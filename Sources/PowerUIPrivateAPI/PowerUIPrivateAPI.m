#import "PowerUIPrivateAPI.h"

#import <dlfcn.h>
#import <objc/runtime.h>
#import <unistd.h>

NS_ASSUME_NONNULL_BEGIN

@protocol STPowerUIChargeClient
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (NSUInteger)isMCLCurrentlyEnabled:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (NSArray<NSNumber *> *)availableChargeLimitsWithError:(NSError **)error;
- (BOOL)smartChargingUIState:(NSUInteger *)state
                 chargeLimit:(NSUInteger *)limit
     chargingOverrideAllowed:(BOOL *)allowed
                   withError:(NSError **)error;
- (BOOL)temporarilyDisableMCL:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (BOOL)enableMCL:(NSError **)error;
@end

@interface STPowerUIChargeState ()
- (instancetype)initWithValidState:(BOOL)validState
                mclEnabledRawValue:(NSUInteger)mclEnabledRawValue
                          mclLimit:(NSInteger)mclLimit
             availableChargeLimits:(NSArray<NSNumber *> *)availableChargeLimits
          chargingOverrideAllowed:(BOOL)chargingOverrideAllowed
                      errorMessage:(NSString * _Nullable)errorMessage;
@end

@interface STPowerUIChargeCapability ()
- (instancetype)initWithAvailable:(BOOL)available
                           reason:(STPowerUIChargeAvailabilityReason)reason;
@end

@interface STPowerUIChargeWriteResult ()
- (instancetype)initWithSucceeded:(BOOL)succeeded
                     errorMessage:(NSString * _Nullable)errorMessage;
- (instancetype)initWithSucceeded:(BOOL)succeeded
                          failure:(STPowerUIChargeWriteFailure)failure
                     errorMessage:(NSString * _Nullable)errorMessage;
@end

typedef struct {
    Class _Nullable clientClass;
    STPowerUIChargeAvailabilityReason reason;
} STPowerUIRuntime;

static BOOL STPlatformSupported(void) {
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    return version.majorVersion > 26
        || (version.majorVersion == 26 && version.minorVersion >= 4);
}

static BOOL STSignatureMatches(
    Class _Nullable cls,
    SEL selector,
    const char *returnType,
    NSArray<NSString *> *arguments
) {
    @try {
        Method method = cls != Nil ? class_getInstanceMethod(cls, selector) : NULL;
        const char *types = method != NULL ? method_getTypeEncoding(method) : NULL;
        if (types == NULL) return NO;

        NSMethodSignature *signature =
            [NSMethodSignature signatureWithObjCTypes:types];
        if (signature == nil
            || strcmp(signature.methodReturnType, returnType) != 0
            || signature.numberOfArguments != arguments.count + 2) {
            return NO;
        }
        for (NSUInteger index = 0; index < arguments.count; index++) {
            if (strcmp(
                [signature getArgumentTypeAtIndex:index + 2],
                arguments[index].UTF8String
            ) != 0) {
                return NO;
            }
        }
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

static BOOL STValidateClient(Class cls) {
    return STSignatureMatches(
               cls,
               sel_registerName("initWithClientName:"),
               @encode(id),
               @[@(@encode(id))]
           )
        && STSignatureMatches(
               cls,
               sel_registerName("isMCLSupported"),
               @encode(BOOL),
               @[]
           )
        && STSignatureMatches(
               cls,
               sel_registerName("isMCLCurrentlyEnabled:"),
               @encode(NSUInteger),
               @[@(@encode(NSError *__autoreleasing *))]
           )
        && STSignatureMatches(
               cls,
               sel_registerName("getMCLLimitWithError:"),
               @encode(unsigned char),
               @[@(@encode(NSError *__autoreleasing *))]
           )
        && STSignatureMatches(
               cls,
               sel_registerName("smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:"),
               @encode(BOOL),
               @[
                   @(@encode(NSUInteger *)),
                   @(@encode(NSUInteger *)),
                   @(@encode(BOOL *)),
                   @(@encode(NSError *__autoreleasing *))
               ]
           )
        && STSignatureMatches(
               cls,
               sel_registerName("temporarilyDisableMCL:"),
               @encode(BOOL),
               @[@(@encode(NSError *__autoreleasing *))]
           )
        && STSignatureMatches(
               cls,
               sel_registerName("setMCLLimit:error:"),
               @encode(BOOL),
               @[
                   @(@encode(unsigned char)),
                   @(@encode(NSError *__autoreleasing *))
               ]
           )
        && STSignatureMatches(
               cls,
               sel_registerName("enableMCL:"),
               @encode(BOOL),
               @[@(@encode(NSError *__autoreleasing *))]
           );
}

static STPowerUIRuntime STLoadRuntime(void) {
    static STPowerUIRuntime runtime;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        runtime.reason = STPowerUIChargeAvailabilityReasonUnsupportedSystem;
        if (!STPlatformSupported()) return;

#if defined(__arm64__)
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI",
            RTLD_NOW | RTLD_LOCAL
        );
        if (handle == NULL) {
            runtime.reason = STPowerUIChargeAvailabilityReasonFrameworkUnavailable;
            return;
        }

        Class clientClass = NSClassFromString(@"PowerUISmartChargeClient");
        if (clientClass == Nil || !STValidateClient(clientClass)) {
            runtime.reason = STPowerUIChargeAvailabilityReasonAPIUnavailable;
            return;
        }

        // Keep the handle for the life of the process. Unloading a framework
        // that registered Objective-C classes is unsafe.
        runtime.clientClass = clientClass;
        runtime.reason = STPowerUIChargeAvailabilityReasonAvailable;
#else
        runtime.reason = STPowerUIChargeAvailabilityReasonUnsupportedArchitecture;
#endif
    });
    return runtime;
}

static id<STPowerUIChargeClient> _Nullable STCreateClient(STPowerUIRuntime runtime) {
    if (runtime.clientClass == Nil) return nil;
    @try {
        return [(id<STPowerUIChargeClient>)[runtime.clientClass alloc]
            initWithClientName:@"Status Trio"];
    } @catch (NSException *exception) {
        return nil;
    }
}

static void STReleaseIfNeeded(id _Nullable object) {
#if !__has_feature(objc_arc)
    [object release];
#else
    (void)object;
#endif
}

static NSString * _Nullable STErrorDescription(NSError * _Nullable error) {
    if (error == nil) return nil;
    NSString *description = error.localizedDescription;
    return description.length > 0 ? description : @"PowerUI returned an error.";
}

static NSString * _Nullable STFirstError(
    NSError * _Nullable first,
    NSError * _Nullable second,
    NSError * _Nullable third
) {
    if (first != nil) return STErrorDescription(first);
    if (second != nil) return STErrorDescription(second);
    if (third != nil) return STErrorDescription(third);
    return nil;
}

static STPowerUIChargeState *STReadState(
    id<STPowerUIChargeClient> client,
    NSString * _Nullable * _Nullable failure
) {
    NSError *enabledError = nil;
    NSError *limitError = nil;
    NSError *availableError = nil;
    NSError *uiError = nil;
    NSUInteger enabled = 0;
    unsigned char limit = 0;
    NSArray<NSNumber *> *availableLimits = @[];
    NSUInteger uiState = 0;
    NSUInteger uiLimit = 0;
    BOOL allowed = NO;
    BOOL uiSucceeded = NO;

    @try {
        if (![client isMCLSupported]) {
            if (failure != NULL) *failure = @"MCL is not supported by this Mac.";
            return [[STPowerUIChargeState alloc] initWithValidState:NO
                                                     mclEnabledRawValue:0
                                                               mclLimit:-1
                                               availableChargeLimits:@[]
                                               chargingOverrideAllowed:NO
                                                           errorMessage:@"MCL is not supported by this Mac."];
        }

        enabled = [client isMCLCurrentlyEnabled:&enabledError];
        limit = [client getMCLLimitWithError:&limitError];
        SEL availableSelector = sel_registerName("availableChargeLimitsWithError:");
        if (STSignatureMatches(
                object_getClass(client),
                availableSelector,
                @encode(id),
                @[@(@encode(NSError *__autoreleasing *))]
            )) {
            NSArray<NSNumber *> *reportedLimits =
                [client availableChargeLimitsWithError:&availableError];
            if ([reportedLimits isKindOfClass:[NSArray class]]) {
                availableLimits = reportedLimits;
            }
        }
        uiSucceeded = [client smartChargingUIState:&uiState
                                      chargeLimit:&uiLimit
                          chargingOverrideAllowed:&allowed
                                        withError:&uiError];
    } @catch (NSException *exception) {
        NSString *message = exception.reason ?: @"PowerUI raised an exception.";
        if (failure != NULL) *failure = message;
        return [[STPowerUIChargeState alloc] initWithValidState:NO
                                                 mclEnabledRawValue:0
                                                           mclLimit:-1
                                           availableChargeLimits:@[]
                                           chargingOverrideAllowed:NO
                                                       errorMessage:message];
    }

    NSString *errorMessage = STFirstError(enabledError, limitError, uiError);
    BOOL valid = errorMessage == nil && uiSucceeded;
    if (!uiSucceeded && errorMessage == nil) {
        errorMessage = @"PowerUI did not return charging UI state.";
    }
    if (failure != NULL) *failure = errorMessage;

    return [[STPowerUIChargeState alloc]
        initWithValidState:valid
         mclEnabledRawValue:enabled
                   mclLimit:limitError == nil ? (NSInteger)limit : -1
      availableChargeLimits:availableError == nil ? availableLimits : @[]
    chargingOverrideAllowed:uiSucceeded && uiError == nil ? allowed : NO
                errorMessage:errorMessage];
}

static BOOL STIsRestorableChargeLimit(NSInteger limit) {
    return limit >= 80 && limit < 100;
}

static BOOL STIsSub100ChargeLimit(NSInteger limit) {
    return limit >= 80 && limit < 100;
}

// A set call can leave MCL briefly disengaged or primed while the new limit
// is already stored. Accept every non-override shape for the same limit
// instead of reporting a false verification failure right after a write
// (observed on macOS 27.2). Raw 3 is the temporary override.
static BOOL STIsRestoredChargeLimit(
    STPowerUIChargeState *state,
    NSInteger limit
) {
    return state.validState
        && state.mclEnabledRawValue != 3
        && state.mclLimit == limit;
}

// `expectedLimit` is the sub-100 limit recorded for the running session, or 0
// when no session recorded one. A limit that matches it is the system's own
// restore step, not an external change.
static STPowerUIChargeWriteResult *STRestoreChargeLimit(
    id<STPowerUIChargeClient> client,
    NSInteger limit,
    NSInteger expectedLimit
) {
    @try {
        if (![client isMCLSupported] || !STIsRestorableChargeLimit(limit)) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                          failure:STPowerUIChargeWriteFailureUnsupportedLimit
                     errorMessage:@"The requested charge limit is not supported."];
        }

        BOOL hasExpectedLimit = STIsSub100ChargeLimit(expectedLimit);

        STPowerUIChargeState *before = STReadState(client, NULL);
        BOOL supported = before.availableChargeLimits.count > 0
            ? [before.availableChargeLimits containsObject:@(limit)]
            : [@[@80, @85, @90, @95] containsObject:@(limit)];
        if (!supported) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                          failure:STPowerUIChargeWriteFailureUnsupportedLimit
                     errorMessage:@"The requested charge limit is not supported."];
        }

        // Revalidate at the write boundary. A sub-100 limit that is neither our
        // target nor the limit this session started from belongs to the user or
        // another app. While no session recorded one, a temporary override
        // (raw 3) still owns the persisted limit, so cancelling may proceed.
        if (STIsSub100ChargeLimit(before.mclLimit)
            && before.mclLimit != limit
            && !(hasExpectedLimit && before.mclLimit == expectedLimit)
            && !(!hasExpectedLimit && before.mclEnabledRawValue == 3)) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                          failure:STPowerUIChargeWriteFailureLimitChanged
                     errorMessage:@"The charge limit changed. Open the panel and try again."];
        }
        if (STIsRestoredChargeLimit(before, limit)) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:YES
                          failure:STPowerUIChargeWriteFailureNone
                     errorMessage:nil];
        }

        // Always try the non-setting operation first, including when the
        // original value could only be recovered from the accepted session.
        NSError *writeError = nil;
        BOOL wrote = [client enableMCL:&writeError];
        if (!wrote || writeError != nil) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                          failure:STPowerUIChargeWriteFailureRejected
                     errorMessage:STErrorDescription(writeError)
                        ?: @"PowerUI could not re-enable the charge limit."];
        }

        NSString *verificationFailure = nil;
        STPowerUIChargeState *after = STReadState(client, &verificationFailure);
        if (!after.validState) {
            // A single transient failed read must not fail a completed write.
            usleep(20 * 1000);
            verificationFailure = nil;
            after = STReadState(client, &verificationFailure);
        }
        if (!after.validState) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                          failure:STPowerUIChargeWriteFailureVerificationFailed
                     errorMessage:verificationFailure
                        ?: @"PowerUI could not verify the charge limit."];
        }
        if (STIsRestoredChargeLimit(after, limit)) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:YES
                          failure:STPowerUIChargeWriteFailureNone
                     errorMessage:nil];
        }
        // enableMCL: restores the system's persisted limit before our target is
        // applied. That intermediate value is expected; any other sub-100 limit
        // recorded for the session is an external change and stops the write.
        if (STIsSub100ChargeLimit(after.mclLimit)
            && after.mclLimit != limit
            && (!hasExpectedLimit || after.mclLimit != expectedLimit)) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                          failure:STPowerUIChargeWriteFailureLimitChanged
                     errorMessage:@"The charge limit changed. Open the panel and try again."];
        }
        if (after.mclEnabledRawValue != 0
            && after.mclEnabledRawValue != 1
            && after.mclEnabledRawValue != 2
            && after.mclEnabledRawValue != 3) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                          failure:STPowerUIChargeWriteFailureLimitChanged
                     errorMessage:@"The charge limit changed. Open the panel and try again."];
        }

        // One bounded fallback, never a retry loop. A successful API return
        // still needs a fresh enabled/limit read before reporting success.
        writeError = nil;
        wrote = [client setMCLLimit:(unsigned char)limit error:&writeError];
        if (!wrote || writeError != nil) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                          failure:STPowerUIChargeWriteFailureRejected
                     errorMessage:STErrorDescription(writeError)
                        ?: @"PowerUI rejected the charge limit."];
        }
        // setMCLLimit: applies the target after the override has ended.
        // Calling enableMCL: again would reapply PowerUI's saved pre-override
        // limit and overwrite the target (observed 90 -> 80 on macOS 27.2).
        after = STReadState(client, &verificationFailure);
        if (!STIsRestoredChargeLimit(after, limit)) {
            // Let PowerUI engage the stored limit before the one re-read.
            usleep(20 * 1000);
            verificationFailure = nil;
            after = STReadState(client, &verificationFailure);
        }
        if (!STIsRestoredChargeLimit(after, limit)) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                          failure:STPowerUIChargeWriteFailureVerificationFailed
                     errorMessage:verificationFailure
                        ?: @"PowerUI did not confirm the restored charge limit."];
        }
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:YES
                      failure:STPowerUIChargeWriteFailureNone
                 errorMessage:nil];
    } @catch (NSException *exception) {
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
                      failure:STPowerUIChargeWriteFailureRejected
                 errorMessage:exception.reason ?: @"PowerUI raised an exception."];
    }
}

@implementation STPowerUIChargeCapability

- (instancetype)initWithAvailable:(BOOL)available
                           reason:(STPowerUIChargeAvailabilityReason)reason {
    self = [super init];
    if (self != nil) {
        _available = available;
        _reason = reason;
    }
    return self;
}

@end

@implementation STPowerUIChargeState

- (instancetype)initWithValidState:(BOOL)validState
                mclEnabledRawValue:(NSUInteger)mclEnabledRawValue
                          mclLimit:(NSInteger)mclLimit
             availableChargeLimits:(NSArray<NSNumber *> *)availableChargeLimits
          chargingOverrideAllowed:(BOOL)chargingOverrideAllowed
                      errorMessage:(NSString * _Nullable)errorMessage {
    self = [super init];
    if (self != nil) {
        _validState = validState;
        _mclEnabledRawValue = mclEnabledRawValue;
        _mclLimit = mclLimit;
        _availableChargeLimits = [availableChargeLimits copy];
        _chargingOverrideAllowed = chargingOverrideAllowed;
        _errorMessage = [errorMessage copy];
    }
    return self;
}

@end

@implementation STPowerUIChargeWriteResult

- (instancetype)initWithSucceeded:(BOOL)succeeded
                     errorMessage:(NSString * _Nullable)errorMessage {
    return [self initWithSucceeded:succeeded
                           failure:STPowerUIChargeWriteFailureNone
                      errorMessage:errorMessage];
}

- (instancetype)initWithSucceeded:(BOOL)succeeded
                          failure:(STPowerUIChargeWriteFailure)failure
                     errorMessage:(NSString * _Nullable)errorMessage {
    self = [super init];
    if (self != nil) {
        _succeeded = succeeded;
        _failure = failure;
        _errorMessage = [errorMessage copy];
    }
    return self;
}

@end

@implementation STPowerUIChargeBridge

- (STPowerUIChargeCapability *)capability {
    STPowerUIRuntime runtime = STLoadRuntime();
    if (runtime.reason != STPowerUIChargeAvailabilityReasonAvailable) {
        return [[STPowerUIChargeCapability alloc]
            initWithAvailable:NO
                       reason:runtime.reason];
    }

    id<STPowerUIChargeClient> client = STCreateClient(runtime);
    if (client == nil) {
        return [[STPowerUIChargeCapability alloc]
            initWithAvailable:NO
                       reason:STPowerUIChargeAvailabilityReasonAPIUnavailable];
    }

    BOOL supported = NO;
    @try {
        supported = [client isMCLSupported];
    } @catch (NSException *exception) {
        supported = NO;
    }
    STReleaseIfNeeded(client);
    return [[STPowerUIChargeCapability alloc]
        initWithAvailable:supported
                   reason:supported
                       ? STPowerUIChargeAvailabilityReasonAvailable
                       : STPowerUIChargeAvailabilityReasonMCLUnsupported];
}

- (STPowerUIChargeState *)readState {
    STPowerUIRuntime runtime = STLoadRuntime();
    if (runtime.reason != STPowerUIChargeAvailabilityReasonAvailable) {
        return [[STPowerUIChargeState alloc] initWithValidState:NO
                                              mclEnabledRawValue:0
                                                        mclLimit:-1
                                               availableChargeLimits:@[]
                                        chargingOverrideAllowed:NO
                                                    errorMessage:@"PowerUI is unavailable."];
    }

    id<STPowerUIChargeClient> client = STCreateClient(runtime);
    if (client == nil) {
        return [[STPowerUIChargeState alloc] initWithValidState:NO
                                              mclEnabledRawValue:0
                                                        mclLimit:-1
                                               availableChargeLimits:@[]
                                        chargingOverrideAllowed:NO
                                                    errorMessage:@"PowerUI client is unavailable."];
    }

    NSString *failure = nil;
    STPowerUIChargeState *state = STReadState(client, &failure);
    STReleaseIfNeeded(client);
    return state;
}

- (STPowerUIChargeWriteResult *)temporarilyDisableMCL {
    STPowerUIRuntime runtime = STLoadRuntime();
    if (runtime.reason != STPowerUIChargeAvailabilityReasonAvailable) {
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
                 errorMessage:@"PowerUI is unavailable."];
    }

    id<STPowerUIChargeClient> client = STCreateClient(runtime);
    if (client == nil) {
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
                 errorMessage:@"PowerUI client is unavailable."];
    }

    NSString *failure = nil;
    STPowerUIChargeState *state = STReadState(client, &failure);
    if (!state.validState
        || state.mclEnabledRawValue == 0
        || state.mclLimit < 0
        || state.mclLimit >= 100) {
        STReleaseIfNeeded(client);
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
                 errorMessage:failure ?: @"The charge limit is no longer active."];
    }

    NSError *writeError = nil;
    BOOL wrote = NO;
    @try {
        // Exactly one charging request is sent. There is no retry.
        wrote = [client temporarilyDisableMCL:&writeError];
    } @catch (NSException *exception) {
        STReleaseIfNeeded(client);
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
                 errorMessage:exception.reason ?: @"PowerUI raised an exception."];
    }
    STReleaseIfNeeded(client);

    NSString *errorMessage = STErrorDescription(writeError);
    return [[STPowerUIChargeWriteResult alloc]
        initWithSucceeded:wrote && errorMessage == nil
             errorMessage:errorMessage ?: (wrote ? nil : @"PowerUI rejected the request.")];
}

- (STPowerUIChargeWriteResult *)restoreChargeLimit:(NSInteger)limit
                                    expectedLimit:(NSInteger)expectedLimit {
    if (!STIsRestorableChargeLimit(limit)) {
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
                      failure:STPowerUIChargeWriteFailureUnsupportedLimit
                 errorMessage:@"The requested charge limit is outside the supported range."];
    }

    STPowerUIRuntime runtime = STLoadRuntime();
    if (runtime.reason != STPowerUIChargeAvailabilityReasonAvailable) {
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
                      failure:STPowerUIChargeWriteFailureUnavailable
                 errorMessage:@"PowerUI is unavailable."];
    }

    id<STPowerUIChargeClient> client = STCreateClient(runtime);
    if (client == nil) {
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
                      failure:STPowerUIChargeWriteFailureUnavailable
                 errorMessage:@"PowerUI client is unavailable."];
    }

    STPowerUIChargeWriteResult *result =
        STRestoreChargeLimit(client, limit, expectedLimit);
    STReleaseIfNeeded(client);
    return result;
}

@end

NS_ASSUME_NONNULL_END
