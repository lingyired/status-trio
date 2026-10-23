import Foundation
import Testing
@testable import StatusTrioCore

struct IconContentLegacyAdapterTests {
    @Test func everyV1SourceRoundTripsWithoutWritingConfiguration() throws {
        let configuration = IconConfigurationV1.classic
        let before = try JSONEncoder().encode(configuration)
        for source in RingSource.allCases where source != .none {
            let binding = try #require(IconContentLegacyAdapter.binding(for: source))
            #expect(IconContentLegacyAdapter.ringSource(for: binding) == source)
        }
        for source in CenterSource.allCases where source != .none {
            let binding = try #require(IconContentLegacyAdapter.binding(for: source))
            #expect(IconContentLegacyAdapter.centerSource(for: binding) == source)
        }
        for source in FooterSource.allCases where source != .none {
            let binding = try #require(IconContentLegacyAdapter.binding(for: source))
            #expect(IconContentLegacyAdapter.footerSource(for: binding) == source)
        }
        #expect(IconContentLegacyAdapter.binding(for: RingSource.none) == nil)
        #expect(IconContentLegacyAdapter.binding(for: CenterSource.none) == nil)
        #expect(IconContentLegacyAdapter.binding(for: FooterSource.none) == nil)
        #expect(IconContentLegacyAdapter.ringSource(for: .init(pluginID: "unknown", presentationID: "ring")) == nil)
        let after = try JSONEncoder().encode(configuration)
        #expect(try JSONSerialization.jsonObject(with: before) as? NSDictionary == JSONSerialization.jsonObject(with: after) as? NSDictionary)
    }
}
