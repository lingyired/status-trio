#import "NativeBatteryClient.h"
#include <libimobiledevice/companion_proxy.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <plist/plist.h>
#include <usbmuxd.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    idevice_t device;
    lockdownd_client_t client;
} STNativeLockdown;

typedef struct {
    STNativeLockdown *lockdown;
    char *sessionIdentifier;
} STNativeSession;

typedef struct {
    STNativeSession *session;
} STNativeCompanion;

static BOOL NativeIsString(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0;
}

static NSString *StringFromPlist(plist_t node) {
    if (!node || plist_get_node_type(node) != PLIST_STRING) return nil;
    char *value = NULL;
    plist_get_string_val(node, &value);
    if (!value) return nil;
    NSString *result = [NSString stringWithUTF8String:value];
    free(value);
    return result;
}

static id ObjectFromPlist(plist_t node) {
    if (!node) return nil;
    switch (plist_get_node_type(node)) {
        case PLIST_STRING:
            return StringFromPlist(node);
        case PLIST_BOOLEAN: {
            uint8_t value = 0;
            plist_get_bool_val(node, &value);
            return @(value != 0);
        }
        case PLIST_UINT: {
            uint64_t value = 0;
            plist_get_uint_val(node, &value);
            return @(value);
        }
        case PLIST_REAL: {
            double value = 0;
            plist_get_real_val(node, &value);
            return @(value);
        }
        default:
            return [NSNull null];
    }
}

static NSDictionary *DictionaryFromPlist(plist_t dict) {
    if (!dict || plist_get_node_type(dict) != PLIST_DICT) return nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    plist_dict_iter iterator = NULL;
    plist_dict_new_iter(dict, &iterator);
    if (!iterator) return result;
    char *key = NULL;
    plist_t value = NULL;
    do {
        plist_dict_next_item(dict, iterator, &key, &value);
        if (key && value) {
            NSString *name = [NSString stringWithUTF8String:key];
            id object = ObjectFromPlist(value);
            if (name && object) result[name] = object;
        }
        free(key);
        key = NULL;
    } while (value);
    free(iterator);
    return result;
}

static int NativeEnumerate(void *context, NSArray<NSDictionary *> **devices) {
    (void)context;
    idevice_info_t *nativeDevices = NULL;
    int count = 0;
    if (idevice_get_device_list_extended(&nativeDevices, &count) != IDEVICE_E_SUCCESS) return -1;
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(count, 0)];
    for (int index = 0; index < count; index++) {
        idevice_info_t entry = nativeDevices[index];
        if (!entry || !entry->udid) continue;
        NSString *identifier = [NSString stringWithUTF8String:entry->udid];
        NSString *transport = entry->conn_type == CONNECTION_NETWORK ? STMobileBatteryTransportNetwork : STMobileBatteryTransportUSB;
        if (identifier) [result addObject:@{@"id": identifier, @"transport": transport}];
    }
    idevice_device_list_extended_free(nativeDevices);
    *devices = [result copy];
    return 0;
}

static int NativeCopyPairRecord(void *context, NSString *identifier, NSDictionary **record) {
    (void)context;
    char *recordData = NULL;
    uint32_t recordSize = 0;
    const char *udid = identifier.UTF8String;
    if (!udid || usbmuxd_read_pair_record(udid, &recordData, &recordSize) != 0 || !recordData || recordSize == 0) {
        free(recordData);
        return -1;
    }
    plist_t pairRecord = NULL;
    plist_err_t parseResult = plist_from_memory(recordData, recordSize, &pairRecord, NULL);
    free(recordData);
    if (parseResult != PLIST_ERR_SUCCESS || !pairRecord || plist_get_node_type(pairRecord) != PLIST_DICT) {
        plist_free(pairRecord);
        return -1;
    }

    NSString *hostID = StringFromPlist(plist_dict_get_item(pairRecord, "HostID"));
    NSString *recordBUID = StringFromPlist(plist_dict_get_item(pairRecord, "SystemBUID"));
    char *systemBUID = NULL;
    int buidResult = usbmuxd_read_buid(&systemBUID);
    NSString *daemonBUID = systemBUID ? [NSString stringWithUTF8String:systemBUID] : nil;
    free(systemBUID);
    plist_free(pairRecord);
    if (!NativeIsString(hostID) || !NativeIsString(recordBUID) || buidResult != 0 || ![recordBUID isEqualToString:daemonBUID]) return -1;
    *record = @{@"HostID": hostID, @"SystemBUID": recordBUID};
    return 0;
}

static void NativeFreeObject(void *context, id object) { (void)context; (void)object; }

static int NativeCreateLockdown(void *context, NSString *identifier, NSString *transport, void **client) {
    (void)context;
    idevice_t device = NULL;
    enum idevice_options options = [transport isEqualToString:STMobileBatteryTransportNetwork] ? IDEVICE_LOOKUP_NETWORK : IDEVICE_LOOKUP_USBMUX;
    if (idevice_new_with_options(&device, identifier.UTF8String, options) != IDEVICE_E_SUCCESS || !device) return -1;
    lockdownd_client_t lockdown = NULL;
    if (lockdownd_client_new(device, &lockdown, "StatusTrioMobileBattery") != LOCKDOWN_E_SUCCESS || !lockdown) {
        if (lockdown) lockdownd_client_free(lockdown);
        idevice_free(device);
        return -1;
    }
    STNativeLockdown *handle = calloc(1, sizeof(STNativeLockdown));
    if (!handle) {
        lockdownd_client_free(lockdown);
        idevice_free(device);
        return -1;
    }
    handle->device = device;
    handle->client = lockdown;
    *client = handle;
    return 0;
}

static int NativeStartSession(void *context, void *client, NSDictionary *record, void **session) {
    (void)context;
    STNativeLockdown *lockdown = client;
    NSString *hostID = record[@"HostID"];
    if (!lockdown || !NativeIsString(hostID)) return -1;
    STNativeSession *handle = calloc(1, sizeof(STNativeSession));
    if (!handle) return -1;
    if (lockdownd_start_session(lockdown->client, hostID.UTF8String, &handle->sessionIdentifier, NULL) != LOCKDOWN_E_SUCCESS) {
        free(handle->sessionIdentifier);
        free(handle);
        return -1;
    }
    handle->lockdown = lockdown;
    *session = handle;
    return 0;
}

static void NativeFreeSession(void *context, void *session) {
    (void)context;
    STNativeSession *handle = session;
    if (!handle) return;
    if (handle->sessionIdentifier) {
        lockdownd_stop_session(handle->lockdown->client, handle->sessionIdentifier);
        free(handle->sessionIdentifier);
    }
    free(handle);
}

static void NativeFreeLockdown(void *context, void *client) {
    (void)context;
    STNativeLockdown *handle = client;
    if (!handle) return;
    lockdownd_client_free(handle->client);
    idevice_free(handle->device);
    free(handle);
}

static int CopyLockdownValue(lockdownd_client_t client, const char *domain, const char *key, NSMutableDictionary *values) {
    plist_t node = NULL;
    if (lockdownd_get_value(client, domain, key, &node) != LOCKDOWN_E_SUCCESS || !node) {
        plist_free(node);
        return -1;
    }
    id object = ObjectFromPlist(node);
    if (object) values[@(key)] = object;
    plist_free(node);
    return object ? 0 : -1;
}

static int NativeCopyPhoneValues(void *context, void *session, NSDictionary **values) {
    (void)context;
    STNativeSession *handle = session;
    if (!handle) return -1;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    CopyLockdownValue(handle->lockdown->client, NULL, "DeviceName", result);
    CopyLockdownValue(handle->lockdown->client, NULL, "ProductType", result);
    CopyLockdownValue(handle->lockdown->client, NULL, "DeviceClass", result);
    CopyLockdownValue(handle->lockdown->client, "com.apple.mobile.battery", "BatteryCurrentCapacity", result);
    CopyLockdownValue(handle->lockdown->client, "com.apple.mobile.battery", "BatteryIsCharging", result);
    *values = [result copy];
    return 0;
}

static int NativeCreateCompanion(void *context, void *session, void **companion) {
    (void)context;
    if (!session) return -1;
    STNativeCompanion *handle = calloc(1, sizeof(STNativeCompanion));
    if (!handle) return -1;
    handle->session = session;
    *companion = handle;
    return 0;
}

static companion_proxy_client_t OpenCompanion(STNativeSession *session) {
    lockdownd_service_descriptor_t service = NULL;
    if (lockdownd_start_service(session->lockdown->client, COMPANION_PROXY_SERVICE_NAME, &service) != LOCKDOWN_E_SUCCESS || !service) {
        lockdownd_service_descriptor_free(service);
        return NULL;
    }
    companion_proxy_client_t client = NULL;
    companion_proxy_client_new(session->lockdown->device, service, &client);
    lockdownd_service_descriptor_free(service);
    return client;
}

static int NativeCopyCompanionIdentifiers(void *context, void *companion, NSArray<NSString *> **identifiers) {
    (void)context;
    STNativeCompanion *handle = companion;
    companion_proxy_client_t client = OpenCompanion(handle->session);
    if (!client) return -1;
    plist_t registry = NULL;
    companion_proxy_error_t status = companion_proxy_get_device_registry(client, &registry);
    companion_proxy_client_free(client);
    if (status != COMPANION_PROXY_E_SUCCESS || !registry || plist_get_node_type(registry) != PLIST_ARRAY) {
        plist_free(registry);
        return -1;
    }
    NSMutableArray *result = [NSMutableArray array];
    uint32_t count = plist_array_get_size(registry);
    for (uint32_t index = 0; index < count; index++) {
        NSString *identifier = StringFromPlist(plist_array_get_item(registry, index));
        if (NativeIsString(identifier)) [result addObject:identifier];
    }
    plist_free(registry);
    *identifiers = [result copy];
    return 0;
}

static int NativeCopyCompanionValues(void *context, void *companion, NSString *identifier, NSArray<NSString *> *keys, NSDictionary **values) {
    (void)context;
    STNativeCompanion *handle = companion;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        companion_proxy_client_t client = OpenCompanion(handle->session);
        if (!client) continue;
        plist_t response = NULL;
        companion_proxy_error_t status = companion_proxy_get_value_from_registry(client, identifier.UTF8String, key.UTF8String, &response);
        companion_proxy_client_free(client);
        if (status == COMPANION_PROXY_E_SUCCESS && response) {
            plist_t value = plist_dict_get_item(response, key.UTF8String);
            id object = ObjectFromPlist(value);
            if (object) result[key] = object;
        }
        plist_free(response);
    }
    *values = [result copy];
    return 0;
}

static void NativeFreeCompanion(void *context, void *companion) { (void)context; free(companion); }

STMobileBatteryNativeAPI STMobileBatteryProductionAPI(void) {
    return (STMobileBatteryNativeAPI){
        .context = NULL,
        .enumerateDevices = NativeEnumerate,
        .copyPairRecord = NativeCopyPairRecord,
        .freePairRecord = NativeFreeObject,
        .createLockdownClient = NativeCreateLockdown,
        .startSession = NativeStartSession,
        .freeSession = NativeFreeSession,
        .freeLockdownClient = NativeFreeLockdown,
        .copyPhoneValues = NativeCopyPhoneValues,
        .createCompanionClient = NativeCreateCompanion,
        .copyCompanionIdentifiers = NativeCopyCompanionIdentifiers,
        .copyCompanionValues = NativeCopyCompanionValues,
        .freeCompanionIdentifiers = NativeFreeObject,
        .freeCompanionClient = NativeFreeCompanion,
        .freeValues = NativeFreeObject,
        .freeDeviceList = NativeFreeObject,
    };
}

static BOOL IsTransport(NSString *value) {
    return [value isEqualToString:STMobileBatteryTransportUSB] || [value isEqualToString:STMobileBatteryTransportNetwork];
}

static int WriteJSON(NSDictionary *payload) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingFragmentsAllowed error:&error];
    if (!data) {
        fputs("mobile battery helper: json-serialization-failed\n", stderr);
        return 1;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        STMobileBatteryNativeAPI api = STMobileBatteryProductionAPI();
        STMobileBatteryError error = STMobileBatteryErrorNone;
        NSDictionary *payload = nil;
        if (argc == 2 && strcmp(argv[1], "--list") == 0) {
            payload = STMobileBatteryCopyDeviceList(api, &error);
        } else if (argc == 5 && strcmp(argv[1], "--read-phone") == 0 && strcmp(argv[3], "--transport") == 0) {
            NSString *identifier = [NSString stringWithUTF8String:argv[2]];
            NSString *transport = [NSString stringWithUTF8String:argv[4]];
            if (IsTransport(transport)) payload = STMobileBatteryCopyPhone(api, identifier, transport, &error);
        } else if (argc == 7 && strcmp(argv[1], "--read-watch") == 0 && strcmp(argv[3], "--watch-id") == 0 && strcmp(argv[5], "--transport") == 0) {
            NSString *phoneIdentifier = [NSString stringWithUTF8String:argv[2]];
            NSString *watchIdentifier = [NSString stringWithUTF8String:argv[4]];
            NSString *transport = [NSString stringWithUTF8String:argv[6]];
            if (IsTransport(transport)) payload = STMobileBatteryCopyWatch(api, phoneIdentifier, transport, watchIdentifier, &error);
        }

        if (!payload) {
            fputs("mobile battery helper: enumeration-or-arguments-failed\n", stderr);
            return 1;
        }
        return WriteJSON(payload);
    }
}
