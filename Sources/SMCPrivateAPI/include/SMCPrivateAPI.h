#ifndef SMC_PRIVATE_API_H
#define SMC_PRIVATE_API_H

/*
 * Minimal AppleSMC access for the legacy charge limiter.
 *
 * Independently implemented against the undocumented AppleSMC user-client
 * ABI observed by open-source SMC tools. This is not an Apple public API or
 * compatibility promise. No third-party source is copied; unexpected metadata
 * and response layouts are rejected.
 *
 * SAFETY: writes are restricted to an explicit allowlist inside the
 * implementation. No arbitrary key writes are exposed. This bridge is only
 * linked into the root helper.
 */

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint8_t dataType[4];
    uint32_t dataSize;
    bool valid;
} STSMKeyInfo;

typedef struct {
    uint8_t key[5];      /* NUL-terminated 4-char key */
    STSMKeyInfo info;
    uint8_t bytes[32];
    uint32_t bytesRead;
    bool ok;
} STSMReadResult;

/* Opens the AppleSMC user client. Returns 0 on success. */
int STSMCOpen(void);

/* Closes the user client. */
void STSMClose(void);

/* Reads a key. Returns true when the key exists and was read. */
bool STSMReadKey(const char *key, STSMReadResult *out);

/* Reads a key into a caller buffer. Returns true and sets `outSize` when the
 * key exists and fits; the caller compares `outSize` with the expected width. */
bool STSMReadKeyCopy(const char *key,
                     uint8_t *outBytes,
                     uint32_t capacity,
                     uint32_t *outSize);

/* Writes bytes to an allowlisted key. Returns true when the write returned OK.
 * The caller must still perform a readback to verify. Non-allowlisted keys are
 * rejected (false) without touching the SMC. */
bool STSMWriteKeyAllowlisted(const char *key, const uint8_t *bytes, uint32_t size);

/* Pure validation also used by the read/write implementation. These never
 * open a connection or issue IOKit calls. Data types are four ASCII bytes
 * ("ui8 " includes the trailing space). */
bool STSMValidateChargeKeyInfo(const char *key, const char *dataType, uint32_t size);
bool STSMValidateChargeWrite(const char *key, const uint8_t *bytes, uint32_t size);

/* Returns true only for an exact four-character allowlisted key. */
bool STSMIsWriteAllowlisted(const char *key);

#endif /* SMC_PRIVATE_API_H */