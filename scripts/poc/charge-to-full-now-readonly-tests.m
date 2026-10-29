#define CHARGE_TO_FULL_NOW_POC_TESTS 1
#import "charge-to-full-now-readonly.m"

@interface ChargeProbeFixture : NSObject
- (BOOL)supported;
- (NSUInteger)enabled:(NSError **)error;
- (unsigned char)limit:(NSError **)error;
- (BOOL)ui:(NSUInteger *)state limit:(NSUInteger *)limit allowed:(BOOL *)allowed error:(NSError **)error;
@end

@implementation ChargeProbeFixture
- (BOOL)supported { return YES; }
- (NSUInteger)enabled:(NSError **)error { (void)error; return 1; }
- (unsigned char)limit:(NSError **)error { (void)error; return 80; }
- (BOOL)ui:(NSUInteger *)state limit:(NSUInteger *)limit allowed:(BOOL *)allowed error:(NSError **)error {
    (void)state; (void)limit; (void)allowed; (void)error;
    return YES;
}
@end

@interface ChargeProbeInheritedFixture : ChargeProbeFixture
@end
@implementation ChargeProbeInheritedFixture
@end

static NSUInteger failures = 0;
static NSUInteger checks = 0;

static void Check(BOOL value, const char *name) {
    checks++;
    if (!value) {
        failures++;
        fprintf(stderr, "FAIL: %s\n", name);
    }
}

int main(void) {
    @autoreleasepool {
        Check(!ProbePlatformSupported((NSOperatingSystemVersion){26, 3, 9}, YES), "26.3 rejected");
        Check(ProbePlatformSupported((NSOperatingSystemVersion){26, 4, 0}, YES), "26.4 accepted");
        Check(ProbePlatformSupported((NSOperatingSystemVersion){27, 0, 1}, YES), "27 accepted");
        Check(!ProbePlatformSupported((NSOperatingSystemVersion){27, 0, 1}, NO), "Intel rejected");
        Class cls = ChargeProbeFixture.class;
        Check(!ProbeSignatureMatches(Nil, @selector(supported), @encode(BOOL), @[]), "missing class rejected");
        Check(!ProbeSignatureMatches(cls, NSSelectorFromString(@"missing"), @encode(BOOL), @[]), "missing selector rejected");
        Check(ProbeSignatureMatches(cls, @selector(supported), @encode(BOOL), @[]), "BOOL accepted");
        Check(!ProbeSignatureMatches(cls, @selector(enabled:), @encode(BOOL), @[@(@encode(NSError * __autoreleasing *))]), "NSUInteger cannot be called as BOOL");
        Check(ProbeSignatureMatches(cls, @selector(enabled:), @encode(NSUInteger), @[@(@encode(NSError * __autoreleasing *))]), "NSUInteger accepted");
        Check(ProbeSignatureMatches(cls, @selector(limit:), @encode(unsigned char), @[@(@encode(NSError * __autoreleasing *))]), "UInt8 accepted");
        Check(!ProbeSignatureMatches(cls, @selector(limit:), @encode(NSUInteger), @[@(@encode(NSError * __autoreleasing *))]), "UInt8 cannot be called as NSUInteger");
        Check(!ProbeSignatureMatches(cls, @selector(enabled:), @encode(NSUInteger), @[@(@encode(BOOL *))]), "wrong out pointer rejected");
        Check(!ProbeSignatureMatches(cls, @selector(enabled:), @encode(NSUInteger), @[]), "wrong argument count rejected");
        Check(ProbeSignatureMatches(cls, @selector(ui:limit:allowed:error:), @encode(BOOL),
              @[@(@encode(NSUInteger *)), @(@encode(NSUInteger *)), @(@encode(BOOL *)), @(@encode(NSError * __autoreleasing *))]),
              "all UI state out pointers accepted");
        Check(!ProbeSignatureMatches(cls, @selector(ui:limit:allowed:error:), @encode(BOOL),
              @[@(@encode(NSUInteger *)), @(@encode(NSUInteger *)), @(@encode(NSUInteger *)), @(@encode(NSError * __autoreleasing *))]),
              "BOOL out pointer cannot be called as NSUInteger");
        Check(ProbeSignatureMatches(ChargeProbeInheritedFixture.class, @selector(enabled:),
              @encode(NSUInteger), @[@(@encode(NSError * __autoreleasing *))]), "inherited implementation ABI checked");
        Check(!ProbeSignatureMatches(ChargeProbeInheritedFixture.class, @selector(enabled:),
              @encode(BOOL), @[@(@encode(NSError * __autoreleasing *))]), "inherited wrong ABI rejected");
        printf("Read-only PoC: %lu checks, %lu failures; PowerUI not loaded.\n",
               (unsigned long)checks, (unsigned long)failures);
    }
    return failures == 0 ? 0 : 1;
}
