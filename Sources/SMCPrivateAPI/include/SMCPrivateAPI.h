#ifndef SMC_PRIVATE_API_H
#define SMC_PRIVATE_API_H

/*
 * Minimal AppleSMC access for the legacy charge limiter.
 *
 * Implemented independently from the public IOKit AppleSMC user-client
 * interface (the same interface documented by smc-command and used by every
 * SMC tool). No third-party source is copied; the struct layout is the
 * publicly documented IOKit request/response shape.
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

/* Writes bytes to an allowlisted key. Returns true when the write returned OK.
 * The caller must still perform a readback to verify. Non-allowlisted keys are
 * rejected (false) without touching the SMC. */
bool STSMWriteKeyAllowlisted(const char *key, const uint8_t *bytes, uint32_t size);

/* Returns true when the key is in the hard-coded write allowlist. */
bool STSMIsWriteAllowlisted(const char *key);

#endif /* SMC_PRIVATE_API_H */