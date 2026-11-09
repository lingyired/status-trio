/*
 * avbypass.dylib — interposes SecTaskCopyValueForEntitlement so that the
 * private `com.apple.avfoundation.allow-system-wide-context` entitlement check
 * (performed in-process by AVFoundation when acquiring the shared system audio
 * context) reports the entitlement as present. This is what lets an
 * unprivileged helper reach AVOutputDevice's listening-mode API — the same
 * mechanism NoiseBuddy uses.
 *
 * It only ever forges that one entitlement; every other query is passed through
 * to the real implementation unchanged. Ships as a dylib inserted via
 * DYLD_INSERT_LIBRARIES (an in-binary interpose does not work — the
 * AVFoundation -> Security call is resolved inside the dyld shared cache and is
 * only rewritten for an inserted image).
 */
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>

extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task,
                                                CFStringRef entitlement,
                                                CFErrorRef *error);

static CFTypeRef my_SecTaskCopyValueForEntitlement(SecTaskRef task,
                                                   CFStringRef entitlement,
                                                   CFErrorRef *error) {
  if (entitlement &&
      CFStringCompare(entitlement,
                      CFSTR("com.apple.avfoundation.allow-system-wide-context"),
                      0) == kCFCompareEqualTo) {
    return CFRetain(kCFBooleanTrue); /* Copy semantics: caller releases. */
  }
  return SecTaskCopyValueForEntitlement(task, entitlement, error);
}

__attribute__((used)) static struct {
  const void *replacement;
  const void *original;
} _interpose_SecTask __attribute__((section("__DATA,__interpose"))) = {
    (const void *)my_SecTaskCopyValueForEntitlement,
    (const void *)SecTaskCopyValueForEntitlement,
};
