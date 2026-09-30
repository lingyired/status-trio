import Testing
@testable import StatusTrioCore

struct AppleBluetoothAudioResolverTests {
    @Test("AirPods 5 resolves from either confirmed Bluetooth product ID")
    func airPodsFiveResolvesFromProductIDs() {
        #expect(AppleBluetoothAudioResolver.airPodsModel(productID: 0x2030, vendorID: 0x004C) == .airPodsGen5)
        #expect(AppleBluetoothAudioResolver.airPodsModel(productID: 0x2036, vendorID: 0x004C) == .airPodsGen5)
        #expect(AppleBluetoothAudioResolver.airPodsModel(modelUID: "2030 4c") == .airPodsGen5)
        #expect(AppleBluetoothAudioResolver.airPodsModel(modelUID: "2036 4c") == .airPodsGen5)
    }

    @Test("AirPods name fallback resolves the generation wording")
    func nameFallbackResolvesGeneration() {
        for name in ["AirPods 5", "Ling's AirPods 5", "AirPods gen5", "AirPods 第5代"] {
            #expect(
                AppleBluetoothAudioResolver.airPodsModel(name: name) == .airPodsGen5,
                Comment(stringLiteral: name)
            )
        }
        #expect(AppleBluetoothAudioResolver.airPodsModel(name: "AirPods 第五代") == .airPods)
        #expect(AppleBluetoothAudioResolver.airPodsModel(name: "My Earbuds") == nil)
        #expect(AppleBluetoothAudioResolver.airPodsModel(name: "AirPods 3 gen4") == .airPodsGen4)
        #expect(AppleBluetoothAudioResolver.airPodsModel(name: "AirPods 5 gen3") == .airPodsGen3)
    }

    @Test("The Apple product table covers the confirmed hardware families")
    func confirmedFamiliesResolve() {
        let cases: [(Int, AirPodsModel)] = [
            (0x201C, .airPodsGen4),
            (0x201E, .airPodsGen4),
            (0x2020, .airPodsGen4),
            (0x201F, .airPodsMax),
            (0x2024, .airPodsPro),
            (0x202D, .airPodsMax)
        ]
        for (productID, expected) in cases {
            #expect(
                AppleBluetoothAudioResolver.airPodsModel(productID: productID, vendorID: 0x004C) == expected,
                "0x\(String(productID, radix: 16))"
            )
        }
        #expect(AppleBluetoothAudioResolver.airPodsModel(productID: 0x2030, vendorID: 0x1234) == nil)
        #expect(AppleBluetoothAudioResolver.airPodsModel(productID: 0x2042, vendorID: 0x004C) == nil)
    }
}
