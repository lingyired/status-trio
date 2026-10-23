import Foundation
import Testing
@testable import StatusTrioCore

struct AudioInputVolumeDraftTests {
    @Test
    func quickClickKeepsRequestedValueUntilSystemReadback() {
        var draft = AudioInputVolumeDraft()
        draft.receiveSystemScalar(0.5)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.5) { _, _ in }
        draft.setEditing(false)

        #expect(draft.value == 0.8)
        #expect(draft.accessibilityValue(systemScalar: 0.5, locale: Locale(identifier: "en_US")) == "80%")

        draft.receiveSystemScalar(0.8)
        #expect(draft.value == 0.8)
    }

    @Test
    func repeatedMouseUpAndLateSetterCannotRestoreOldReadback() {
        var draft = AudioInputVolumeDraft()
        var requests: [Double] = []
        draft.receiveSystemScalar(0.5)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.5) { value, _ in requests.append(value) }
        draft.setEditing(false)
        draft.setEditing(false)
        draft.setSliderValue(0.7, systemScalar: 0.5) { value, _ in requests.append(value) }

        #expect(draft.value == 0.8)
        #expect(requests == [0.8])
    }

    @Test
    func completedWriteCanRestoreUnchangedSystemValue() {
        var draft = AudioInputVolumeDraft()
        draft.receiveSystemScalar(0.5)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.5) { _, _ in }
        draft.setEditing(false)

        #expect(draft.value == 0.8)
        draft.receiveSystemScalar(0.5)
        #expect(draft.value == 0.5)
    }

    @Test
    func switchingDevicesDiscardsPendingValueEvenAtSameSystemVolume() {
        var draft = AudioInputVolumeDraft()
        draft.receiveSystemState(deviceIdentity: .init(rawValue: 11), scalar: 0.5)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.5) { _, _ in }
        draft.setEditing(false)

        #expect(draft.value == 0.8)
        draft.receiveSystemState(deviceIdentity: .init(rawValue: 22), scalar: 0.5)
        #expect(draft.value == 0.5)
        #expect(draft.isEditing == false)
    }

    @Test
    func missingReadbackDoesNotExposePendingPercentage() {
        var draft = AudioInputVolumeDraft()
        draft.receiveSystemScalar(0.5)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.5) { _, _ in }
        draft.setEditing(false)
        draft.receiveSystemScalar(nil)

        #expect(draft.value == 0)
        #expect(draft.accessibilityValue(systemScalar: nil, locale: Locale(identifier: "en_US")) == "—")
    }

    @Test
    func busySnapshotKeepsDraftUntilUnchangedReadbackIsConfirmed() {
        var draft = AudioInputVolumeDraft()
        var requestID: UUID?
        draft.receiveSystemState(deviceIdentity: .init(rawValue: 11), scalar: 0.5)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.5) { _, id in requestID = id }
        draft.setEditing(false)
        draft.receiveSystemState(
            deviceIdentity: .init(rawValue: 11), scalar: 0.5,
            canAdjust: false, isBusy: true
        )
        #expect(draft.value == 0.8)

        draft.receiveSystemState(
            deviceIdentity: .init(rawValue: 11), scalar: 0.5,
            canAdjust: true, isBusy: false,
            completedScalarRequestID: requestID
        )
        #expect(draft.value == 0.5)
    }

    @Test
    func readOnlySnapshotDiscardsPendingValueWithoutScalarChange() {
        var draft = pendingDraft()
        draft.receiveSystemState(
            deviceIdentity: .init(rawValue: 11), scalar: 0.5,
            canAdjust: false
        )
        #expect(draft.value == 0.5)
        #expect(draft.accessibilityValue(systemScalar: 0.5, locale: Locale(identifier: "en_US")) == "50%")
    }

    @Test
    func errorSnapshotDiscardsPendingValueEvenWhileCommandIsBusy() {
        var draft = pendingDraft()
        draft.receiveSystemState(
            deviceIdentity: .init(rawValue: 11), scalar: 0.5,
            canAdjust: false, isBusy: true, hasError: true
        )
        #expect(draft.value == 0.5)
        #expect(draft.isEditing == false)
    }

    @Test
    func unrelatedSnapshotDoesNotRestorePreWriteValue() {
        var draft = pendingDraft()
        draft.receiveSystemState(deviceIdentity: .init(rawValue: 11), scalar: 0.5)
        #expect(draft.value == 0.8)
    }

    @Test
    func unacknowledgedChangedReadbackDoesNotConfirmPendingRequest() {
        var draft = pendingDraft()
        draft.receiveSystemState(deviceIdentity: .init(rawValue: 11), scalar: 0.75)
        #expect(draft.value == 0.8)
    }

    @Test
    func olderRequestCompletionCannotOverwriteNewerClick() {
        var draft = AudioInputVolumeDraft()
        var requestIDs: [UUID] = []
        draft.receiveSystemState(deviceIdentity: .init(rawValue: 11), scalar: 0.2)
        draft.setEditing(true)
        draft.setSliderValue(0.4, systemScalar: 0.2) { _, id in requestIDs.append(id) }
        draft.setEditing(false)
        draft.setEditing(true)
        draft.setSliderValue(0.71, systemScalar: 0.2) { _, id in requestIDs.append(id) }
        draft.setEditing(false)

        draft.receiveSystemState(
            deviceIdentity: .init(rawValue: 11), scalar: 0.4,
            completedScalarRequestID: requestIDs[0]
        )
        #expect(draft.value == 0.71)
        draft.receiveSystemState(
            deviceIdentity: .init(rawValue: 11), scalar: 0.709,
            completedScalarRequestID: requestIDs[1]
        )
        #expect(draft.value == 0.709)

        // Once this request is confirmed, external changes remain authoritative.
        draft.receiveSystemState(
            deviceIdentity: .init(rawValue: 11), scalar: 0.6,
            completedScalarRequestID: requestIDs[1]
        )
        #expect(draft.value == 0.6)
    }

    @Test
    func secondClickBackToOriginalValueReplacesPendingWrite() {
        var draft = AudioInputVolumeDraft()
        var requests: [Double] = []
        draft.receiveSystemScalar(0.5)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.5) { value, _ in requests.append(value) }
        draft.setEditing(false)
        draft.setEditing(true)
        draft.setSliderValue(0.5, systemScalar: 0.5) { value, _ in requests.append(value) }
        draft.setEditing(false)

        #expect(requests == [0.8, 0.5])
        #expect(draft.value == 0.5)
    }

    private func pendingDraft() -> AudioInputVolumeDraft {
        var draft = AudioInputVolumeDraft()
        draft.receiveSystemState(deviceIdentity: .init(rawValue: 11), scalar: 0.5)
        draft.setEditing(true)
        draft.setSliderValue(0.8, systemScalar: 0.5) { _, _ in }
        draft.setEditing(false)
        return draft
    }
}
