#import <Foundation/Foundation.h>
#import <dlfcn.h>

static void *STForbiddenLoad(const char *path, int mode) {
    (void)path;
    (void)mode;
    abort();
}

// Exercise the production restore routine with a fake client. Even an
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
- (BOOL)isMCLSupported { return self.supported; }
- (NSUInteger)isMCLCurrentlyEnabled:(NSError **)error {
    (void)error;
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
    (void)error;
    return self.limits;
}
- (BOOL)smartChargingUIState:(NSUInteger *)state
                 chargeLimit:(NSUInteger *)limit
     chargingOverrideAllowed:(BOOL *)allowed
                   withError:(NSError **)error {
    (void)error;
    *state = 13;
    *limit = self.limit;
    *allowed = NO;
    return YES;
}
- (BOOL)temporarilyDisableMCL:(NSError **)error {
    (void)error;
    abort();
}
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error {
    [self.writes addObject:[NSString stringWithFormat:@"set:%u", limit]];
    self.limit = self.failsVerification ? 100 : limit;
    if (self.setReportsError) {
        *error = [NSError errorWithDomain:@"FakeSet" code:2 userInfo:nil];
    }
    return YES;
}
- (BOOL)enableMCL:(NSError **)error {
    [self.writes addObject:@"enable"];
    self.enabled = 1;
    if (self.restoredByEnable > 0) self.limit = self.restoredByEnable;
    if (self.enableReportsError) {
        *error = [NSError errorWithDomain:@"FakeEnable" code:3 userInfo:nil];
    }
    return YES;
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

int main(void) {
    @autoreleasepool {
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

        FakeChargeClient *noMCL = [FakeChargeClient new];
        noMCL.supported = NO;
        Check(@"unsupported hardware never writes", noMCL, 80, NO, @[]);

        printf("PowerUI restore fake-client cases: %d, failures: %d; no real PowerUI load\n",
            cases, failures);
    }
    return failures == 0 ? 0 : 1;
}
