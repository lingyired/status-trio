#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, STMobileBatteryError) {
    STMobileBatteryErrorNone = 0,
    STMobileBatteryErrorEnumeration = 1,
    STMobileBatteryErrorTrustRequired = 2,
    STMobileBatteryErrorHostIdentityMissing = 3,
    STMobileBatteryErrorSession = 4,
    STMobileBatteryErrorBatteryUnavailable = 5,
};

typedef struct {
    void * _Nullable context;
    int (*enumerateDevices)(void * _Nullable context, NSArray<NSDictionary *> * _Nullable * _Nonnull devices);
    int (*copyPairRecord)(void * _Nullable context, NSString *identifier, NSDictionary * _Nullable * _Nonnull record);
    void (*freePairRecord)(void * _Nullable context, NSDictionary * _Nullable record);
    int (*createLockdownClient)(void * _Nullable context, NSString *identifier, NSString *transport, void * _Nullable * _Nonnull client);
    int (*startSession)(void * _Nullable context, void *client, NSDictionary *record, void * _Nullable * _Nonnull session);
    void (*freeSession)(void * _Nullable context, void * _Nullable session);
    void (*freeLockdownClient)(void * _Nullable context, void * _Nullable client);
    int (*copyPhoneValues)(void * _Nullable context, void *session, NSDictionary * _Nullable * _Nonnull values);
    int (*createCompanionClient)(void * _Nullable context, void *session, void * _Nullable * _Nonnull companion);
    int (*copyCompanionIdentifiers)(void * _Nullable context, void *companion, NSArray<NSString *> * _Nullable * _Nonnull identifiers);
    int (*copyCompanionValues)(void * _Nullable context, void *companion, NSString *identifier, NSArray<NSString *> *keys, NSDictionary * _Nullable * _Nonnull values);
    void (*freeCompanionIdentifiers)(void * _Nullable context, NSArray<NSString *> * _Nullable identifiers);
    void (*freeCompanionClient)(void * _Nullable context, void * _Nullable companion);
    void (*freeValues)(void * _Nullable context, NSDictionary * _Nullable values);
    void (*freeDeviceList)(void * _Nullable context, NSArray<NSDictionary *> * _Nullable devices);
} STMobileBatteryNativeAPI;

FOUNDATION_EXPORT NSString * const STMobileBatteryTransportUSB;
FOUNDATION_EXPORT NSString * const STMobileBatteryTransportNetwork;

FOUNDATION_EXPORT NSDictionary *STMobileBatteryCopyDeviceList(STMobileBatteryNativeAPI api, STMobileBatteryError * _Nullable error);
FOUNDATION_EXPORT NSDictionary *STMobileBatteryCopyPhone(STMobileBatteryNativeAPI api, NSString *identifier, NSString *transport, STMobileBatteryError * _Nullable error);
FOUNDATION_EXPORT NSDictionary *STMobileBatteryCopyWatch(STMobileBatteryNativeAPI api, NSString *phoneIdentifier, NSString *transport, NSString *watchIdentifier, STMobileBatteryError * _Nullable error);
FOUNDATION_EXPORT STMobileBatteryNativeAPI STMobileBatteryProductionAPI(void);

NS_ASSUME_NONNULL_END
