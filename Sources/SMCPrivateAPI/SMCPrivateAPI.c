#include "SMCPrivateAPI.h"
#include <IOKit/IOKitLib.h>
#include <pthread.h>
#include <stddef.h>
#include <string.h>

/* Undocumented AppleSMC user-client ABI. These request layouts are facts
 * established by independent clients, not an Apple public compatibility promise.
 * Keep all I/O in this file and fail closed on changed response/metadata shapes. */
#define SMC_SELECTOR 2
#define SMC_READ_BYTES 5
#define SMC_WRITE_BYTES 6
#define SMC_READ_INFO 9

typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} SMCVersion;
typedef struct {
    uint16_t version, length;
    uint32_t cpu, gpu, memory;
} SMCLimits;
typedef struct {
    uint32_t size, type;
    uint8_t attributes;
} SMCInfo;
typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCLimits limits;
    SMCInfo info;
    uint8_t result, status, command;
    uint32_t data;
    uint8_t bytes[32];
} SMCMessage;

_Static_assert(sizeof(SMCMessage) == 80, "Unexpected AppleSMC request layout");
_Static_assert(offsetof(SMCMessage, bytes) == 48, "Unexpected AppleSMC payload offset");

/* Reference-counted shared user client. Serialization is in C so a second
 * Swift executor cannot race another instance's open, close, read or write. */
static pthread_mutex_t connectionLock = PTHREAD_MUTEX_INITIALIZER;
static io_connect_t connection = 0;
static unsigned int users = 0;

static uint32_t fourcc(const char *key) {
    return ((uint32_t)(uint8_t)key[0] << 24) | ((uint32_t)(uint8_t)key[1] << 16)
        | ((uint32_t)(uint8_t)key[2] << 8) | (uint8_t)key[3];
}

bool STSMIsWriteAllowlisted(const char *key) {
    if (key == NULL || strlen(key) != 4) return false;
    return strcmp(key, "BCLM") == 0 || strcmp(key, "CH0B") == 0
        || strcmp(key, "CH0C") == 0 || strcmp(key, "CHTE") == 0;
}

bool STSMValidateChargeKeyInfo(const char *key, const char *type, uint32_t size) {
    if (!STSMIsWriteAllowlisted(key) || type == NULL) return false;
    if (strcmp(key, "CHTE") == 0) return size == 4 && memcmp(type, "ui32", 4) == 0;
    return size == 1 && memcmp(type, "ui8 ", 4) == 0;
}

bool STSMValidateChargeWrite(const char *key, const uint8_t *bytes, uint32_t size) {
    if (!STSMIsWriteAllowlisted(key) || bytes == NULL) return false;
    if (strcmp(key, "BCLM") == 0) return size == 1 && bytes[0] >= 50 && bytes[0] <= 100;
    if (strcmp(key, "CHTE") == 0) {
        return size == 4 && (bytes[0] == 0 || bytes[0] == 1)
            && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0;
    }
    return size == 1 && (bytes[0] == 0 || bytes[0] == 2);
}

int STSMCOpen(void) {
    pthread_mutex_lock(&connectionLock);
    if (users > 0) {
        users++;
        pthread_mutex_unlock(&connectionLock);
        return 0;
    }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    kern_return_t result = kIOReturnNotFound;
    if (service != 0) {
        result = IOServiceOpen(service, mach_task_self(), 0, &connection);
        IOObjectRelease(service);
    }
    if (result == KERN_SUCCESS) users = 1;
    else connection = 0;
    pthread_mutex_unlock(&connectionLock);
    return result == KERN_SUCCESS ? 0 : -1;
}

void STSMClose(void) {
    pthread_mutex_lock(&connectionLock);
    if (users > 0 && --users == 0) {
        IOServiceClose(connection);
        connection = 0;
    }
    pthread_mutex_unlock(&connectionLock);
}

/* All callers hold connectionLock. */
static bool callSMC(SMCMessage *input, SMCMessage *output) {
    size_t outputSize = sizeof(*output);
    kern_return_t result = IOConnectCallStructMethod(
        connection, SMC_SELECTOR, input, sizeof(*input), output, &outputSize
    );
    return result == KERN_SUCCESS && outputSize == sizeof(*output) && output->result == 0;
}

static bool chargeKeyInfo(const char *key, SMCInfo *info) {
    SMCMessage input = {0}, output = {0};
    input.key = fourcc(key);
    input.command = SMC_READ_INFO;
    if (!callSMC(&input, &output)) return false;
    char type[4];
    for (unsigned int i = 0; i < 4; i++) type[i] = (char)(output.info.type >> (24 - 8 * i));
    if (!STSMValidateChargeKeyInfo(key, type, output.info.size)) return false;
    *info = output.info;
    return true;
}

bool STSMReadKey(const char *key, STSMReadResult *out) {
    if (out == NULL) return false;
    memset(out, 0, sizeof(*out));
    if (!STSMIsWriteAllowlisted(key)) return false;
    pthread_mutex_lock(&connectionLock);
    bool ok = false;
    if (users == 0) goto done;
    SMCInfo info;
    if (!chargeKeyInfo(key, &info)) goto done;
    SMCMessage input = {0}, output = {0};
    input.key = fourcc(key);
    input.info.size = info.size;
    input.command = SMC_READ_BYTES;
    if (!callSMC(&input, &output)) goto done;
    // A key with the right metadata but an unknown firmware value is read-only
    // to this feature: do not take ownership of something we cannot restore.
    if (!STSMValidateChargeWrite(key, output.bytes, info.size)) goto done;
    memcpy(out->key, key, 4);
    for (unsigned int i = 0; i < 4; i++) out->info.dataType[i] = (uint8_t)(info.type >> (24 - 8 * i));
    out->info.dataSize = info.size;
    out->info.valid = true;
    memcpy(out->bytes, output.bytes, info.size);
    out->bytesRead = info.size;
    out->ok = true;
    ok = true;
done:
    pthread_mutex_unlock(&connectionLock);
    return ok;
}

bool STSMWriteKeyAllowlisted(const char *key, const uint8_t *bytes, uint32_t size) {
    if (!STSMValidateChargeWrite(key, bytes, size)) return false;
    pthread_mutex_lock(&connectionLock);
    bool ok = false;
    if (users == 0) goto done;
    SMCInfo info;
    // Check live key metadata immediately before every write. A same-width
    // key of another type is never treated as compatible.
    if (!chargeKeyInfo(key, &info) || info.size != size) goto done;
    SMCMessage input = {0}, output = {0};
    input.key = fourcc(key);
    input.info.size = size;
    input.command = SMC_WRITE_BYTES;
    memcpy(input.bytes, bytes, size);
    ok = callSMC(&input, &output);
done:
    pthread_mutex_unlock(&connectionLock);
    return ok;
}

bool STSMReadKeyCopy(const char *key, uint8_t *outBytes, uint32_t capacity, uint32_t *outSize) {
    if (outSize == NULL) return false;
    *outSize = 0;
    if (outBytes == NULL || capacity == 0) return false;
    STSMReadResult result;
    if (!STSMReadKey(key, &result) || result.bytesRead > capacity) return false;
    memcpy(outBytes, result.bytes, result.bytesRead);
    *outSize = result.bytesRead;
    return true;
}
