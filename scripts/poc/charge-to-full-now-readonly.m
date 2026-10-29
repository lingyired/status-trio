// Standalone research only. This file is not part of any app target.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL ProbePlatformSupported(NSOperatingSystemVersion version, BOOL isArm64) {
    return isArm64 && (version.majorVersion > 26 ||
                      (version.majorVersion == 26 && version.minorVersion >= 4));
}

static BOOL ProbeSignatureMatches(Class cls, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    if (cls == Nil) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) return NO;
    const char *types = method_getTypeEncoding(method);
    if (types == NULL) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:types];
    if (strcmp(signature.methodReturnType, result) != 0 ||
        signature.numberOfArguments != arguments.count + 2) return NO;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        if (strcmp([signature getArgumentTypeAtIndex:index + 2], arguments[index].UTF8String) != 0) return NO;
    }
    return YES;
}

#if !defined(CHARGE_TO_FULL_NOW_POC_TESTS)
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <dlfcn.h>

@protocol ChargeProbeReadOnlyClient
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (NSUInteger)isMCLCurrentlyEnabled:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)smartChargingUIState:(NSUInteger *)state
                 chargeLimit:(NSUInteger *)limit
     chargingOverrideAllowed:(BOOL *)allowed
                   withError:(NSError **)error;
@end

static NSDictionary *ProbeBattery(void) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (info == NULL) return @{@"readSucceeded": @NO};
    CFArrayRef sources = IOPSCopyPowerSourcesList(info);
    NSDictionary *reading = @{@"readSucceeded": @(sources != NULL), @"isPresent": @NO};
    if (sources != NULL) {
        for (CFIndex index = 0; index < CFArrayGetCount(sources); index++) {
            CFTypeRef source = CFArrayGetValueAtIndex(sources, index);
            NSDictionary *description = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, source);
            if (![description[@kIOPSTypeKey] isEqual:@kIOPSInternalBatteryType]) continue;
            NSNumber *current = description[@kIOPSCurrentCapacityKey];
            NSNumber *maximum = description[@kIOPSMaxCapacityKey];
            id percentage = NSNull.null;
            if ([current isKindOfClass:NSNumber.class] && [maximum isKindOfClass:NSNumber.class] &&
                maximum.doubleValue > 0) {
                percentage = @(100.0 * current.doubleValue / maximum.doubleValue);
            }
            reading = @{
                @"readSucceeded": @YES,
                @"isPresent": @([description[@kIOPSIsPresentKey] boolValue]),
                @"isConnectedToPower": @([description[@kIOPSPowerSourceStateKey] isEqual:@kIOPSACPowerValue]),
                @"isCharging": @([description[@kIOPSIsChargingKey] boolValue]),
                @"isCharged": @([description[@kIOPSIsChargedKey] boolValue]),
                @"percentage": percentage
            };
            break;
        }
        CFRelease(sources);
    }
    CFRelease(info);
    return reading;
}

static id ProbeError(NSError *error) {
    if (error == nil) return NSNull.null;
    return @{@"domain": error.domain, @"code": @(error.code), @"message": error.localizedDescription};
}

static BOOL ProbeValidateClient(Class cls, NSMutableDictionary *signatures) {
    NSArray<NSDictionary *> *requirements = @[
        @{@"selector": @"initWithClientName:", @"result": @(@encode(id)), @"arguments": @[@(@encode(id))]},
        @{@"selector": @"isMCLSupported", @"result": @(@encode(BOOL)), @"arguments": @[]},
        @{@"selector": @"isMCLCurrentlyEnabled:", @"result": @(@encode(NSUInteger)), @"arguments": @[@(@encode(NSError * __autoreleasing *))]},
        @{@"selector": @"getMCLLimitWithError:", @"result": @(@encode(unsigned char)), @"arguments": @[@(@encode(NSError * __autoreleasing *))]},
        @{@"selector": @"smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:",
          @"result": @(@encode(BOOL)),
          @"arguments": @[@(@encode(NSUInteger *)), @(@encode(NSUInteger *)), @(@encode(BOOL *)), @(@encode(NSError * __autoreleasing *))]},
        // Validate metadata only. No writer is declared or invoked by this tool.
        @{@"selector": @"temporarilyDisableMCL:", @"result": @(@encode(BOOL)), @"arguments": @[@(@encode(NSError * __autoreleasing *))]}
    ];
    BOOL valid = YES;
    for (NSDictionary *requirement in requirements) {
        NSString *name = requirement[@"selector"];
        SEL selector = NSSelectorFromString(name);
        Method method = cls != Nil ? class_getInstanceMethod(cls, selector) : NULL;
        const char *types = method != NULL ? method_getTypeEncoding(method) : NULL;
        signatures[name] = types != NULL ? @(types) : (id)NSNull.null;
        if (!ProbeSignatureMatches(cls, selector, [requirement[@"result"] UTF8String], requirement[@"arguments"])) valid = NO;
    }
    return valid;
}

static int ProbeInspect(NSMutableDictionary *report) {
    NSProcessInfo *process = NSProcessInfo.processInfo;
    report[@"os"] = process.operatingSystemVersionString;
#if defined(__arm64__)
    const BOOL isArm64 = YES;
    report[@"architecture"] = @"arm64";
#else
    const BOOL isArm64 = NO;
    report[@"architecture"] = @"unsupported";
#endif
    if (!ProbePlatformSupported(process.operatingSystemVersion, isArm64)) {
        report[@"reason"] = @"Requires an Apple Silicon process and macOS 26.4 or later; framework not loaded.";
        return 2;
    }
    // Keep the framework loaded until process exit; unloading registered ObjC classes is unsafe.
    void *handle = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        const char *error = dlerror();
        report[@"reason"] = error != NULL ? @(error) : @"Framework unavailable.";
        return 2;
    }
    Class cls = NSClassFromString(@"PowerUISmartChargeClient");
    NSMutableDictionary *signatures = [NSMutableDictionary dictionary];
    report[@"signatures"] = signatures;
    if (!ProbeValidateClient(cls, signatures)) {
        report[@"reason"] = @"Missing class, selector, or unexpected ABI; no client initialized.";
        return 2;
    }
    id<ChargeProbeReadOnlyClient> client = [(id<ChargeProbeReadOnlyClient>)[cls alloc]
        initWithClientName:@"StatusTrio.ChargeToFullNow.ReadOnlyPoC"];
    if (client == nil || !ProbeValidateClient(object_getClass(client), signatures)) {
        report[@"reason"] = @"Client initialization or instance ABI validation failed.";
        return 2;
    }
    BOOL supported = [client isMCLSupported];
    report[@"mclSupported"] = @(supported);
    if (!supported) {
        report[@"reason"] = @"PowerUI reports MCL unsupported; no charging-state queries performed.";
        return 2;
    }
    NSError *enabledError = nil, *limitError = nil, *uiError = nil;
    NSUInteger enabled = [client isMCLCurrentlyEnabled:&enabledError];
    unsigned char limit = [client getMCLLimitWithError:&limitError];
    NSUInteger uiState = NSUIntegerMax, uiLimit = NSUIntegerMax;
    BOOL allowed = NO;
    BOOL uiSuccess = [client smartChargingUIState:&uiState chargeLimit:&uiLimit
        chargingOverrideAllowed:&allowed withError:&uiError];
    report[@"battery"] = ProbeBattery();
    // These are undocumented enums. Report raw values without inferring enablement or eligibility.
    report[@"mclEnabledRaw"] = @(enabled);
    report[@"mclEnabledError"] = ProbeError(enabledError);
    report[@"mclLimit"] = limitError == nil ? (id)@(limit) : NSNull.null;
    report[@"mclLimitError"] = ProbeError(limitError);
    report[@"uiSuccess"] = @(uiSuccess);
    report[@"uiStateRaw"] = uiSuccess && uiError == nil ? (id)@(uiState) : NSNull.null;
    report[@"uiLimit"] = uiSuccess && uiError == nil ? (id)@(uiLimit) : NSNull.null;
    report[@"overrideAllowed"] = uiSuccess && uiError == nil ? (id)@(allowed) : NSNull.null;
    report[@"uiError"] = ProbeError(uiError);
    report[@"reason"] = !uiSuccess || uiError != nil || enabledError != nil || limitError != nil
        ? @"Read failed; no eligibility can be established."
        : (!allowed ? @"System override-allowed signal is false; do not send a request."
                    : @"Read succeeded; native UI, write authorization, actual charging, and limit restoration remain unverified.");
    return !uiSuccess || uiError != nil || enabledError != nil || limitError != nil ? 1 : 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2 || strcmp(argv[1], "--inspect") != 0) {
            fprintf(stderr, "Usage: charge-to-full-now-readonly --inspect\nNo charging write operation is implemented.\n");
            return 2;
        }
        NSMutableDictionary *report = [@{
            @"chargeRequestSent": @NO,
            @"integrationDecision": @"BLOCKED",
            @"status": @"observationOnly"
        } mutableCopy];
        int result;
        @try {
            result = ProbeInspect(report);
        } @catch (NSException *exception) {
            report[@"reason"] = exception.reason ?: @"Objective-C exception.";
            result = 1;
        }
        if (result != 0) report[@"status"] = result == 2 ? @"unsupported" : @"readFailed";
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (json == nil) {
            fprintf(stderr, "Cannot serialize probe result: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return result;
    }
}
#endif
