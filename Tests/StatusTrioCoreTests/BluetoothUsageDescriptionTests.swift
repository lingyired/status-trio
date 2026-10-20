import Foundation
import XCTest
@testable import StatusTrioCore

final class BluetoothUsageDescriptionTests: XCTestCase {
    func testAppDeclaresTheBluetoothPurpose() throws {
        let values = try propertyList(at: root.appendingPathComponent("Support/Info.plist"))
        let purpose = try XCTUnwrap(values["NSBluetoothAlwaysUsageDescription"] as? String)

        XCTAssertTrue(purpose.contains("connection status"))
        XCTAssertTrue(purpose.contains("already trusted"))
        XCTAssertTrue(purpose.contains("battery/model metadata"))
        XCTAssertTrue(purpose.contains("explicitly authorized by BLE UUID"))
        XCTAssertTrue(purpose.contains("noise-control mode"))
        XCTAssertFalse(purpose.contains("Battery Service"))
    }

    func testEveryLanguageLocalizesTheBluetoothPurpose() throws {
        let english = try bluetoothPurpose(
            at: root.appendingPathComponent("Sources/StatusTrioCore/Resources/en.lproj/InfoPlist.strings")
        )

        for language in AppLanguage.allCases {
            let purpose = try bluetoothPurpose(
                at: root.appendingPathComponent(
                    "Sources/StatusTrioCore/Resources/\(language.rawValue).lproj/InfoPlist.strings"
                )
            )
            XCTAssertFalse(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if language != .english {
                XCTAssertNotEqual(purpose, english, "\(language.rawValue) must localize Bluetooth permission copy")
            }
        }
    }

    private func bluetoothPurpose(at url: URL) throws -> String {
        let values = try propertyList(at: url)
        return try XCTUnwrap(values["NSBluetoothAlwaysUsageDescription"] as? String, "\(url.path) is missing Bluetooth purpose")
    }

    private func propertyList(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
