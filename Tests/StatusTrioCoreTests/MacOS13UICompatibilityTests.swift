import Foundation
import XCTest

final class MacOS13UICompatibilityTests: XCTestCase {
    func testCompatibleViewsDoNotUseTheMacOS14TwoParameterOnChangeOverload() throws {
        let files = [
            "Sources/StatusTrioCore/UI/AudioInputControlsView.swift",
            "Sources/StatusTrioCore/UI/BluetoothDeviceList.swift",
            "Sources/StatusTrioCore/UI/BluetoothStatusView.swift",
            "Sources/StatusTrioCore/UI/IconGuideView.swift",
            "Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift",
            "Sources/StatusTrioCore/UI/VolumeControlsView.swift"
        ]
        // Match the two-parameter closure in one line only. A multiline
        // regex here can run from an unrelated opening brace to the next
        // `_ ,` and report false positives in large view files.
        let pattern = try NSRegularExpression(
            pattern: #"\.onChange\(of:[^)]*\)\s*\{\s*_[^,]*,.*\}"#
        )

        for path in files {
            let source = try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            XCTAssertNil(
                pattern.firstMatch(in: source, range: range),
                "\(path) still uses the macOS 14 two-parameter onChange overload"
            )
        }
    }

    func testStatusPopoverUsesVenturaSafeHostingSizing() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/StatusTrioCore/UI/StatusBarController.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("if #available(macOS 14.0, *)"))
        XCTAssertTrue(source.contains("hostingController.sizingOptions = [.preferredContentSize]"))
    }

    func testOnboardingUsesVenturaSafeHostingSizing() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/StatusTrioCore/UI/OnboardingWindowController.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("if #available(macOS 14.0, *)"))
        XCTAssertTrue(source.contains("hostingController.sizingOptions = [.preferredContentSize]"))
        XCTAssertFalse(source.contains("hostingController.view.layoutSubtreeIfNeeded()"))
    }

    func testBluetoothViewsRouteEveryVisibilityChangeThroughASnapshot() throws {
        let statusSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/StatusTrioCore/UI/BluetoothStatusView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(statusSource.contains(".onChange(of: readAuthorizationSnapshot)"))
        XCTAssertTrue(statusSource.contains("updateReadAuthorization(snapshot)"))
        XCTAssertFalse(statusSource.contains(".onChange(of: showsBatteryLevels) { _ in updateNearbyReadAuthorization() }"))
        XCTAssertFalse(statusSource.contains(".onChange(of: showsAppleDevicesAndBattery) { _ in updateNearbyReadAuthorization() }"))

        let listSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/StatusTrioCore/UI/BluetoothDeviceList.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(listSource.contains("BluetoothDeviceListVisibilitySnapshot"))
        XCTAssertTrue(listSource.contains(".onChange(of: visibilitySnapshot)"))
    }

    func testPictureRowKeepsNativeActivationAndUsesMoveCommandForArrows() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/StatusTrioCore/UI/Settings/SettingsChrome.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".onMoveCommand"))
        XCTAssertTrue(source.contains(".onKeyPress"))
        XCTAssertEqual(
            source.components(separatedBy: ".focusEffectDisabled()").count - 1,
            1,
            "focusEffectDisabled must appear only in the macOS 14+ compatibility modifier"
        )
        let availability = try XCTUnwrap(source.range(of: "if #available(macOS 14.0, *)"))
        let focusEffect = try XCTUnwrap(source.range(of: ".focusEffectDisabled()"))
        XCTAssertLessThan(availability.lowerBound, focusEffect.lowerBound)
        XCTAssertTrue(source.contains("selectOption(option)"))
    }

    /// The icon audit in `docs/ventura-icon-availability.md`, enforced.
    ///
    /// Every string literal under `Sources` is matched against the SF Symbols
    /// availability table macOS ships inside CoreGlyphs. A symbol this table
    /// says arrived after the macOS 13 deployment target must already be on the
    /// audited list, because each one is either a fallback in a candidate list
    /// or a value that never reaches a view. A glyph added later fails here by
    /// name instead of rendering blank on a Ventura Mac.
    ///
    /// The table is read from the host rather than vendored, so the check stays
    /// current. A host without it skips rather than guessing an answer.
    func testSourcesOnlyUseSymbolsTheVenturaAuditCovers() throws {
        let tableURL = URL(
            fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle"
                + "/Contents/Resources/name_availability.plist"
        )
        guard let data = try? Data(contentsOf: tableURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let years = plist["symbols"] as? [String: String],
              let releases = plist["year_to_release"] as? [String: [String: String]]
        else {
            throw XCTSkip("CoreGlyphs availability table is not present on this host")
        }

        var introduced: [String: String] = [:]
        for (symbol, year) in years {
            if let macOS = releases[year]?["macOS"] {
                introduced[symbol] = macOS
            }
        }

        let literalPattern = try NSRegularExpression(pattern: #""([^"\\\n]+)""#)
        var used: Set<String> = []
        let sourcesRoot = packageRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail("Sources directory is missing at \(sourcesRoot.path)")
            return
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in literalPattern.matches(in: source, range: range) {
                guard let literalRange = Range(match.range(at: 1), in: source) else { continue }
                let literal = String(source[literalRange])
                if introduced[literal] != nil {
                    used.insert(literal)
                }
            }
        }

        let tooNewForVentura = used.filter { Self.isNewerThanVentura(introduced[$0]) }
        let unaudited = tooNewForVentura.subtracting(Self.auditedPostVenturaSymbols)
        XCTAssertTrue(
            unaudited.isEmpty,
            "These SF Symbols postdate the macOS 13 deployment target and are not on the audited "
                + "list. Give each one a Ventura-safe fallback, then record it in "
                + "docs/ventura-icon-availability.md and auditedPostVenturaSymbols: "
                + unaudited.sorted().joined(separator: ", ")
        )
    }

    /// Every post-Ventura SF Symbol name that appears anywhere under `Sources`.
    ///
    /// The audio and paired-device tables resolve their rows at runtime, so the
    /// newer names live inside candidate lists that end on a symbol Ventura
    /// ships, or in the Bluetooth picker where AppKit availability filtering
    /// hides unsupported choices. `left`, `right`, and `microphone` are parse
    /// and class values, never drawn. `headset` is also a picker choice when
    /// available. `translate` is the one row the resolver still downgrades, to
    /// `character.bubble`.
    private static let auditedPostVenturaSymbols: Set<String> = [
        "airpods.gen4",
        "airpods.max",
        "airpods.pro",
        "airpods.pro.gen1",
        "airpods.pro.gen3",
        "battery.100percent",
        "battery.75percent",
        "beats.fitpro",
        "beats.pill",
        "beats.powerbeats.pro",
        "beats.powerbeats.pro.2",
        "beats.solobuds",
        "beats.studiobuds.plus",
        "flask.fill",
        "headphones.over.ear",
        "headset",
        "homepod.mini",
        "left",
        "macbook",
        "macmini.gen2",
        "microphone",
        "powerplug.portrait.fill",
        "right",
        "smartphone",
        "translate",
        "watch.analog"
    ]

    /// `13.7.8` counts as Ventura; `13.3` does not, because the package targets
    /// macOS 13.0 and a symbol added in 13.3 is missing on 13.0 through 13.2.
    private static func isNewerThanVentura(_ version: String?) -> Bool {
        guard let version else { return false }
        let parts = version.split(separator: ".").map { Int($0) ?? 0 }
        guard let major = parts.first else { return false }
        guard major == 13 else { return major > 13 }
        return parts.count > 1 && parts[1] > 0
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
