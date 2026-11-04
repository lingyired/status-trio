#include "SMCPrivateAPI.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

/*
 * AppleSMC user-client request/response shape. These struct layouts are the
 * public IOKit interface shape documented by the AppleSMC kernel service.
 */
#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCKeyDataVers;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyDataPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyDataKeyInfo;

typedef struct {
    uint32_t key;
    SMCKeyDataVers vers;
    SMCKeyDataPLimitData pLimitData;
    SMCKeyDataKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static io_connect_t g_conn = 0;
static bool g_open = false;

/* Keys this bridge is allowed to write. Everything else is refused. */
static const char *const kWriteAllowlist[] = {
    "BCLM", /* Intel firmware ceiling (ui8) */
    "CH0B", /* Apple Silicon legacy inhibit (ui8) */
    "CH0C", /* Apple Silicon legacy inhibit (ui8) */
    "CHTE", /* Apple Silicon Tahoe-era inhibit (ui32) */
};

static uint32_t fourcc(const char *key) {
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) {
        v = (v << 8) | (uint8_t)key[i];
    }
    return v;
}

bool STSMIsWriteAllowlisted(const char *key) {
    if (key == NULL) {
        return false;
    }
    for (size_t i = 0; i < sizeof(kWriteAllowlist) / sizeof(kWriteAllowlist[0]); i++) {
        if (strncmp(key, kWriteAllowlist[i], 4) == 0) {
            return true;
        }
    }
    return false;
}

int STSMCOpen(void) {
    if (g_open) {
        return 0;
    }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        return -1;
    }
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) {
        g_conn = 0;
        return -1;
    }
    g_open = true;
    return 0;
}

void STSMClose(void) {
    if (g_open) {
        IOServiceClose(g_conn);
        g_conn = 0;
        g_open = false;
    }
}

static bool smc_call(SMCKeyData *input, SMCKeyData *output) {
    size_t outSize = sizeof(SMCKeyData);
    kern_return_t kr = IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, input, sizeof(SMCKeyData), output, &outSize);
    return kr == KERN_SUCCESS;
}

static bool read_key_info(uint32_t key, SMCKeyDataKeyInfo *info) {
    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = SMC_CMD_READ_KEYINFO;
    if (!smc_call(&input, &output)) {
        return false;
    }
    if (output.result != 0) {
        return false;
    }
    *info = output.keyInfo;
    return true;
}

bool STSMReadKey(const char *key, STSMReadResult *out) {
    if (key == NULL || out == NULL || !g_open) {
        return false;
    }
    memset(out, 0, sizeof(*out));
    strncpy((char *)out->key, key, 4);

    uint32_t keyCode = fourcc(key);
    SMCKeyDataKeyInfo info;
    if (!read_key_info(keyCode, &info)) {
        return false;
    }
    if (info.dataSize > sizeof(out->bytes)) {
        return false;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = keyCode;
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = SMC_CMD_READ_BYTES;
    if (!smc_call(&input, &output) || output.result != 0) {
        return false;
    }

    memcpy(out->info.dataType, &info.dataType, 4);
    out->info.dataSize = info.dataSize;
    out->info.valid = true;
    memcpy(out->bytes, output.bytes, info.dataSize);
    out->bytesRead = info.dataSize;
    out->ok = true;
    return true;
}

bool STSMWriteKeyAllowlisted(const char *key, const uint8_t *bytes, uint32_t size) {
    if (key == NULL || bytes == NULL || size == 0 || size > 32 || !g_open) {
        return false;
    }
    if (!STSMIsWriteAllowlisted(key)) {
        return false;
    }

    uint32_t keyCode = fourcc(key);
    SMCKeyDataKeyInfo info;
    if (!read_key_info(keyCode, &info)) {
        return false;
    }
    if (info.dataSize != size || size > sizeof(((SMCKeyData *)0)->bytes)) {
        return false;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = keyCode;
    input.keyInfo.dataSize = size;
    input.data8 = SMC_CMD_WRITE_BYTES;
    memcpy(input.bytes, bytes, size);
    if (!smc_call(&input, &output)) {
        return false;
    }
    return output.result == 0;
}