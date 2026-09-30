import Testing
@testable import StatusTrioCore

/// macOS declares the AirPods family itself: every `com.apple.airpods*` type in
/// `CoreTypes.bundle/Contents/Info.plist` carries a
/// `public.bluetooth-vendor-product-id` tag such as `76:8207`, which is the
/// decimal product ID `0x200F` for AirPods (2nd generation).
///
/// A user with AirPods (2nd generation, A2031/A2032) reported the generic
/// headphone glyph, so the product ID is what has to decide the icon when the
/// device name does not spell "AirPods".
struct AirPodsModelTests {
    @Test("AirPods (2nd generation) resolves to the AirPods glyph")
    func secondGenerationResolvesToAirPods() {
        // A2031/A2032 is product 0x200F; CoreAudio reports it in the device's
        // model UID as "200f 4c" (product, then Apple's vendor ID 0x004C).
        #expect(AirPodsModel(productID: 0x200F, vendorID: 0x004C) == .airPods)
        #expect(AirPodsModel(productID: 0x200F, vendorID: 0x004C)?.kind == .airPods)
        #expect(AirPodsModel(modelUID: "200f 4c") == .airPods)
        #expect(AirPodsModel(productIDText: "0x200F", vendorIDText: "0x004C") == .airPods)
        // A model UID that carries the product ID without the vendor ID still
        // identifies the model.
        #expect(AirPodsModel(modelUID: "200f") == .airPods)
        #expect(AirPodsModel(productID: 0x200F) == .airPods)
    }

    @Test("Every AirPods model macOS declares maps to its own icon class")
    func everyDeclaredModelMapsToItsIconClass() {
        let declared: [(productID: Int, model: AirPodsModel, kind: AudioOutputDeviceKind)] = [
            (0x2002, .airPods, .airPods),              // AirPods (1st generation)
            (0x200F, .airPods, .airPods),              // AirPods (2nd generation)
            (0x2013, .airPodsGen3, .airPodsGen3),      // AirPods (3rd generation)
            (0x2019, .airPodsGen4, .airPodsGen4),      // AirPods 4
            (0x201B, .airPodsGen4, .airPodsGen4),      // AirPods 4 with ANC
            (0x201C, .airPodsGen4, .airPodsGen4),
            (0x201E, .airPodsGen4, .airPodsGen4),
            (0x2020, .airPodsGen4, .airPodsGen4),
            (0x2030, .airPodsGen5, .airPodsGen5),      // AirPods 5
            (0x2036, .airPodsGen5, .airPodsGen5),
            (0x200E, .airPodsProGen1, .airPodsProGen1),// AirPods Pro
            (0x2014, .airPodsPro, .airPodsPro),        // AirPods Pro (2nd generation)
            (0x2024, .airPodsPro, .airPodsPro),        // AirPods Pro 2 USB-C
            (0x2027, .airPodsProGen3, .airPodsProGen3),// AirPods Pro 3
            (0x2028, .airPodsProGen3, .airPodsProGen3),
            (0x200A, .airPodsMax, .airPodsMax),        // AirPods Max
            (0x201F, .airPodsMax, .airPodsMax),        // AirPods Max USB-C
            (0x202D, .airPodsMax, .airPodsMax)         // AirPods Max 2
        ]

        for entry in declared {
            #expect(
                AirPodsModel(productID: entry.productID, vendorID: 0x004C) == entry.model,
                "product \(String(entry.productID, radix: 16))"
            )
            #expect(AirPodsModel(productID: entry.productID, vendorID: 0x004C)?.kind == entry.kind)
        }
    }

    @Test("A product ID from another vendor is never an AirPods")
    func otherVendorsAreRejected() {
        // The paired EDIFIER LolliPods report vendor 0x05D6.
        #expect(AirPodsModel(productID: 0x200F, vendorID: 0x05D6) == nil)
        #expect(AirPodsModel(modelUID: "200f 5d6") == nil)
        #expect(AirPodsModel(productIDText: "0x200F", vendorIDText: "0x05D6") == nil)
    }

    @Test("A model UID that is not a product pair is not an AirPods")
    func nonProductModelUIDsAreRejected() {
        // Built-in and USB hardware report names, not product IDs.
        #expect(AirPodsModel(modelUID: "Speaker") == nil)
        #expect(AirPodsModel(modelUID: "Digital Mic") == nil)
        #expect(AirPodsModel(modelUID: "") == nil)
        #expect(AirPodsModel(modelUID: nil) == nil)
        #expect(AirPodsModel(modelUID: "2042 4c") == nil)
        #expect(AirPodsModel(productID: nil) == nil)
        #expect(AirPodsModel(productID: 0) == nil)
        #expect(AirPodsModel(productIDText: nil, vendorIDText: nil) == nil)
    }
}
