import Foundation

/// Resolves Apple Bluetooth audio identities shared by Bluetooth and CoreAudio.
enum AppleBluetoothAudioResolver {
    static func airPodsModel(productID: Int?, vendorID: Int?) -> AirPodsModel? {
        AirPodsModel(productID: productID, vendorID: vendorID)
    }

    static func airPodsModel(modelUID: String?) -> AirPodsModel? {
        AirPodsModel(modelUID: modelUID)
    }

    static func airPodsModel(name: String?) -> AirPodsModel? {
        let normalizedName = (name ?? "").lowercased()
        guard normalizedName.contains("airpods") else { return nil }

        if normalizedName.contains("airpods max") {
            return .airPodsMax
        }

        let generation = airPodsGeneration(in: normalizedName)
        if normalizedName.contains("airpods pro") {
            switch generation {
            case 1:
                return .airPodsProGen1
            case 3:
                return .airPodsProGen3
            default:
                return .airPodsPro
            }
        }

        switch generation {
        case 5:
            return .airPodsGen5
        case 4:
            return .airPodsGen4
        case 3:
            return .airPodsGen3
        default:
            return .airPods
        }
    }

    private static func matchesGeneration(_ name: String, generation: Int) -> Bool {
        let suffixes = ["th", "st", "nd", "rd"]
        var keywords = [
            "gen\(generation)",
            "gen \(generation)",
            "generation \(generation)",
            "\(generation)代",
            "第\(generation)代"
        ]
        for suffix in suffixes {
            keywords.append("\(generation)\(suffix) generation")
        }
        keywords.append(contentsOf: chineseNumerals.compactMap { numeral, value in
            value == generation ? numeral : nil
        })
        return keywords.contains { name.contains($0) }
    }

    private static func airPodsGeneration(in name: String) -> Int? {
        // Preserve the original precedence: explicit generation wording wins
        // over a contradictory marketing number in the same display name.
        if let explicitGeneration = (1...6).first(where: { generation in
            matchesGeneration(name, generation: generation)
        }) {
            return explicitGeneration
        }

        return (1...6).first { generation in
        let modelNumbers = [
            "airpods pro \(generation)",
            "airpods pro\(generation)",
            "airpods \(generation)",
            "airpods\(generation)"
        ]
            return modelNumbers.contains { name.contains($0) }
        }
    }

    private static let chineseNumerals: [(numeral: String, generation: Int)] = [
        ("第一代", 1),
        ("第二代", 2),
        ("第三代", 3),
        ("第四代", 4),
        ("一代", 1),
        ("二代", 2),
        ("三代", 3),
        ("四代", 4)
    ]
}
