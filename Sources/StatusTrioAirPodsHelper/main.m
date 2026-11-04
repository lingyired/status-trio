#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import <limits.h>

@interface NSObject (AirPodsAudio)
+ (id)sharedSystemAudioContext;
- (id)outputDevice;
- (NSString *)associatedAudioDeviceID;
- (NSString *)deviceID;
- (BOOL)supportsConversationDetection;
- (BOOL)isConversationDetectionEnabled;
- (BOOL)setConversationDetectionEnabled:(BOOL)value error:(NSError **)error;
@end

// The helper runs as the user, has no service registration or IPC listener, and
// accepts only a current output UID and an allowlisted operation. No UI APIs.
static BOOL currentRouteMatches(NSString *uid) {
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, 0};
    AudioDeviceID device = 0; UInt32 size = sizeof(device);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device)) return NO;
    address.mSelector = kAudioDevicePropertyDeviceUID;
    CFStringRef actual = NULL; size = sizeof(actual);
    if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &actual) || !actual) return NO;
    BOOL matches = [(__bridge NSString *)actual isEqualToString:uid];
    CFRelease(actual);
    return matches;
}

static id endpoint(id context, NSString *uid, NSString *identity) {
    if (![context respondsToSelector:@selector(outputDevice)] ||
        ![context respondsToSelector:@selector(associatedAudioDeviceID)] || !currentRouteMatches(uid)) return nil;
    id device = [context outputDevice];
    if (![device respondsToSelector:@selector(deviceID)] ||
        ![[context associatedAudioDeviceID] isEqualToString:uid]) return nil;
    if (identity && ![[device deviceID] isEqualToString:identity]) return nil;
    return device;
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc == 2 && !strcmp(argv[1], "--self-test")) {
        // Invalid invocations must terminate without touching any audio framework.
        puts("{\"protocol\":1}"); return 0;
    }
    if (argc != 3) return 2;
    NSString *operation = @(argv[1]), *uid = @(argv[2]);
    if (![@[@"read", @"ca-on", @"ca-off"] containsObject:operation] || uid.length == 0 || uid.length > 512) return 2;
    alarm(4);
    // Inject only into a re-exec of this short-lived helper, never the app or a
    // system process. All other Security entitlement queries pass through.
    if (!getenv("ST_AIRPODS_CONTEXT_READY")) {
        char path[PATH_MAX]; uint32_t length = sizeof(path);
        if (_NSGetExecutablePath(path, &length)) return 3;
        NSString *executable = [@(path) stringByResolvingSymlinksInPath];
        NSString *library = [[executable stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"libAirPodsAudioContext.dylib"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:library]) return 3;
        setenv("DYLD_INSERT_LIBRARIES", library.fileSystemRepresentation, 1);
        setenv("ST_AIRPODS_CONTEXT_READY", "1", 1);
        execv(executable.fileSystemRepresentation, argv);
        return 3;
    }
    dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_NOW);
    Class provider = NSClassFromString(@"AVOutputContext");
    if (![provider respondsToSelector:@selector(sharedSystemAudioContext)]) return 3;
    id context = [provider sharedSystemAudioContext];
    id device = endpoint(context, uid, nil);
    if (!device) return 4;
    NSString *identity = [[device deviceID] copy];
    if (identity.length == 0 || ![device respondsToSelector:@selector(supportsConversationDetection)] ||
        ![device respondsToSelector:@selector(isConversationDetectionEnabled)]) return 3;
    if (![device supportsConversationDetection]) { puts("{\"conversationSupported\":false}"); return [operation isEqualToString:@"read"] ? 0 : 3; }
    if (![operation isEqualToString:@"read"]) {
        BOOL desired = [operation isEqualToString:@"ca-on"];
        device = endpoint(context, uid, identity);
        if (!device) return 4;
        if (![device respondsToSelector:@selector(setConversationDetectionEnabled:error:)]) return 3;
        if ([device isConversationDetectionEnabled] != desired) {
            NSError *error = nil;
            if (![device setConversationDetectionEnabled:desired error:&error]) return 5;
            BOOL confirmed = NO;
            for (int attempt = 0; attempt < 30; attempt++) {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                device = endpoint(context, uid, identity);
                if (!device) return 4;
                if ([device isConversationDetectionEnabled] == desired) { confirmed = YES; break; }
            }
            if (!confirmed) return 5;
        }
    }
    device = endpoint(context, uid, identity);
    if (!device) return 4;
    printf("{\"conversationSupported\":true,\"conversation\":%s}\n", [device isConversationDetectionEnabled] ? "true" : "false");
    return 0;
}}
