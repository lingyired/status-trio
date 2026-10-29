#import "PowerUIPrivateAPI.h"

#import <dlfcn.h>
#import <objc/runtime.h>

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

static STPowerUIChargeWriteResult *STRestoreChargeLimit(
    id<STPowerUIChargeClient> client,
    NSInteger limit
) {
    @try {
        if (![client isMCLSupported] || limit < 80 || limit >= 100) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                     errorMessage:@"The requested charge limit is not supported."];
        }

        STPowerUIChargeState *before = STReadState(client, NULL);
        if ((before.availableChargeLimits.count > 0
                && ![before.availableChargeLimits containsObject:@(limit)])
            || (before.availableChargeLimits.count == 0
                && ![@[@80, @85, @90, @95] containsObject:@(limit)])) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                     errorMessage:@"The requested charge limit is not supported."];
        }

        // Revalidate at the write boundary: a newer sub-100 limit belongs to
        // the user or another app and must not be replaced by our snapshot.
        if (before.mclLimit >= 80 && before.mclLimit < 100
            && before.mclLimit != limit) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                     errorMessage:@"The charge limit changed. Open the panel and try again."];
        }
        if (before.validState
            && before.mclEnabledRawValue == 1
            && before.mclLimit == limit) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:YES
                     errorMessage:nil];
        }

        // Always try the non-setting operation first, including when the
        // original value could only be recovered from the accepted session.
        NSError *writeError = nil;
        BOOL wrote = [client enableMCL:&writeError];
        if (!wrote || writeError != nil) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                     errorMessage:STErrorDescription(writeError)
                        ?: @"PowerUI could not re-enable the charge limit."];
        }

        NSString *verificationFailure = nil;
        STPowerUIChargeState *after = STReadState(client, &verificationFailure);
        if (!after.validState) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                     errorMessage:verificationFailure
                        ?: @"PowerUI could not verify the charge limit."];
        }
        if (after.mclEnabledRawValue == 1 && after.mclLimit == limit) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:YES
                     errorMessage:nil];
        }
        if ((after.mclLimit >= 80 && after.mclLimit < 100
                && after.mclLimit != limit)
            || (after.mclEnabledRawValue != 0
                && after.mclEnabledRawValue != 1
                && after.mclEnabledRawValue != 3)) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                     errorMessage:@"The charge limit changed. Open the panel and try again."];
        }

        // One bounded fallback, never a retry loop. A successful API return
        // still needs a fresh enabled/limit read before reporting success.
        writeError = nil;
        wrote = [client setMCLLimit:(unsigned char)limit error:&writeError];
        if (!wrote || writeError != nil) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                     errorMessage:STErrorDescription(writeError)
                        ?: @"PowerUI rejected the charge limit."];
        }
        writeError = nil;
        wrote = [client enableMCL:&writeError];
        if (!wrote || writeError != nil) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                     errorMessage:STErrorDescription(writeError)
                        ?: @"PowerUI could not re-enable the charge limit."];
        }
        after = STReadState(client, &verificationFailure);
        if (!after.validState
            || after.mclEnabledRawValue != 1
            || after.mclLimit != limit) {
            return [[STPowerUIChargeWriteResult alloc]
                initWithSucceeded:NO
                     errorMessage:verificationFailure
                        ?: @"PowerUI did not confirm the restored charge limit."];
        }
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:YES
                 errorMessage:nil];
    } @catch (NSException *exception) {
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
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
    self = [super init];
    if (self != nil) {
        _succeeded = succeeded;
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

- (STPowerUIChargeWriteResult *)restoreChargeLimit:(NSInteger)limit {
    if (limit < 80 || limit >= 100) {
        return [[STPowerUIChargeWriteResult alloc]
            initWithSucceeded:NO
                 errorMessage:@"The requested charge limit is outside the supported range."];
    }

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

    STPowerUIChargeWriteResult *result = STRestoreChargeLimit(client, limit);
    STReleaseIfNeeded(client);
    return result;
}

@end

NS_ASSUME_NONNULL_END
