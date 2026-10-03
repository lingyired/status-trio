#import "NativeBatteryClient.h"
#import <CoreFoundation/CoreFoundation.h>

NSString * const STMobileBatteryTransportUSB = @"usb";
NSString * const STMobileBatteryTransportNetwork = @"network";

static BOOL IsString(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0;
}

static BOOL IsBoolean(id value) {
    return [value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static NSNumber *ValidatedPercentage(id value) {
    if (![value isKindOfClass:[NSNumber class]] || IsBoolean(value)) return nil;
    CFNumberRef number = (__bridge CFNumberRef)value;
    if (CFNumberIsFloatType(number)) return nil;
    NSInteger percentage = [value integerValue];
    if (percentage < 0 || percentage > 100) return nil;
    return @(percentage);
}

static NSDictionary *BatteryFailure(NSString *category) {
    return @{@"error": category};
}

static NSDictionary *ReadWatch(STMobileBatteryNativeAPI api, void *companion, NSString *identifier) {
    NSDictionary *values = nil;
    NSArray<NSString *> *requiredKeys = @[@"ProductType", @"BatteryCurrentCapacity"];
    int status = api.copyCompanionValues(api.context, companion, identifier, requiredKeys, &values);
    NSDictionary *result = nil;
    NSNumber *percentage = ValidatedPercentage(values[@"BatteryCurrentCapacity"]);
    if (status != 0 || !percentage) {
        result = BatteryFailure(@"battery-unavailable");
    } else {
        NSMutableDictionary *watch = [NSMutableDictionary dictionaryWithDictionary:@{
            @"id": identifier,
            @"batteryLevel": percentage,
        }];
        id name = values[@"DeviceName"];
        id model = values[@"ProductType"];
        id charging = values[@"BatteryIsCharging"];
        if (IsString(name)) watch[@"name"] = name;
        if (IsString(model)) watch[@"model"] = model;
        if (IsBoolean(charging)) watch[@"isCharging"] = charging;
        result = [watch copy];
    }
    if (values) api.freeValues(api.context, values);
    return result;
}

static NSDictionary *ReadPhone(STMobileBatteryNativeAPI api, NSDictionary *device, BOOL includeWatchValues, NSArray<NSString *> **candidateIdentifiers) {
    NSString *identifier = device[@"id"];
    NSString *transport = device[@"transport"];
    NSDictionary *pairRecord = nil;
    void *lockdown = NULL;
    void *session = NULL;
    void *companion = NULL;
    NSDictionary *phoneValues = nil;
    NSArray<NSString *> *watchIdentifiers = nil;
    NSNumber *phonePercentage = nil;
    id phoneName = nil;
    id phoneModel = nil;
    id phoneClass = nil;
    id phoneCharging = nil;
    NSMutableDictionary *phone = [NSMutableDictionary dictionary];

    phone[@"id"] = identifier;
    phone[@"transport"] = transport;

    int recordStatus = api.copyPairRecord(api.context, identifier, &pairRecord);
    if (recordStatus != 0 || ![pairRecord isKindOfClass:[NSDictionary class]]) {
        phone[@"error"] = @"trust-required";
        phone[@"errorCode"] = @(STMobileBatteryErrorTrustRequired);
        goto cleanup;
    }
    if (!IsString(pairRecord[@"HostID"]) || !IsString(pairRecord[@"SystemBUID"])) {
        phone[@"error"] = @"host-identity-missing";
        phone[@"errorCode"] = @(STMobileBatteryErrorHostIdentityMissing);
        goto cleanup;
    }

    if (api.createLockdownClient(api.context, identifier, transport, &lockdown) != 0 || !lockdown) {
        phone[@"error"] = @"session-unavailable";
        goto cleanup;
    }
    if (api.startSession(api.context, lockdown, pairRecord, &session) != 0 || !session) {
        phone[@"error"] = @"session-unavailable";
        goto cleanup;
    }

    int phoneStatus = api.copyPhoneValues(api.context, session, &phoneValues);
    phonePercentage = ValidatedPercentage(phoneValues[@"BatteryCurrentCapacity"]);
    phoneName = phoneValues[@"DeviceName"];
    phoneModel = phoneValues[@"ProductType"];
    phoneClass = phoneValues[@"DeviceClass"];
    phoneCharging = phoneValues[@"BatteryIsCharging"];
    if (IsString(phoneName)) phone[@"name"] = phoneName;
    if (IsString(phoneModel)) phone[@"model"] = phoneModel;
    if (IsString(phoneClass)) phone[@"deviceClass"] = phoneClass;
    if (phoneStatus == 0 && phonePercentage) phone[@"batteryLevel"] = phonePercentage;
    if (IsBoolean(phoneCharging)) phone[@"isCharging"] = phoneCharging;

    if (api.createCompanionClient(api.context, session, &companion) == 0 && companion) {
        if (api.copyCompanionIdentifiers(api.context, companion, &watchIdentifiers) == 0) {
            NSMutableArray<NSString *> *validIdentifiers = [NSMutableArray array];
            for (id watchIdentifier in watchIdentifiers) {
                if (![watchIdentifier isKindOfClass:[NSString class]] || [(NSString *)watchIdentifier length] == 0) continue;
                [validIdentifiers addObject:watchIdentifier];
            }
            if (candidateIdentifiers) *candidateIdentifiers = [validIdentifiers copy];
            if (includeWatchValues) {
                NSMutableArray *watches = [NSMutableArray array];
                for (NSString *watchIdentifier in validIdentifiers) {
                    NSDictionary *watch = ReadWatch(api, companion, watchIdentifier);
                    if (watch) [watches addObject:watch];
                }
                phone[@"watches"] = [watches copy];
            }
        }
    }

    if (phoneStatus != 0 || !phonePercentage) {
        phone[@"error"] = @"battery-unavailable";
        phone[@"errorCode"] = @(STMobileBatteryErrorBatteryUnavailable);
        goto cleanup;
    }

cleanup:
    if (watchIdentifiers) api.freeCompanionIdentifiers(api.context, watchIdentifiers);
    if (companion) api.freeCompanionClient(api.context, companion);
    if (phoneValues) api.freeValues(api.context, phoneValues);
    if (session) api.freeSession(api.context, session);
    if (lockdown) api.freeLockdownClient(api.context, lockdown);
    if (pairRecord) api.freePairRecord(api.context, pairRecord);
    return [phone copy];
}

NSDictionary *STMobileBatteryCopyDeviceList(STMobileBatteryNativeAPI api, STMobileBatteryError *error) {
    if (error) *error = STMobileBatteryErrorNone;
    if (!api.enumerateDevices || !api.freeDeviceList) {
        if (error) *error = STMobileBatteryErrorEnumeration;
        return nil;
    }
    NSArray<NSDictionary *> *devices = nil;
    if (api.enumerateDevices(api.context, &devices) != 0 || ![devices isKindOfClass:[NSArray class]]) {
        if (devices) api.freeDeviceList(api.context, devices);
        if (error) *error = STMobileBatteryErrorEnumeration;
        return nil;
    }
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *availableRoutes = [NSMutableDictionary dictionary];
    for (id candidate in devices) {
        if (![candidate isKindOfClass:[NSDictionary class]]) continue;
        NSString *identifier = candidate[@"id"];
        NSString *transport = candidate[@"transport"];
        if (!IsString(identifier) || (![transport isEqual:STMobileBatteryTransportUSB] && ![transport isEqual:STMobileBatteryTransportNetwork])) continue;
        if (!availableRoutes[identifier]) availableRoutes[identifier] = [NSMutableSet set];
        [availableRoutes[identifier] addObject:transport];
    }
    api.freeDeviceList(api.context, devices);
    NSArray *phones = [[availableRoutes allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:phones.count];
    for (NSString *identifier in phones) {
        NSSet *routes = availableRoutes[identifier];
        NSMutableArray *orderedRoutes = [NSMutableArray arrayWithCapacity:2];
        if ([routes containsObject:STMobileBatteryTransportUSB]) [orderedRoutes addObject:STMobileBatteryTransportUSB];
        if ([routes containsObject:STMobileBatteryTransportNetwork]) [orderedRoutes addObject:STMobileBatteryTransportNetwork];
        NSString *preferred = [routes containsObject:STMobileBatteryTransportUSB] ? STMobileBatteryTransportUSB : STMobileBatteryTransportNetwork;
        [items addObject:@{@"id": identifier, @"transport": preferred, @"availableTransports": [orderedRoutes copy]}];
    }
    return @{@"schemaVersion": @1, @"phones": [items copy]};
}

static NSDictionary *DeviceFailure(NSString *identifier, NSString *transport, NSString *category, STMobileBatteryError code) {
    return @{@"id": identifier, @"transport": transport, @"error": category, @"errorCode": @(code)};
}

NSDictionary *STMobileBatteryCopyPhone(STMobileBatteryNativeAPI api, NSString *identifier, NSString *transport, STMobileBatteryError *error) {
    if (error) *error = STMobileBatteryErrorNone;
    if (!IsString(identifier) || (![transport isEqual:STMobileBatteryTransportUSB] && ![transport isEqual:STMobileBatteryTransportNetwork])) {
        if (error) *error = STMobileBatteryErrorEnumeration;
        return nil;
    }
    NSArray<NSString *> *candidateIdentifiers = nil;
    NSDictionary *phone = ReadPhone(api, @{@"id": identifier, @"transport": transport}, NO, &candidateIdentifiers);
    if (!phone) {
        if (error) *error = STMobileBatteryErrorEnumeration;
        return nil;
    }
    NSString *category = phone[@"error"];
    STMobileBatteryError phoneError = [phone[@"errorCode"] integerValue];
    NSMutableArray *devices = [NSMutableArray array];
    NSMutableArray *failures = [NSMutableArray array];
    if (category) {
        if ([category isEqualToString:@"trust-required"]) phoneError = STMobileBatteryErrorTrustRequired;
        else if ([category isEqualToString:@"host-identity-missing"]) phoneError = STMobileBatteryErrorHostIdentityMissing;
        else if ([category isEqualToString:@"battery-unavailable"]) phoneError = STMobileBatteryErrorBatteryUnavailable;
        [failures addObject:DeviceFailure(identifier, transport, category, phoneError)];
    } else {
        NSMutableDictionary *snapshot = [phone mutableCopy];
        [snapshot removeObjectForKey:@"errorCode"];
        [devices addObject:[snapshot copy]];
    }
    NSMutableArray *candidates = [NSMutableArray arrayWithCapacity:candidateIdentifiers.count];
    for (NSString *watchIdentifier in candidateIdentifiers) {
        [candidates addObject:@{@"id": watchIdentifier, @"parentID": identifier, @"transport": transport}];
    }
    return @{@"schemaVersion": @1, @"devices": [devices copy], @"failures": [failures copy], @"watchCandidates": [candidates copy]};
}

NSDictionary *STMobileBatteryCopyWatch(STMobileBatteryNativeAPI api, NSString *phoneIdentifier, NSString *transport, NSString *watchIdentifier, STMobileBatteryError *error) {
    if (error) *error = STMobileBatteryErrorNone;
    if (!IsString(phoneIdentifier) || !IsString(watchIdentifier) ||
        (![transport isEqual:STMobileBatteryTransportUSB] && ![transport isEqual:STMobileBatteryTransportNetwork])) {
        if (error) *error = STMobileBatteryErrorEnumeration;
        return nil;
    }

    NSDictionary *pairRecord = nil;
    void *lockdown = NULL;
    void *session = NULL;
    void *companion = NULL;
    NSArray<NSString *> *watchIdentifiers = nil;
    NSDictionary *watch = nil;
    NSMutableDictionary *snapshot = nil;
    NSMutableArray *devices = [NSMutableArray array];
    NSMutableArray *failures = [NSMutableArray array];
    NSString *failureCategory = nil;
    STMobileBatteryError failureCode = STMobileBatteryErrorNone;

    int recordStatus = api.copyPairRecord(api.context, phoneIdentifier, &pairRecord);
    if (recordStatus != 0 || ![pairRecord isKindOfClass:[NSDictionary class]]) {
        failureCategory = @"trust-required";
        failureCode = STMobileBatteryErrorTrustRequired;
        goto watch_cleanup;
    }
    if (!IsString(pairRecord[@"HostID"]) || !IsString(pairRecord[@"SystemBUID"])) {
        failureCategory = @"host-identity-missing";
        failureCode = STMobileBatteryErrorHostIdentityMissing;
        goto watch_cleanup;
    }
    if (api.createLockdownClient(api.context, phoneIdentifier, transport, &lockdown) != 0 || !lockdown ||
        api.startSession(api.context, lockdown, pairRecord, &session) != 0 || !session) {
        failureCategory = @"session-unavailable";
        failureCode = STMobileBatteryErrorSession;
        goto watch_cleanup;
    }
    if (api.createCompanionClient(api.context, session, &companion) != 0 || !companion ||
        api.copyCompanionIdentifiers(api.context, companion, &watchIdentifiers) != 0 || !watchIdentifiers) {
        failureCategory = @"watch-unavailable";
        failureCode = STMobileBatteryErrorBatteryUnavailable;
        goto watch_cleanup;
    }
    if (![watchIdentifiers containsObject:watchIdentifier]) {
        failureCategory = @"watch-not-paired";
        failureCode = STMobileBatteryErrorTrustRequired;
        goto watch_cleanup;
    }
    watch = ReadWatch(api, companion, watchIdentifier);
    if (!watch || watch[@"error"]) {
        failureCategory = @"battery-unavailable";
        failureCode = STMobileBatteryErrorBatteryUnavailable;
        goto watch_cleanup;
    }
    snapshot = [watch mutableCopy];
    snapshot[@"parentID"] = phoneIdentifier;
    snapshot[@"transport"] = transport;
    [devices addObject:[snapshot copy]];

watch_cleanup:
    if (failureCategory) [failures addObject:DeviceFailure(watchIdentifier, transport, failureCategory, failureCode)];
    if (watchIdentifiers) api.freeCompanionIdentifiers(api.context, watchIdentifiers);
    if (companion) api.freeCompanionClient(api.context, companion);
    if (session) api.freeSession(api.context, session);
    if (lockdown) api.freeLockdownClient(api.context, lockdown);
    if (pairRecord) api.freePairRecord(api.context, pairRecord);
    return @{@"schemaVersion": @1, @"devices": [devices copy], @"failures": [failures copy], @"watchCandidates": @[]};
}
