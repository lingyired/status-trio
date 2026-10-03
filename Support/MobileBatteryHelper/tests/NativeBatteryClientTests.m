#import <Foundation/Foundation.h>
#import "../NativeBatteryClient.h"

#define CHECK(condition, message) do { if (!(condition)) { fprintf(stderr, "FAIL: %s\n", message); return NO; } } while (0)

typedef struct {
    NSArray<NSDictionary *> *devices;
    NSDictionary *pairRecord;
    NSDictionary *phoneValues;
    NSDictionary<NSString *, NSDictionary *> *companions;
    NSArray<NSString *> *watchIdentifiers;
    NSUInteger pairRequestCount;
    NSUInteger startSessionCount;
    NSUInteger configurationWriteCount;
    NSUInteger watchValueQueryCount;
    NSMutableArray<NSString *> *watchValueQueryIdentifiers;
    NSMutableArray<NSArray<NSString *> *> *requestedCompanionKeys;
    NSUInteger allocatedHandles;
    NSUInteger releasedHandles;
    BOOL failEnumeration;
    BOOL failSession;
} FakeNativeState;

static void *NewFakeHandle(FakeNativeState *state) {
    state->allocatedHandles++;
    return (__bridge_retained void *)[NSObject new];
}

static void FreeHandle(FakeNativeState *state, void *handle) {
    if (handle) {
        state->releasedHandles++;
        (void)CFBridgingRelease(handle);
    }
}

static int Enumerate(void *context, NSArray<NSDictionary *> **devices) {
    FakeNativeState *state = context;
    if (state->failEnumeration) return -1;
    *devices = state->devices;
    return 0;
}

static int CopyPairRecord(void *context, NSString *identifier, NSDictionary **record) {
    (void)identifier;
    FakeNativeState *state = context;
    if (!state->pairRecord) return -1;
    *record = state->pairRecord;
    return 0;
}

static void FreePairRecord(void *context, NSDictionary *record) { (void)context; (void)record; }
static int CreateLockdown(void *context, NSString *identifier, NSString *transport, void **client) {
    (void)identifier; (void)transport; *client = NewFakeHandle(context); return 0;
}
static int StartSession(void *context, void *client, NSDictionary *record, void **session) {
    (void)client; (void)record;
    FakeNativeState *state = context;
    state->startSessionCount++;
    if (state->failSession) return -1;
    *session = NewFakeHandle(state);
    return 0;
}
static void FreeSession(void *context, void *session) { FreeHandle(context, session); }
static void FreeLockdown(void *context, void *client) { FreeHandle(context, client); }
static int CopyPhone(void *context, void *session, NSDictionary **values) {
    (void)session; *values = ((FakeNativeState *)context)->phoneValues; return 0;
}
static int CreateCompanion(void *context, void *session, void **companion) {
    (void)session; *companion = NewFakeHandle(context); return 0;
}
static int CopyWatchIDs(void *context, void *companion, NSArray<NSString *> **identifiers) {
    (void)companion; *identifiers = ((FakeNativeState *)context)->watchIdentifiers; return 0;
}
static int CopyWatch(void *context, void *companion, NSString *identifier, NSArray<NSString *> *keys, NSDictionary **values) {
    (void)companion;
    FakeNativeState *state = context;
    state->watchValueQueryCount++;
    if (!state->watchValueQueryIdentifiers) state->watchValueQueryIdentifiers = [NSMutableArray array];
    if (!state->requestedCompanionKeys) state->requestedCompanionKeys = [NSMutableArray array];
    [state->watchValueQueryIdentifiers addObject:identifier];
    [state->requestedCompanionKeys addObject:keys];
    *values = state->companions[identifier];
    return *values ? 0 : -1;
}
static void FreeWatchIDs(void *context, NSArray<NSString *> *identifiers) { (void)context; (void)identifiers; }
static void FreeCompanion(void *context, void *companion) { FreeHandle(context, companion); }
static void FreeValues(void *context, NSDictionary *values) { (void)context; (void)values; }
static void FreeDevices(void *context, NSArray<NSDictionary *> *devices) { (void)context; (void)devices; }

static STMobileBatteryNativeAPI API(FakeNativeState *state) {
    return (STMobileBatteryNativeAPI){
        .context = state,
        .enumerateDevices = Enumerate,
        .copyPairRecord = CopyPairRecord,
        .freePairRecord = FreePairRecord,
        .createLockdownClient = CreateLockdown,
        .startSession = StartSession,
        .freeSession = FreeSession,
        .freeLockdownClient = FreeLockdown,
        .copyPhoneValues = CopyPhone,
        .createCompanionClient = CreateCompanion,
        .copyCompanionIdentifiers = CopyWatchIDs,
        .copyCompanionValues = CopyWatch,
        .freeCompanionIdentifiers = FreeWatchIDs,
        .freeCompanionClient = FreeCompanion,
        .freeValues = FreeValues,
        .freeDeviceList = FreeDevices,
    };
}

static FakeNativeState BaseState(void) {
    return (FakeNativeState){
        .devices = @[@{@"id": @"phone-1", @"transport": STMobileBatteryTransportUSB}],
        .pairRecord = @{@"HostID": @"host", @"SystemBUID": @"system"},
        .phoneValues = @{@"DeviceName": @"Phone", @"ProductType": @"iPhone18,1", @"BatteryCurrentCapacity": @71, @"BatteryIsCharging": @NO},
        .watchIdentifiers = @[@"watch-1"],
        .companions = @{@"watch-1": @{@"DeviceName": @"Watch", @"ProductType": @"Watch7,4", @"BatteryCurrentCapacity": @48, @"BatteryIsCharging": @YES}},
    };
}

static BOOL TestEmptyEnumeration(void) {
    FakeNativeState state = BaseState(); state.devices = @[];
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyDeviceList(API(&state), &error);
    CHECK(error == STMobileBatteryErrorNone, "empty enumeration is successful");
    CHECK([result[@"phones"] isEqual:@[]], "empty enumeration emits no phones");
    return YES;
}

static BOOL TestTransportDuplicatesCollapse(void) {
    FakeNativeState state = BaseState();
    state.devices = @[@{@"id": @"phone-1", @"transport": STMobileBatteryTransportUSB}, @{@"id": @"phone-1", @"transport": STMobileBatteryTransportNetwork}];
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyDeviceList(API(&state), &error);
    NSArray *phones = result[@"phones"];
    CHECK(error == STMobileBatteryErrorNone, "duplicate transports are accepted");
    CHECK(phones.count == 1, "USB and network duplicate is represented once");
    CHECK([phones.firstObject[@"transport"] isEqual:STMobileBatteryTransportUSB], "USB wins transport selection");
    return YES;
}

static BOOL TestUntrustedDeviceDoesNotPair(void) {
    FakeNativeState state = BaseState(); state.pairRecord = nil;
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    NSDictionary *phone = result[@"failures"][0];
    CHECK([phone[@"errorCode"] integerValue] == STMobileBatteryErrorTrustRequired, "missing existing trust record reports trust required");
    CHECK(state.pairRequestCount == 0, "trust validation never requests pairing");
    CHECK(state.startSessionCount == 0, "trust validation never starts a session");
    CHECK(state.configurationWriteCount == 0, "trust validation never writes configuration");
    return YES;
}

static BOOL TestDeviceListDoesNotRequireTrustOrReadValues(void) {
    FakeNativeState state = BaseState(); state.pairRecord = nil;
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyDeviceList(API(&state), &error);
    CHECK(error == STMobileBatteryErrorNone, "device enumeration does not require an existing pair record");
    CHECK([result[@"phones"] count] == 1, "untrusted phone can be listed for later structured failure");
    CHECK(state.startSessionCount == 0 && state.pairRequestCount == 0 && state.configurationWriteCount == 0, "device list performs no pairing/session/configuration operation");
    CHECK(state.watchValueQueryCount == 0, "device list reads no battery or companion values");
    return YES;
}

static BOOL TestDeviceListPreservesAvailableRoutesInUSBFirstOrder(void) {
    FakeNativeState state = BaseState();
    state.devices = @[@{ @"id": @"phone-1", @"transport": STMobileBatteryTransportNetwork },
                      @{ @"id": @"phone-1", @"transport": STMobileBatteryTransportUSB }];
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyDeviceList(API(&state), &error);
    NSDictionary *phone = result[@"phones"][0];
    CHECK(error == STMobileBatteryErrorNone, "device list with both routes succeeds");
    CHECK([phone[@"transport"] isEqual:STMobileBatteryTransportUSB], "USB remains the preferred transport");
    CHECK(([phone[@"availableTransports"] isEqual:@[@"usb", @"network"]]), "all routes are listed once in USB-first order");
    return YES;
}

static BOOL TestMissingHostIdentityDoesNotStartSession(void) {
    FakeNativeState state = BaseState(); state.pairRecord = @{@"SystemBUID": @"system"};
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    CHECK([result[@"failures"][0][@"errorCode"] integerValue] == STMobileBatteryErrorHostIdentityMissing, "missing HostID is rejected");
    CHECK(state.startSessionCount == 0, "invalid host identity is rejected before session start");
    return YES;
}

static BOOL TestInvalidPhonePercentageIsNotZero(void) {
    FakeNativeState state = BaseState(); state.phoneValues = @{@"BatteryCurrentCapacity": @"not-a-number"};
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    CHECK(error == STMobileBatteryErrorNone, "individual battery failure stays in successful envelope");
    CHECK([result[@"failures"][0][@"error"] isEqual:@"battery-unavailable"], "invalid percentage becomes structured device failure");
    CHECK([result[@"devices"] count] == 0, "invalid percentage does not become a zero reading");
    return YES;
}

static BOOL TestMissingPhonePercentageIsFailure(void) {
    FakeNativeState state = BaseState(); state.phoneValues = @{@"DeviceName": @"Phone"};
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    CHECK(error == STMobileBatteryErrorNone, "missing per-device battery keeps envelope successful");
    CHECK([result[@"failures"][0][@"error"] isEqual:@"battery-unavailable"], "missing percentage is a device failure");
    return YES;
}

static BOOL TestUnsupportedOptionalKeysRemainOptional(void) {
    FakeNativeState state = BaseState(); state.phoneValues = @{@"ProductType": @"iPhone18,1", @"BatteryCurrentCapacity": @100};
    state.companions = @{@"watch-1": @{@"ProductType": @"Watch7,4", @"BatteryCurrentCapacity": @0}};
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *phoneResult = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    NSDictionary *phone = phoneResult[@"devices"][0];
    NSDictionary *watchResult = STMobileBatteryCopyWatch(API(&state), @"phone-1", STMobileBatteryTransportUSB, @"watch-1", &error);
    NSDictionary *watch = watchResult[@"devices"][0];
    CHECK(error == STMobileBatteryErrorNone, "optional unsupported keys do not fail the split reads");
    CHECK([phone[@"batteryLevel"] isEqual:@100], "full phone battery is retained");
    CHECK(phone[@"name"] == nil, "unsupported phone name remains absent");
    CHECK([watch[@"batteryLevel"] isEqual:@0], "zero Watch battery is retained");
    CHECK(watch[@"name"] == nil, "unsupported Watch name remains absent");
    CHECK(watch[@"isCharging"] == nil, "unsupported Watch charging value remains absent");
    return YES;
}

static BOOL TestMultipleWatchesAreEnumerated(void) {
    FakeNativeState state = BaseState();
    state.watchIdentifiers = @[@"watch-1", @"watch-2"];
    state.companions = @{
        @"watch-1": @{@"ProductType": @"Watch7,4", @"BatteryCurrentCapacity": @48},
        @"watch-2": @{@"ProductType": @"Watch7,5", @"BatteryCurrentCapacity": @62},
    };
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    CHECK(error == STMobileBatteryErrorNone, "multiple Watches are accepted");
    CHECK([result[@"watchCandidates"] count] == 2, "all valid paired Watch identifiers are returned as candidates");
    CHECK(state.watchValueQueryCount == 0, "split phone read defers Watch value reads");
    return YES;
}

static BOOL TestEveryAllocatedHandleIsReleasedOnFailure(void) {
    FakeNativeState state = BaseState(); state.failSession = YES;
    STMobileBatteryError error = STMobileBatteryErrorNone;
    (void)STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    CHECK(state.allocatedHandles == state.releasedHandles, "client handles are released when session start fails");
    return YES;
}

static BOOL TestPhoneReadReturnsCandidatesWithoutReadingWatchValues(void) {
    FakeNativeState state = BaseState();
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    CHECK(error == STMobileBatteryErrorNone, "phone read succeeds");
    CHECK([result[@"devices"] count] == 1, "phone snapshot is returned independently");
    CHECK([result[@"watchCandidates"] count] == 1, "paired Watch identifier is returned as a candidate");
    CHECK(state.watchValueQueryCount == 0, "phone read does not query Watch values");
    return YES;
}

static BOOL TestSplitPhoneReadUsesSwiftWireFields(void) {
    FakeNativeState state = BaseState();
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    NSDictionary *phone = result[@"devices"][0];
    CHECK(error == STMobileBatteryErrorNone, "split phone read succeeds");
    CHECK([phone[@"batteryLevel"] isEqual:@71], "phone battery uses batteryLevel wire key");
    CHECK([phone[@"isCharging"] isEqual:@NO], "phone charging uses isCharging wire key");
    return YES;
}

static BOOL TestSplitPhoneUsesIsChargingWireKey(void) {
    FakeNativeState state = BaseState();
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    NSDictionary *phone = result[@"devices"][0];
    CHECK(error == STMobileBatteryErrorNone, "split phone read succeeds");
    CHECK([phone[@"isCharging"] isEqual:@NO], "phone charging uses isCharging wire key");
    return YES;
}

static BOOL TestPhoneBatteryFailureStillReturnsWatchCandidates(void) {
    FakeNativeState state = BaseState();
    state.phoneValues = @{@"DeviceName": @"Phone", @"ProductType": @"iPhone18,1"};
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyPhone(API(&state), @"phone-1", STMobileBatteryTransportUSB, &error);
    CHECK(error == STMobileBatteryErrorNone, "per-phone battery failure keeps the envelope successful");
    CHECK([result[@"failures"][0][@"error"] isEqual:@"battery-unavailable"], "phone battery failure is preserved");
    CHECK([result[@"watchCandidates"] count] == 1, "trusted companion registry is still returned after battery failure");
    CHECK(state.watchValueQueryCount == 0, "candidate recovery does not query Watch values");
    return YES;
}

static BOOL TestWatchReadQueriesOnlyRequestedPairedWatch(void) {
    FakeNativeState state = BaseState();
    state.watchIdentifiers = @[@"watch-1", @"watch-2"];
    state.companions = @{
        @"watch-1": @{@"ProductType": @"Watch7,4", @"BatteryCurrentCapacity": @48},
        @"watch-2": @{@"ProductType": @"Watch7,5", @"BatteryCurrentCapacity": @62},
    };
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyWatch(API(&state), @"phone-1", STMobileBatteryTransportUSB, @"watch-2", &error);
    CHECK(error == STMobileBatteryErrorNone, "Watch read succeeds");
    CHECK([result[@"devices"] count] == 1, "only the requested Watch snapshot is returned");
    CHECK([result[@"devices"][0][@"id"] isEqual:@"watch-2"], "requested Watch identity is preserved");
    CHECK(state.watchValueQueryIdentifiers.count == 1, "one Watch value query is made");
    CHECK([state.watchValueQueryIdentifiers[0] isEqual:@"watch-2"], "no other Watch identifier is queried");
    CHECK(([state.requestedCompanionKeys[0] isEqual:(@[@"ProductType", @"BatteryCurrentCapacity"])]), "bounded Watch reads query only required model and battery fields");
    CHECK([result[@"devices"][0][@"batteryLevel"] isEqual:@62], "Watch battery uses batteryLevel wire key");
    CHECK(result[@"devices"][0][@"isCharging"] == nil, "optional Watch charging remains absent");
    return YES;
}

static BOOL TestWatchReadRejectsUnpairedIdentifier(void) {
    FakeNativeState state = BaseState();
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyWatch(API(&state), @"phone-1", STMobileBatteryTransportUSB, @"other-watch", &error);
    CHECK([result[@"failures"][0][@"error"] isEqual:@"watch-not-paired"], "Watch identifier must appear in the current companion registry");
    CHECK(state.watchValueQueryCount == 0, "unpaired Watch identifier is never sent to companion value lookup");
    CHECK(state.allocatedHandles == state.releasedHandles, "client, session, and companion handles are released after registry rejection");
    return YES;
}

static BOOL TestWatchReadTrustFailureDoesNotStartSession(void) {
    FakeNativeState state = BaseState(); state.pairRecord = nil;
    STMobileBatteryError error = STMobileBatteryErrorNone;
    NSDictionary *result = STMobileBatteryCopyWatch(API(&state), @"phone-1", STMobileBatteryTransportUSB, @"watch-1", &error);
    CHECK([result[@"failures"][0][@"error"] isEqual:@"trust-required"], "Watch read requires existing phone trust");
    CHECK(state.pairRequestCount == 0 && state.startSessionCount == 0 && state.configurationWriteCount == 0, "Watch trust rejection performs no pairing work");
    return YES;
}

static BOOL TestShippingPhoneAndWatchRejectRealNumbersAndAcceptIntegerBoundaries(void) {
    NSArray *invalidValues = @[@72.0, @72.5, @YES, @"72"];
    for (id invalid in invalidValues) {
        FakeNativeState phoneState = BaseState();
        phoneState.phoneValues = @{ @"BatteryCurrentCapacity": invalid };
        STMobileBatteryError error = STMobileBatteryErrorNone;
        NSDictionary *phone = STMobileBatteryCopyPhone(API(&phoneState), @"phone-1", STMobileBatteryTransportUSB, &error);
        NSArray *phoneFailures = phone[@"failures"];
        CHECK([phoneFailures.firstObject[@"error"] isEqual:@"battery-unavailable"], "split phone rejects non-integer property-list number types");

        FakeNativeState watchState = BaseState();
        watchState.companions = @{ @"watch-1": @{ @"ProductType": @"Watch7,4", @"BatteryCurrentCapacity": invalid } };
        error = STMobileBatteryErrorNone;
        NSDictionary *watch = STMobileBatteryCopyWatch(API(&watchState), @"phone-1", STMobileBatteryTransportUSB, @"watch-1", &error);
        NSArray *watchFailures = watch[@"failures"];
        CHECK([watchFailures.firstObject[@"error"] isEqual:@"battery-unavailable"], "split Watch rejects non-integer property-list number types");
    }

    for (NSNumber *boundary in @[@0, @100]) {
        FakeNativeState phoneState = BaseState();
        phoneState.phoneValues = @{ @"BatteryCurrentCapacity": boundary };
        STMobileBatteryError error = STMobileBatteryErrorNone;
        NSDictionary *phone = STMobileBatteryCopyPhone(API(&phoneState), @"phone-1", STMobileBatteryTransportUSB, &error);
        CHECK([phone[@"devices"][0][@"batteryLevel"] isEqual:boundary], "split phone accepts integer percentage boundaries");

        FakeNativeState watchState = BaseState();
        watchState.companions = @{ @"watch-1": @{ @"ProductType": @"Watch7,4", @"BatteryCurrentCapacity": boundary } };
        error = STMobileBatteryErrorNone;
        NSDictionary *watch = STMobileBatteryCopyWatch(API(&watchState), @"phone-1", STMobileBatteryTransportUSB, @"watch-1", &error);
        CHECK([watch[@"devices"][0][@"batteryLevel"] isEqual:boundary], "split Watch accepts integer percentage boundaries");
    }
    return YES;
}

int main(void) {
    @autoreleasepool {
        NSArray<NSDictionary *> *tests = @[
            @{@"name": @"empty enumeration", @"run": [NSValue valueWithPointer:TestEmptyEnumeration]},
            @{@"name": @"transport deduplication", @"run": [NSValue valueWithPointer:TestTransportDuplicatesCollapse]},
            @{@"name": @"trust without pairing", @"run": [NSValue valueWithPointer:TestUntrustedDeviceDoesNotPair]},
            @{@"name": @"device list requires no trust", @"run": [NSValue valueWithPointer:TestDeviceListDoesNotRequireTrustOrReadValues]},
            @{@"name": @"list preserves available routes", @"run": [NSValue valueWithPointer:TestDeviceListPreservesAvailableRoutesInUSBFirstOrder]},
            @{@"name": @"host identity", @"run": [NSValue valueWithPointer:TestMissingHostIdentityDoesNotStartSession]},
            @{@"name": @"invalid percentage", @"run": [NSValue valueWithPointer:TestInvalidPhonePercentageIsNotZero]},
            @{@"name": @"missing percentage", @"run": [NSValue valueWithPointer:TestMissingPhonePercentageIsFailure]},
            @{@"name": @"unsupported optional keys", @"run": [NSValue valueWithPointer:TestUnsupportedOptionalKeysRemainOptional]},
            @{@"name": @"multiple Watches", @"run": [NSValue valueWithPointer:TestMultipleWatchesAreEnumerated]},
            @{@"name": @"cleanup", @"run": [NSValue valueWithPointer:TestEveryAllocatedHandleIsReleasedOnFailure]},
            @{@"name": @"phone read and candidates", @"run": [NSValue valueWithPointer:TestPhoneReadReturnsCandidatesWithoutReadingWatchValues]},
            @{@"name": @"split phone Swift wire keys", @"run": [NSValue valueWithPointer:TestSplitPhoneReadUsesSwiftWireFields]},
            @{@"name": @"split phone isCharging wire key", @"run": [NSValue valueWithPointer:TestSplitPhoneUsesIsChargingWireKey]},
            @{@"name": @"Watch candidates survive phone battery failure", @"run": [NSValue valueWithPointer:TestPhoneBatteryFailureStillReturnsWatchCandidates]},
            @{@"name": @"single Watch read", @"run": [NSValue valueWithPointer:TestWatchReadQueriesOnlyRequestedPairedWatch]},
            @{@"name": @"unpaired Watch rejection", @"run": [NSValue valueWithPointer:TestWatchReadRejectsUnpairedIdentifier]},
            @{@"name": @"Watch trust rejection", @"run": [NSValue valueWithPointer:TestWatchReadTrustFailureDoesNotStartSession]},
            @{@"name": @"shipping split percentage type validation", @"run": [NSValue valueWithPointer:TestShippingPhoneAndWatchRejectRealNumbersAndAcceptIntegerBoundaries]},
        ];
        NSUInteger failures = 0;
        for (NSDictionary *test in tests) {
            BOOL (*run)(void) = [test[@"run"] pointerValue];
            if (run()) NSLog(@"PASS: %@", test[@"name"]); else failures++;
        }
        return failures == 0 ? 0 : 1;
    }
}
