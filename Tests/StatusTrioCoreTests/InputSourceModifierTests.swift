import AppKit
import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class InputSourceModifierTests: XCTestCase {
    private let abc = InputSourceDescriptor(
        id: "com.apple.keylayout.ABC", localizedName: "ABC", primaryLanguage: "en",
        iconURL: URL(fileURLWithPath: "/fixture/abc.pdf"), shortLabel: "A"
    )

    func testEnglishLayoutKeepsUppercaseWithCapsLockAndShiftAndOverridesIcon() {
        for (caps, shift, expected) in [(false, false, "a"), (false, true, "A"),
                                       (true, false, "A"), (true, true, "A")] {
            let descriptor = abc.applying(InputSourceModifiers(capsLock: caps, shift: shift))
            XCTAssertEqual(descriptor.shortLabel, expected)
            XCTAssertNil(descriptor.iconURL)
            XCTAssertEqual(descriptor.id, abc.id)
        }
    }

    func testNonEnglishAndUnknownInputMethodsKeepTheirIdentity() {
        for id in ["com.apple.inputmethod.SCIM.ITABC", "com.example.EnglishIME"] {
            let source = InputSourceDescriptor(id: id, localizedName: "Input", primaryLanguage: "en",
                                               iconURL: abc.iconURL, shortLabel: "拼")
            XCTAssertEqual(source.applying(.init(capsLock: true, shift: true)), source)
        }
    }

    func testModifierUpdatesShareStateWithoutRereadingTISAndStopRemovesObserver() {
        let reader = ModifierSourceReader()
        let modifiers = FakeInputSourceModifierObserver()
        let controller = InputSourceController(reader: reader, modifierObserver: modifiers)
        controller.start()
        controller.start()
        XCTAssertEqual(modifiers.startCount, 1)
        XCTAssertEqual(controller.state.iconDescriptor(markerStyle: .systemIcon)?.shortLabel, "a")
        XCTAssertEqual(controller.selectedDescriptor?.shortLabel, "A", "panel identity stays unchanged")
        let reads = reader.reads
        var emissions = 0
        let subscription = controller.$state.sink { _ in emissions += 1 }
        modifiers.emit(.init(capsLock: false, shift: true))
        XCTAssertEqual(controller.state.iconDescriptor(markerStyle: .systemIcon)?.shortLabel, "A")
        XCTAssertEqual(reader.reads, reads)
        let afterChange = emissions
        modifiers.emit(.init(capsLock: false, shift: true))
        XCTAssertEqual(emissions, afterChange)
        controller.stop()
        XCTAssertEqual(modifiers.stopCount, 1)
        let stoppedState = controller.state
        modifiers.emit(.init(capsLock: true, shift: true))
        XCTAssertEqual(controller.state, stoppedState, "late events cannot publish after stop")
        controller.start()
        XCTAssertEqual(controller.state.iconDescriptor(markerStyle: .systemIcon)?.shortLabel, "A", "restart reads current modifiers")
        subscription.cancel()
        controller.stop()
    }

    func testLowercaseAndUppercaseProduceDifferentScenesAndDockCacheKeys() {
        let lower = abc.applying(.init(capsLock: false, shift: false))
        let upper = abc.applying(.init(capsLock: true, shift: false))
        let options = ConnectionIconOptions(centerSource: .inputSource, prioritizesNetworkErrors: false)
        let lowScene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil, inputSource: lower),
            configuration: IconPresentationConfiguration(battery: .standard, connection: options, volume: .standard, bluetooth: .standard)
        )
        let highScene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil, inputSource: upper),
            configuration: IconPresentationConfiguration(battery: .standard, connection: options, volume: .standard, bluetooth: .standard)
        )
        XCTAssertNotEqual(lowScene, highScene)
        XCTAssertNotEqual(
            DockIconRenderKey(scene: lowScene, backgroundStyle: .clear, pixelLength: 128),
            DockIconRenderKey(scene: highScene, backgroundStyle: .clear, pixelLength: 128)
        )
    }
}

private final class ModifierSourceReader: InputSourceReading {
    var reads = 0
    func currentKeyboardInputSourceID() -> String? { "com.apple.keylayout.ABC" }
    func keyboardInputSources() -> [RawInputSource] {
        reads += 1
        return [RawInputSource(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"],
                               iconImageURL: nil, isEnabled: true, isSelectCapable: true)]
    }
}

@MainActor
private final class FakeInputSourceModifierObserver: InputSourceModifierObserving {
    var startCount = 0
    var stopCount = 0
    var current = InputSourceModifiers(capsLock: false, shift: false)
    var handler: (@MainActor (InputSourceModifiers) -> Void)?
    func start(handler: @escaping @MainActor (InputSourceModifiers) -> Void) {
        startCount += 1
        self.handler = handler
        handler(current)
    }
    func stop() { stopCount += 1 }
    func emit(_ value: InputSourceModifiers) { current = value; handler?(value) }
}
