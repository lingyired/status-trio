#import <Foundation/Foundation.h>
#import <dlfcn.h>

static void *STForbiddenLoad(const char *path, int mode) {
    (void)path;
    (void)mode;
    abort();
}

// Exercise the production write routines with a fake client. Even an
// accidental call through its runtime loader cannot load the real framework.
#define dlopen STForbiddenLoad
#import "../../Sources/PowerUIPrivateAPI/PowerUIPrivateAPI.m"
#undef dlopen

@interface FakeChargeClient : NSObject <STPowerUIChargeClient>
@property NSUInteger enabled;
@property unsigned char limit;
@property unsigned char restoredByEnable;
@property NSInteger remainingReadFailures;
@property BOOL enableReportsError;
@property BOOL setReportsError;
@property BOOL failsVerification;
@property BOOL supported;
@property NSArray<NSNumber *> *limits;
@property NSMutableArray<NSString *> *writes;
@property BOOL enabledReportsError;
@property BOOL availableReportsError;
@property BOOL uiReportsError;
@property BOOL uiReturnsFalse;
@property BOOL setReturnsFalse;
@property BOOL enableReturnsFalse;
@property BOOL supportThrows;
@property BOOL readThrows;
@property BOOL availableThrows;
@property BOOL setThrows;
@property BOOL enableThrows;
@property NSUInteger readCount;
@property (copy) void (^beforeRead)(FakeChargeClient *, NSUInteger);
@property (copy) void (^afterSet)(FakeChargeClient *);
@end

@implementation FakeChargeClient
- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = 3;
        _limit = 100;
        _supported = YES;
        _limits = @[@80, @85, @90, @95, @100];
        _writes = [NSMutableArray array];
    }
    return self;
}
- (instancetype)initWithClientName:(NSString *)name {
    (void)name;
    return [self init];
}
- (BOOL)isMCLSupported {
    if (self.supportThrows) [NSException raise:@"FakeSupport" format:@"Support failed"];
    return self.supported;
}
- (NSUInteger)isMCLCurrentlyEnabled:(NSError **)error {
    self.readCount++;
    if (self.beforeRead) self.beforeRead(self, self.readCount);
    if (self.readThrows) [NSException raise:@"FakeRead" format:@"Read failed"];
    if (self.enabledReportsError) {
        *error = [NSError errorWithDomain:@"FakeEnabled" code:4 userInfo:nil];
    }
    return self.enabled;
}
- (unsigned char)getMCLLimitWithError:(NSError **)error {
    if (self.remainingReadFailures > 0) {
        self.remainingReadFailures--;
        *error = [NSError errorWithDomain:@"FakeRead" code:1 userInfo:nil];
        return 0;
    }
    return self.limit;
}
- (NSArray<NSNumber *> *)availableChargeLimitsWithError:(NSError **)error {
    if (self.availableThrows) [NSException raise:@"FakeAvailable" format:@"Options failed"];
    if (self.availableReportsError) {
        *error = [NSError errorWithDomain:@"FakeAvailable" code:5 userInfo:nil];
    }
    return self.limits;
}
- (BOOL)smartChargingUIState:(NSUInteger *)state
                 chargeLimit:(NSUInteger *)limit
     chargingOverrideAllowed:(BOOL *)allowed
                   withError:(NSError **)error {
    if (self.uiReportsError) {
        *error = [NSError errorWithDomain:@"FakeUI" code:6 userInfo:nil];
    }
    *state = 13;
    *limit = self.limit;
    *allowed = NO;
    return !self.uiReturnsFalse;
}
- (BOOL)temporarilyDisableMCL:(NSError **)error {
    (void)error;
    abort();
}
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error {
    [self.writes addObject:[NSString stringWithFormat:@"set:%u", limit]];
    if (self.setThrows) [NSException raise:@"FakeSet" format:@"Set failed"];
    self.limit = self.failsVerification ? 100 : limit;
    if (self.afterSet) self.afterSet(self);
    if (self.setReportsError) {
        *error = [NSError errorWithDomain:@"FakeSet" code:2 userInfo:nil];
    }
    return !self.setReturnsFalse;
}
- (BOOL)enableMCL:(NSError **)error {
    [self.writes addObject:@"enable"];
    if (self.enableThrows) [NSException raise:@"FakeEnable" format:@"Enable failed"];
    self.enabled = 1;
    if (self.restoredByEnable > 0) self.limit = self.restoredByEnable;
    if (self.enableReportsError) {
        *error = [NSError errorWithDomain:@"FakeEnable" code:3 userInfo:nil];
    }
    return !self.enableReturnsFalse;
}
@end

static int failures;
static int cases;

static void Check(
    NSString *name,
    FakeChargeClient *client,
    NSInteger target,
    BOOL success,
    NSArray<NSString *> *writes
) {
    cases++;
    STPowerUIChargeWriteResult *result = STRestoreChargeLimit(client, target);
    if (result.didSucceed != success || ![client.writes isEqual:writes]) {
        failures++;
        fprintf(stderr, "%s: success=%d, writes=%s\n",
            name.UTF8String, result.didSucceed, client.writes.description.UTF8String);
    }
}

static void CheckSet(
    NSString *name,
    FakeChargeClient *client,
    NSInteger target,
    NSInteger expectedLimit,
    NSUInteger expectedEnabled,
    BOOL success,
    NSArray<NSString *> *writes
) {
    cases++;
    STPowerUIChargeWriteResult *result = STSetChargeLimit(
        client, target, expectedLimit, expectedEnabled
    );
    if (result.didSucceed != success || ![client.writes isEqual:writes]
        || (success ? result.errorMessage != nil : result.errorMessage.length == 0)) {
        failures++;
        fprintf(stderr, "%s: success=%d, writes=%s, error=%s\n",
            name.UTF8String, result.didSucceed, client.writes.description.UTF8String,
            result.errorMessage.UTF8String);
    }
}

static FakeChargeClient *ActiveClient(void) {
    FakeChargeClient *client = [FakeChargeClient new];
    client.enabled = 1;
    client.limit = 80;
    return client;
}

static void TestExplicitSetter(void) {
    CheckSet(@"explicit intent replaces active 80 with 90", ActiveClient(),
        90, 80, 1, YES, @[@"set:90"]);
    CheckSet(@"same active target does not write", ActiveClient(),
        80, 80, 1, YES, @[]);
    CheckSet(@"stale current limit never writes", ActiveClient(),
        90, 85, 1, NO, @[]);
    CheckSet(@"stale enabled state never writes", ActiveClient(),
        90, 80, 3, NO, @[]);

    for (NSNumber *target in @[@(-1), @0, @79, @101, @256, @(NSIntegerMax)]) {
        CheckSet(@"invalid requested target never writes", ActiveClient(),
            target.integerValue, 80, 1, NO, @[]);
    }
    for (NSNumber *limit in @[@(-1), @101, @(NSIntegerMax)]) {
        CheckSet(@"invalid expected limit never writes", ActiveClient(),
            90, limit.integerValue, 1, NO, @[]);
    }
    for (NSNumber *raw in @[@2, @4, @(NSUIntegerMax)]) {
        FakeChargeClient *client = ActiveClient();
        client.enabled = raw.unsignedIntegerValue;
        CheckSet(@"unknown expected raw state never writes", client,
            90, 80, raw.unsignedIntegerValue, NO, @[]);
    }

    FakeChargeClient *unsupported = ActiveClient();
    unsupported.supported = NO;
    CheckSet(@"unsupported hardware never sets", unsupported, 90, 80, 1, NO, @[]);
    for (NSArray<NSNumber *> *options in @[@[], @[@80, @85], @[@90.5],
                                           @[@79, @101], @[@"90"]]) {
        FakeChargeClient *client = ActiveClient();
        client.limits = options;
        CheckSet(@"missing or invalid advertised target never sets", client,
            90, 80, 1, NO, @[]);
    }
    FakeChargeClient *nilOptions = ActiveClient();
    nilOptions.limits = nil;
    CheckSet(@"nil options never invent standard limits", nilOptions, 90, 80, 1, NO, @[]);
    FakeChargeClient *optionsError = ActiveClient();
    optionsError.availableReportsError = YES;
    CheckSet(@"options NSError never invents standard limits", optionsError,
        90, 80, 1, NO, @[]);

    FakeChargeClient *custom = ActiveClient();
    custom.limits = @[@82, @88, @94];
    CheckSet(@"advertised nonstandard integer is accepted", custom,
        88, 80, 1, YES, @[@"set:88"]);

    FakeChargeClient *disabled = [FakeChargeClient new];
    disabled.enabled = 0;
    disabled.limit = 0;
    CheckSet(@"disabled zero limit can be explicitly set", disabled,
        90, 0, 0, YES, @[@"set:90", @"enable"]);
    FakeChargeClient *temporary = [FakeChargeClient new];
    CheckSet(@"temporarily disabled limit is set before enabling", temporary,
        90, 100, 3, YES, @[@"set:90", @"enable"]);
    FakeChargeClient *stored = [FakeChargeClient new];
    stored.limit = 90;
    CheckSet(@"stored requested limit only needs enabling", stored,
        90, 90, 3, YES, @[@"enable"]);

    FakeChargeClient *noCap = ActiveClient();
    noCap.limits = @[];
    CheckSet(@"100 restores no cap without advertised options", noCap,
        100, 80, 1, YES, @[@"set:100"]);
    FakeChargeClient *noCapOptionsError = ActiveClient();
    noCapOptionsError.availableReportsError = YES;
    CheckSet(@"100 never writes after an options NSError", noCapOptionsError,
        100, 80, 1, NO, @[]);
    FakeChargeClient *noCapDisabled = [FakeChargeClient new];
    noCapDisabled.limits = @[];
    CheckSet(@"stored no cap only enables", noCapDisabled,
        100, 100, 3, YES, @[@"enable"]);

    FakeChargeClient *initialReadError = ActiveClient();
    initialReadError.remainingReadFailures = 1;
    CheckSet(@"invalid initial read never sets", initialReadError,
        90, 80, 1, NO, @[]);
    FakeChargeClient *enabledError = ActiveClient();
    enabledError.enabledReportsError = YES;
    CheckSet(@"enabled NSError never sets", enabledError, 90, 80, 1, NO, @[]);
    FakeChargeClient *uiError = ActiveClient();
    uiError.uiReportsError = YES;
    CheckSet(@"UI NSError never sets", uiError, 90, 80, 1, NO, @[]);
    FakeChargeClient *uiFailure = ActiveClient();
    uiFailure.uiReturnsFalse = YES;
    CheckSet(@"missing UI state never sets", uiFailure, 90, 80, 1, NO, @[]);

    FakeChargeClient *setError = [FakeChargeClient new];
    setError.setReportsError = YES;
    CheckSet(@"set NSError stops before enabling", setError,
        90, 100, 3, NO, @[@"set:90"]);
    FakeChargeClient *setFailure = [FakeChargeClient new];
    setFailure.setReturnsFalse = YES;
    CheckSet(@"set false stops before enabling", setFailure,
        90, 100, 3, NO, @[@"set:90"]);
    FakeChargeClient *enableError = [FakeChargeClient new];
    enableError.enableReportsError = YES;
    CheckSet(@"enable NSError cannot report success", enableError,
        90, 100, 3, NO, @[@"set:90", @"enable"]);
    FakeChargeClient *enableFailure = [FakeChargeClient new];
    enableFailure.enableReturnsFalse = YES;
    CheckSet(@"enable false cannot report success", enableFailure,
        90, 100, 3, NO, @[@"set:90", @"enable"]);

    FakeChargeClient *afterSetMismatch = [FakeChargeClient new];
    afterSetMismatch.afterSet = ^(FakeChargeClient *client) { client.limit = 95; };
    CheckSet(@"changed target after setting is preserved", afterSetMismatch,
        90, 100, 3, NO, @[@"set:90"]);
    FakeChargeClient *afterSetEnabledChange = [FakeChargeClient new];
    afterSetEnabledChange.afterSet = ^(FakeChargeClient *client) { client.enabled = 0; };
    CheckSet(@"changed enabled state after setting is preserved", afterSetEnabledChange,
        90, 100, 3, NO, @[@"set:90"]);
    FakeChargeClient *enabledBySet = [FakeChargeClient new];
    enabledBySet.afterSet = ^(FakeChargeClient *client) { client.enabled = 1; };
    CheckSet(@"already enabled after setting needs no extra write", enabledBySet,
        90, 100, 3, YES, @[@"set:90"]);
    FakeChargeClient *afterSetReadError = [FakeChargeClient new];
    afterSetReadError.afterSet = ^(FakeChargeClient *client) {
        client.remainingReadFailures = 1;
    };
    CheckSet(@"failed read after setting stops before enabling", afterSetReadError,
        90, 100, 3, NO, @[@"set:90"]);
    FakeChargeClient *afterSetOptionsChanged = [FakeChargeClient new];
    afterSetOptionsChanged.afterSet = ^(FakeChargeClient *client) { client.limits = @[@80]; };
    CheckSet(@"removed target after setting stops before enabling", afterSetOptionsChanged,
        90, 100, 3, NO, @[@"set:90"]);
    FakeChargeClient *afterSetNoCapOptionsError = [FakeChargeClient new];
    afterSetNoCapOptionsError.limit = 80;
    afterSetNoCapOptionsError.afterSet = ^(FakeChargeClient *client) {
        client.availableReportsError = YES;
    };
    CheckSet(@"100 options NSError after setting stops before enabling", afterSetNoCapOptionsError,
        100, 80, 3, NO, @[@"set:100"]);

    FakeChargeClient *enableMismatch = [FakeChargeClient new];
    enableMismatch.restoredByEnable = 95;
    CheckSet(@"different limit after enable cannot report success", enableMismatch,
        90, 100, 3, NO, @[@"set:90", @"enable"]);
    FakeChargeClient *enabledMismatch = [FakeChargeClient new];
    enabledMismatch.beforeRead = ^(FakeChargeClient *client, NSUInteger read) {
        if (read == 3) client.enabled = 3;
    };
    CheckSet(@"disabled readback after enable cannot report success", enabledMismatch,
        90, 100, 3, NO, @[@"set:90", @"enable"]);
    FakeChargeClient *finalReadError = [FakeChargeClient new];
    finalReadError.beforeRead = ^(FakeChargeClient *client, NSUInteger read) {
        if (read == 3) client.remainingReadFailures = 1;
    };
    CheckSet(@"final read error cannot report success", finalReadError,
        90, 100, 3, NO, @[@"set:90", @"enable"]);
    FakeChargeClient *finalNoCapOptionsError = [FakeChargeClient new];
    finalNoCapOptionsError.limit = 80;
    finalNoCapOptionsError.beforeRead = ^(FakeChargeClient *client, NSUInteger read) {
        if (read == 3) client.availableReportsError = YES;
    };
    CheckSet(@"100 final options NSError cannot report success", finalNoCapOptionsError,
        100, 80, 3, NO, @[@"set:100", @"enable"]);

    for (NSString *operation in @[@"supportThrows", @"readThrows", @"availableThrows",
                                  @"setThrows", @"enableThrows"]) {
        FakeChargeClient *client = [FakeChargeClient new];
        [client setValue:@YES forKey:operation];
        NSArray<NSString *> *writes = @[];
        if ([operation isEqual:@"setThrows"]) writes = @[@"set:90"];
        if ([operation isEqual:@"enableThrows"]) writes = @[@"set:90", @"enable"];
        CheckSet(@"PowerUI exception is a bounded failure", client,
            90, 100, 3, NO, writes);
    }
}

int main(void) {
    @autoreleasepool {
        TestExplicitSetter();
        for (NSNumber *limit in @[@80, @85, @90, @95]) {
            FakeChargeClient *client = [FakeChargeClient new];
            client.restoredByEnable = limit.unsignedCharValue;
            Check(@"enable restores without a limit write", client,
                limit.integerValue, YES, @[@"enable"]);
        }

        FakeChargeClient *readFailure = [FakeChargeClient new];
        readFailure.remainingReadFailures = 1;
        readFailure.restoredByEnable = 80;
        Check(@"snapshot survives an initial read failure", readFailure,
            80, YES, @[@"enable"]);

        FakeChargeClient *fallback = [FakeChargeClient new];
        Check(@"set only after enable cannot restore", fallback, 80, YES,
            @[@"enable", @"set:80", @"enable"]);

        FakeChargeClient *stored = [FakeChargeClient new];
        stored.limit = 90;
        Check(@"stored limit only needs enable", stored, 90, YES, @[@"enable"]);

        FakeChargeClient *external = [FakeChargeClient new];
        external.enabled = 1;
        external.limit = 90;
        Check(@"external active limit is preserved", external, 80, NO, @[]);

        FakeChargeClient *duringEnable = [FakeChargeClient new];
        duringEnable.restoredByEnable = 90;
        Check(@"different limit after enable is preserved", duringEnable,
            80, NO, @[@"enable"]);

        FakeChargeClient *enableError = [FakeChargeClient new];
        enableError.limit = 80;
        enableError.enableReportsError = YES;
        Check(@"enable NSError cannot report success", enableError,
            80, NO, @[@"enable"]);

        FakeChargeClient *setError = [FakeChargeClient new];
        setError.setReportsError = YES;
        Check(@"set NSError stops subsequent writes", setError, 80, NO,
            @[@"enable", @"set:80"]);

        FakeChargeClient *mismatch = [FakeChargeClient new];
        mismatch.failsVerification = YES;
        Check(@"verification mismatch cannot report success", mismatch, 80, NO,
            @[@"enable", @"set:80", @"enable"]);

        FakeChargeClient *unsupported = [FakeChargeClient new];
        unsupported.limits = @[@85, @90, @95, @100];
        Check(@"unsupported target never writes", unsupported, 80, NO, @[]);

        FakeChargeClient *active = [FakeChargeClient new];
        active.enabled = 1;
        active.limit = 80;
        Check(@"already restored is a no-op", active, 80, YES, @[]);

        FakeChargeClient *unlimited = [FakeChargeClient new];
        unlimited.limit = 100;
        Check(@"100% restore only enables MCL", unlimited, 100, YES, @[@"enable"]);

        FakeChargeClient *unlimitedActive = [FakeChargeClient new];
        unlimitedActive.enabled = 1;
        unlimitedActive.limit = 100;
        Check(@"100% already active is a no-op", unlimitedActive, 100, YES, @[]);

        FakeChargeClient *noMCL = [FakeChargeClient new];
        noMCL.supported = NO;
        Check(@"unsupported hardware never writes", noMCL, 80, NO, @[]);

        printf("PowerUI restore fake-client cases: %d, failures: %d; no real PowerUI load\n",
            cases, failures);
    }
    return failures == 0 ? 0 : 1;
}
