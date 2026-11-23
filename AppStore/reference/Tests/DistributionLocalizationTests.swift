import Foundation
import Testing
@testable import StatusTrioCore

struct DistributionLocalizationTests {
    private static let copyKeys: [LocalizationKey] = [
        .settingsDistributionTitle,
        .settingsDistributionDescription,
        .settingsDistributionProject,
        .settingsDistributionIndependentSettings,
        .settingsUpdatesSystemManaged,
        .capabilityUnavailableDistribution,
        .capabilityNotVerified
    ]

    private static let expectedEnglishCopy: [String: String] = [
        "settings.distribution.title": "Distribution",
        "settings.distribution.description": "Status Trio is an open-source macOS utility. System control availability may vary by distribution channel and macOS permissions.",
        "settings.distribution.project": "Open-source project and release notes",
        "settings.distribution.independentSettings": "Each distribution keeps its own settings and permissions.",
        "settings.updates.systemManaged": "Updates are managed by the Mac App Store.",
        "capability.unavailableDistribution": "This control is unavailable in this distribution.",
        "capability.notVerified": "Availability on this Mac has not been verified."
    ]

    private static let expectedDistributionDescriptions: [AppLanguage: String] = [
        .english: "Status Trio is an open-source macOS utility. System control availability may vary by distribution channel and macOS permissions.",
        .arabic: "‏Status Trio أداة macOS مفتوحة المصدر. قد يختلف توفر عناصر التحكم في النظام حسب قناة التوزيع وأذونات macOS.",
        .german: "Status Trio ist ein Open-Source-Dienstprogramm für macOS. Die Verfügbarkeit von Systemsteuerungen kann je nach Vertriebskanal und macOS-Berechtigungen variieren.",
        .spanish: "Status Trio es una utilidad de macOS de código abierto. La disponibilidad de los controles del sistema puede variar según el canal de distribución y los permisos de macOS.",
        .french: "Status Trio est un utilitaire macOS open source. La disponibilité des contrôles système peut varier selon le canal de distribution et les autorisations macOS.",
        .italian: "Status Trio è un’utility macOS open source. La disponibilità dei controlli di sistema può variare in base al canale di distribuzione e alle autorizzazioni di macOS.",
        .japanese: "Status Trio はオープンソースの macOS ユーティリティです。システム操作の利用可否は、配布チャネルや macOS の権限によって異なる場合があります。",
        .korean: "Status Trio는 오픈 소스 macOS 유틸리티입니다. 시스템 제어 기능의 사용 가능 여부는 배포 채널과 macOS 권한에 따라 달라질 수 있습니다.",
        .brazilianPortuguese: "O Status Trio é um utilitário macOS de código aberto. A disponibilidade dos controles do sistema pode variar conforme o canal de distribuição e as permissões do macOS.",
        .russian: "Status Trio — утилита macOS с открытым исходным кодом. Доступность системных элементов управления может зависеть от канала распространения и разрешений macOS.",
        .simplifiedChinese: "Status Trio 是开源 macOS 工具。系统控制能力可能因发行渠道和 macOS 权限而有所不同。",
        .traditionalChinese: "Status Trio 是開源 macOS 工具。系統控制能力可能因發行管道和 macOS 權限而有所不同。"
    ]

    private static let forbiddenCopyPatterns = [
        #"(?i)\b(?:buy|purchase|paid|upgrade|unlock|full version)\b"#,
        #"(?i)\b(?:download|install) (?:the )?(?:direct|github) (?:version|build)\b"#,
        #"(?i)\b(?:published|available) on the mac app store\b"#,
        #"(?i)\b(?:approved|reviewed) by apple\b"#,
        #"(?i)\b(?:app store|apple) approved\b"#,
        #"(?i)\b(?:subscribe|subscription|free trial)\b"#,
        #"(?i)\b(?:app store connect|testflight)\b"#
    ]

    private static let localizedForbiddenCopyPatterns: [AppLanguage: [String]] = [
        .arabic: [
            #"(?:شراء|اشتر|مدفوع|ترقية|فتح|النسخة الكاملة|اشتراك|تجربة مجانية)"#,
            #"(?:متوفر|متاحة|يُوز|توزع).{0,24}Mac App Store"#,
            #"(?:تم النشر|تمت الموافقة|موافقة Apple)"#
        ],
        .german: [
            #"(?i)(?:kaufen|kaufe|kauf|kostenpflichtig|bezahlt|upgrade|freischalten|vollversion|abonnieren|abonnement|kostenlose testversion)"#,
            #"(?i)(?:im mac app store (?:verfügbar|erhältlich)|(?:verfügbar|erhältlich) im mac app store)"#
        ],
        .spanish: [
            #"(?i)(?:comprar|compra|de pago|pago único|mejorar|desbloquear|versión completa|suscribirse|suscripción|prueba gratuita)"#,
            #"(?i)(?:disponible|publicad[oa]) en (?:el )?mac app store"#
        ],
        .french: [
            #"(?i)(?:achet(?:er|ez|e|ons)|achat|payant|mise à niveau|débloquer|version complète|s.abonner|abonnement|essai gratuit)"#,
            #"(?i)(?:disponible|publiée?) sur (?:le )?mac app store"#
        ],
        .italian: [
            #"(?i)(?:acquist(?:are|o|a|i|ano)|a pagamento|passare alla versione|sbloccare|versione completa|abbonarsi|abbonamento|prova gratuita)"#,
            #"(?i)(?:disponibile|pubblicat[oa]) (?:sul|nel) mac app store"#
        ],
        .japanese: [
            #"(?:購入|有料|アップグレード|ロック解除|完全版|フルバージョン|サブスクリプション|定期購読|無料トライアル)"#,
            #"(?:Mac App Store (?:で|から).{0,12}(?:配信中|配布中|入手可能|ダウンロード可能)|Appleの承認)"#
        ],
        .korean: [
            #"(?:구매|유료|업그레이드|잠금 해제|전체 버전|정식 버전|구독|무료 체험)"#,
            #"(?:Mac App Store에서.{0,12}(?:제공|배포|다운로드 가능)|Apple의 승인)"#
        ],
        .brazilianPortuguese: [
            #"(?i)(?:compr(?:ar|a|e|o|em)|pago|paga|desbloquear|versão completa|assinar|assinatura|teste grátis|teste gratuito)"#,
            #"(?i)(?:disponível|publicad[oa]) (?:na|no) mac app store"#
        ],
        .russian: [
            #"(?i)(?:куп(?:ить|ите|лю|ка|ит)|платн|разблокировать|полная версия|подписаться|подписка|бесплатная пробная версия)"#,
            #"(?i)(?:доступн|опубликован).{0,16}mac app store"#
        ],
        .simplifiedChinese: [
            #"(?:购买|付费|升级|解锁|完整版|订阅|免费试用)"#,
            #"(?:Mac App Store.{0,12}(?:已上架|已发布|可供下载|可下载)|Apple.{0,8}(?:已批准|已审核))"#
        ],
        .traditionalChinese: [
            #"(?:購買|付費|升級|解鎖|完整版|訂閱|免費試用)"#,
            #"(?:Mac App Store.{0,12}(?:已上架|已發佈|可供下載|可下載)|Apple.{0,8}(?:已批准|已審核))"#
        ]
    ]

    private static let representativeLocalizedClaims: [AppLanguage: String] = [
        .english: "Buy the full version.",
        .arabic: "اشترِ النسخة الكاملة.",
        .german: "Kaufe die Vollversion.",
        .spanish: "Compra la versión completa.",
        .french: "Achetez la version complète.",
        .italian: "Acquista la versione completa.",
        .japanese: "完全版を購入してください。",
        .korean: "전체 버전을 구매하세요.",
        .brazilianPortuguese: "Compre a versão completa.",
        .russian: "Купите полную версию.",
        .simplifiedChinese: "购买完整版。",
        .traditionalChinese: "購買完整版。"
    ]

    @Test func everyDistributionCopyKeyExistsInEveryLanguage() throws {
        let expectedKeys = Set(Self.copyKeys.map(\.rawValue))
        let declaredKeys = Set(
            LocalizationKey.allCases.map(\.rawValue).filter {
                $0.hasPrefix("settings.distribution.")
                    || $0 == "settings.updates.systemManaged"
                    || [
                        "capability.unavailableDistribution",
                        "capability.notVerified"
                    ].contains($0)
            }
        )
        #expect(
            declaredKeys == expectedKeys,
            "distribution/capability key declarations drifted: \(declaredKeys.symmetricDifference(expectedKeys))"
        )

        for language in AppLanguage.allCases {
            let entries = try LocalizedCatalog(language: language)
            for key in expectedKeys {
                let value = try entries.value(for: key)
                #expect(
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(language.rawValue): \(key) is empty"
                )
                #expect(value != key, "\(language.rawValue): \(key) is a raw key")
            }
        }
    }

    @Test func distributionCopyHasNoUnpublishedOrPaidClaims() throws {
        for language in AppLanguage.allCases {
            let entries = try LocalizedCatalog(language: language)
            for key in Self.copyKeys.map(\.rawValue) {
                let value = try entries.value(for: key)
                #expect(
                    !Self.containsForbiddenClaim(value, language: language),
                    "\(language.rawValue): \(key) contains a forbidden distribution claim: \(value)"
                )
            }
        }
    }

    @Test func distributionDescriptionsStayDistributionNeutral() throws {
        #expect(
            Self.expectedDistributionDescriptions.count == AppLanguage.allCases.count,
            "every AppLanguage must have a reviewed distribution description"
        )
        for language in AppLanguage.allCases {
            let entries = try LocalizedCatalog(language: language)
            let actual = try entries.value(for: "settings.distribution.description")
            let expected = Self.expectedDistributionDescriptions[language]
            #expect(expected != nil, "\(language.rawValue): reviewed description missing")
            if let expected {
                #expect(
                    actual == expected,
                    "\(language.rawValue): distribution description changed; review all 12 translations and claim fixtures together"
                )
            }
        }
    }

    @Test func localizedClaimGuardRejectsRepresentativePaidOrCtaPhrases() {
        #expect(
            Self.representativeLocalizedClaims.count == AppLanguage.allCases.count,
            "every AppLanguage must have a negative claim fixture"
        )
        for language in AppLanguage.allCases {
            let claim = Self.representativeLocalizedClaims[language]
            #expect(claim != nil, "\(language.rawValue): representative claim fixture missing")
            if let claim {
                #expect(
                    Self.containsForbiddenClaim(claim, language: language),
                    "\(language.rawValue): localized claim guard missed \(claim)"
                )
            }
        }
    }

    @Test func englishCopyKeepsTheReviewableContract() throws {
        let entries = try LocalizedCatalog(language: .english)
        for (key, expected) in Self.expectedEnglishCopy {
            let actual = try entries.value(for: key)
            #expect(
                actual == expected,
                "en: \(key) changed; update the review copy and all 12 translations together"
            )
        }
    }

    private static func containsForbiddenClaim(
        _ value: String,
        language: AppLanguage
    ) -> Bool {
        let patterns = forbiddenCopyPatterns
            + (localizedForbiddenCopyPatterns[language] ?? [])
        return patterns.contains {
            value.range(of: $0, options: .regularExpression) != nil
        }
    }

    @Test func storePrivacyManifestIsMinimalAndConsistent() throws {
        let manifest = try PrivacyManifest(url: Self.privacyManifestURL)
        try manifest.validated()

        #expect(manifest.tracking == false)
        #expect(manifest.trackingDomains.isEmpty)
        #expect(manifest.collectedDataTypes.isEmpty)
        #expect(
            manifest.reasonsByCategory == [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
                "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"]
            ]
        )
    }

    @Test func privacyManifestRejectsTrackingAndCollectedData() throws {
        var fixture = try PrivacyManifestFixture.minimal()
        fixture.tracking = true
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }

        fixture = try .minimal()
        fixture.trackingDomains = ["https://tracking.example"]
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }

        fixture = try .minimal()
        fixture.collectedDataTypes = [["NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeDeviceID"]]
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }
    }

    @Test func privacyManifestRejectsMissingOrUnexpectedReasons() throws {
        var fixture = try PrivacyManifestFixture.minimal()
        fixture.reasonsByCategory.removeValue(forKey: "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }

        fixture = try .minimal()
        fixture.reasonsByCategory["NSPrivacyAccessedAPICategoryUserDefaults"] = []
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }

        fixture = try .minimal()
        fixture.reasonsByCategory["NSPrivacyAccessedAPICategoryUserDefaults"] = ["CA92.1", "1C8F.1"]
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }

        fixture = try .minimal()
        fixture.reasonsByCategory["NSPrivacyAccessedAPICategorySystemBootTime"] = ["8FFB.1"]
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }

        fixture = try .minimal()
        fixture.reasonsByCategory["NSPrivacyAccessedAPICategoryDiskSpace"] = ["E174.1"]
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }
    }

    @Test func privacyManifestRejectsUnknownOrMalformedCategories() throws {
        var fixture = try PrivacyManifestFixture.minimal()
        fixture.reasonsByCategory["NSPrivacyAccessedAPICategoryMadeUp"] = ["CA92.1"]
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }

        fixture = try .minimal()
        fixture.extraTopLevelKeys = ["NSPrivacyUnknown"]
        #expect(throws: PrivacyManifestError.self) {
            try fixture.validated()
        }
    }

    fileprivate static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var privacyManifestURL: URL {
        repositoryRoot.appendingPathComponent("AppStore/PrivacyInfo.xcprivacy")
    }
}

private struct LocalizedCatalog {
    private let values: [String: String]
    let language: AppLanguage

    init(language: AppLanguage) throws {
        self.language = language
        let url = DistributionLocalizationTests.repositoryRoot
            .appendingPathComponent("Sources/StatusTrioCore/Resources")
            .appendingPathComponent("\(language.rawValue).lproj")
            .appendingPathComponent("Localizable.strings")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw LocalizationFixtureError.unreadable(url)
        }

        var parsed: [String: String] = [:]
        let pattern = /^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$/
        for (index, rawLine) in contents.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("/*") || line.hasPrefix("*") || line.hasPrefix("//") {
                continue
            }
            guard let match = line.wholeMatch(of: pattern) else {
                throw LocalizationFixtureError.unparsableLine(
                    language: language.rawValue,
                    line: index + 1
                )
            }
            let key = String(match.output.1)
            guard parsed.updateValue(String(match.output.2), forKey: key) == nil else {
                throw LocalizationFixtureError.duplicatedKey(
                    language: language.rawValue,
                    key: key
                )
            }
        }
        values = parsed
    }

    func value(for key: String) throws -> String {
        guard let value = values[key] else {
            throw LocalizationFixtureError.missingKey(language: language.rawValue, key: key)
        }
        return value
    }
}

private enum LocalizationFixtureError: Error, CustomStringConvertible {
    case unreadable(URL)
    case unparsableLine(language: String, line: Int)
    case duplicatedKey(language: String, key: String)
    case missingKey(language: String, key: String)

    var description: String {
        switch self {
        case .unreadable(let url):
            "cannot read \(url.path)"
        case .unparsableLine(let language, let line):
            "\(language).lproj line \(line) is not a key/value pair"
        case .duplicatedKey(let language, let key):
            "\(language).lproj declares \(key) more than once"
        case .missingKey(let language, let key):
            "\(language).lproj is missing \(key)"
        }
    }
}

private struct PrivacyManifest {
    static let allowedTopLevelKeys: Set<String> = [
        "NSPrivacyTracking",
        "NSPrivacyTrackingDomains",
        "NSPrivacyCollectedDataTypes",
        "NSPrivacyAccessedAPITypes"
    ]

    static let expectedReasons: [String: Set<String>] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"]
    ]

    let tracking: Bool
    let trackingDomains: [Any]
    let collectedDataTypes: [Any]
    let reasonsByCategory: [String: Set<String>]
    let extraTopLevelKeys: Set<String>

    init(url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PrivacyManifestError.unreadable(url)
        }
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw PrivacyManifestError.invalidPlist
        }
        guard let root = plist as? [String: Any] else {
            throw PrivacyManifestError.rootMustBeDictionary
        }

        guard let tracking = root["NSPrivacyTracking"] as? Bool else {
            throw PrivacyManifestError.missingTracking
        }
        guard let trackingDomains = root["NSPrivacyTrackingDomains"] as? [Any] else {
            throw PrivacyManifestError.invalidTrackingDomains
        }
        guard let collectedDataTypes = root["NSPrivacyCollectedDataTypes"] as? [Any] else {
            throw PrivacyManifestError.invalidCollectedDataTypes
        }
        guard let accessTypes = root["NSPrivacyAccessedAPITypes"] as? [Any] else {
            throw PrivacyManifestError.invalidAccessTypes
        }

        var parsedReasons: [String: Set<String>] = [:]
        for entry in accessTypes {
            guard let entry = entry as? [String: Any],
                  let category = entry["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [Any] else {
                throw PrivacyManifestError.invalidAccessTypeEntry
            }
            guard parsedReasons[category] == nil else {
                throw PrivacyManifestError.duplicateCategory(category)
            }
            let strings = try reasons.map { reason -> String in
                guard let reason = reason as? String else {
                    throw PrivacyManifestError.nonStringReason(category)
                }
                return reason
            }
            parsedReasons[category] = Set(strings)
        }

        self.tracking = tracking
        self.trackingDomains = trackingDomains
        self.collectedDataTypes = collectedDataTypes
        self.reasonsByCategory = parsedReasons
        self.extraTopLevelKeys = Set(root.keys).subtracting(Self.allowedTopLevelKeys)
    }

    func validated() throws {
        guard tracking == false else {
            throw PrivacyManifestError.trackingMustBeFalse
        }
        guard trackingDomains.isEmpty else {
            throw PrivacyManifestError.trackingDomainsMustBeEmpty
        }
        guard collectedDataTypes.isEmpty else {
            throw PrivacyManifestError.collectedDataTypesMustBeEmpty
        }
        guard extraTopLevelKeys.isEmpty else {
            throw PrivacyManifestError.unexpectedTopLevelKeys(extraTopLevelKeys.sorted())
        }
        guard reasonsByCategory == Self.expectedReasons else {
            throw PrivacyManifestError.unexpectedReasons(reasonsByCategory)
        }
    }
}

private struct PrivacyManifestFixture {
    var tracking = false
    var trackingDomains: [Any] = []
    var collectedDataTypes: [Any] = []
    var reasonsByCategory: [String: Set<String>] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"]
    ]
    var extraTopLevelKeys: Set<String> = []

    static func minimal() throws -> PrivacyManifestFixture {
        .init()
    }

    func validated() throws {
        guard tracking == false else {
            throw PrivacyManifestError.trackingMustBeFalse
        }
        guard trackingDomains.isEmpty else {
            throw PrivacyManifestError.trackingDomainsMustBeEmpty
        }
        guard collectedDataTypes.isEmpty else {
            throw PrivacyManifestError.collectedDataTypesMustBeEmpty
        }
        guard extraTopLevelKeys.isEmpty else {
            throw PrivacyManifestError.unexpectedTopLevelKeys(extraTopLevelKeys.sorted())
        }
        guard reasonsByCategory == PrivacyManifest.expectedReasons else {
            throw PrivacyManifestError.unexpectedReasons(reasonsByCategory)
        }
    }
}

private enum PrivacyManifestError: Error, CustomStringConvertible {
    case unreadable(URL)
    case invalidPlist
    case rootMustBeDictionary
    case missingTracking
    case invalidTrackingDomains
    case invalidCollectedDataTypes
    case invalidAccessTypes
    case invalidAccessTypeEntry
    case duplicateCategory(String)
    case nonStringReason(String)
    case trackingMustBeFalse
    case trackingDomainsMustBeEmpty
    case collectedDataTypesMustBeEmpty
    case unexpectedTopLevelKeys([String])
    case unexpectedReasons([String: Set<String>])

    var description: String {
        switch self {
        case .unreadable(let url):
            "cannot read privacy manifest at \(url.path)"
        case .invalidPlist:
            "privacy manifest is not a valid property list"
        case .rootMustBeDictionary:
            "privacy manifest root must be a dictionary"
        case .missingTracking:
            "NSPrivacyTracking must be a Boolean"
        case .invalidTrackingDomains:
            "NSPrivacyTrackingDomains must be an array"
        case .invalidCollectedDataTypes:
            "NSPrivacyCollectedDataTypes must be an array"
        case .invalidAccessTypes:
            "NSPrivacyAccessedAPITypes must be an array"
        case .invalidAccessTypeEntry:
            "each accessed API entry must have a category and reasons array"
        case .duplicateCategory(let category):
            "privacy manifest declares \(category) more than once"
        case .nonStringReason(let category):
            "\(category) contains a non-string reason"
        case .trackingMustBeFalse:
            "NSPrivacyTracking must be false for the Store candidate"
        case .trackingDomainsMustBeEmpty:
            "NSPrivacyTrackingDomains must be empty when tracking is disabled"
        case .collectedDataTypesMustBeEmpty:
            "NSPrivacyCollectedDataTypes must be empty while Store telemetry is ineligible"
        case .unexpectedTopLevelKeys(let keys):
            "privacy manifest has unexpected top-level keys \(keys)"
        case .unexpectedReasons(let reasons):
            "privacy manifest reasons do not match the reviewed mapping: \(reasons)"
        }
    }
}
