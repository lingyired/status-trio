#ifndef POWER_UI_PRIVATE_API_H
#define POWER_UI_PRIVATE_API_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, STPowerUIChargeAvailabilityReason) {
    STPowerUIChargeAvailabilityReasonAvailable = 0,
    STPowerUIChargeAvailabilityReasonUnsupportedSystem,
    STPowerUIChargeAvailabilityReasonUnsupportedArchitecture,
    STPowerUIChargeAvailabilityReasonFrameworkUnavailable,
    STPowerUIChargeAvailabilityReasonAPIUnavailable,
    STPowerUIChargeAvailabilityReasonMCLUnsupported
};

@interface STPowerUIChargeCapability : NSObject
@property (nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, readonly) STPowerUIChargeAvailabilityReason reason;
@end

@interface STPowerUIChargeState : NSObject
@property (nonatomic, readonly, getter=hasValidState) BOOL validState;
@property (nonatomic, readonly) NSUInteger mclEnabledRawValue;
/// `-1` when the value could not be read.
@property (nonatomic, readonly) NSInteger mclLimit;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *availableChargeLimits;
@property (nonatomic, readonly) BOOL chargingOverrideAllowed;
@property (nonatomic, copy, readonly, nullable) NSString *errorMessage;
@end

@interface STPowerUIChargeWriteResult : NSObject
@property (nonatomic, readonly, getter=didSucceed) BOOL succeeded;
@property (nonatomic, copy, readonly, nullable) NSString *errorMessage;
@end

/// Dynamically loads PowerUI. It never statically links the private framework.
@interface STPowerUIChargeBridge : NSObject
- (STPowerUIChargeCapability *)capability;
- (STPowerUIChargeState *)readState;
/// Sends one request. The caller owns user intent, revalidation, and de-duplication.
- (STPowerUIChargeWriteResult *)temporarilyDisableMCL;
/// Enables MCL at `limit`, using `setMCLLimit:error:` only when required.
- (STPowerUIChargeWriteResult *)restoreChargeLimit:(NSInteger)limit;
/// Applies explicit user intent only while a fresh state matches the expected
/// limit and raw enabled value. Sub-100 targets must be advertised by PowerUI;
/// 100 restores no cap. Sends at most one set and one enable request.
- (STPowerUIChargeWriteResult *)setChargeLimit:(NSInteger)limit
                         expectedCurrentLimit:(NSInteger)expectedCurrentLimit
                         expectedEnabledState:(NSUInteger)expectedEnabledState
    NS_SWIFT_NAME(applyChargeLimit(_:expectedCurrentLimit:expectedEnabledState:));
@end

NS_ASSUME_NONNULL_END

#endif
