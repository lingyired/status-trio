import Foundation

/// Applies a development test profile at launch, between settings migration and
/// UI/monitoring startup. It validates everything before mutating, never applies
/// partially, and reports a human-readable development log.
@MainActor
enum DevelopmentProfileBootstrap {
    enum Outcome {
        case noProfile
        case applied
        case rejected([DevelopmentProfileIssue])
        case skipped(SettingsProfileApplyMode)
        case failed([SettingsPlanIssue])
        case loadFailed(String)
    }

    struct RunResult {
        let outcome: Outcome
        let applyResult: SettingsApplyResult?
        let log: [String]

        var applied: Bool {
            if case .applied = outcome { return true }
            return false
        }
    }

    static func run(profileURL: URL?, service: SettingsService) -> RunResult {
        guard let url = profileURL else {
            return RunResult(outcome: .noProfile, applyResult: nil, log: ["没有开发 Profile，保持现有启动行为"])
        }

        let profile: DevelopmentTestProfile
        do {
            profile = try DevelopmentProfileLoader.load(from: url)
        } catch {
            return RunResult(outcome: .loadFailed("\(error)"), applyResult: nil, log: ["读取 Profile 失败：\(error)"])
        }

        let issues = DevelopmentProfileValidator.validate(profile, against: service.registry)
        guard issues.isEmpty else {
            return RunResult(
                outcome: .rejected(issues),
                applyResult: nil,
                log: ["Profile 校验失败，未做任何修改："] + issues.map(\.description)
            )
        }

        guard profile.applyMode == .onLaunch else {
            return RunResult(
                outcome: .skipped(profile.applyMode),
                applyResult: nil,
                log: ["applyMode=\(profile.applyMode.rawValue) 暂不自动应用（仅实现 onLaunch）"]
            )
        }

        let plan = service.preview(
            features: profile.features,
            preferences: profile.preferences,
            mutations: profile.mutations
        )
        guard plan.isApplicable else {
            return RunResult(
                outcome: .failed(plan.errors),
                applyResult: nil,
                log: ["Profile 变更计划非法，未做任何修改："] + plan.errors.map(\.description)
            )
        }

        do {
            let result = try service.apply(plan)
            var log = ["已应用开发 Profile：\(url.lastPathComponent)"]
            if result.plan.operations.isEmpty {
                log.append("  （无变更，当前状态已满足）")
            } else {
                log.append(contentsOf: result.plan.operations.map {
                    "  \($0.preferenceID) = \(describe($0.value)) [\($0.source.rawValue)]"
                })
            }
            return RunResult(outcome: .applied, applyResult: result, log: log)
        } catch {
            return RunResult(outcome: .loadFailed("\(error)"), applyResult: nil, log: ["应用失败：\(error)"])
        }
    }

    static func runAtLaunch(
        service: SettingsService,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> RunResult {
        run(profileURL: DevelopmentProfileLoader.locate(environment: environment, bundle: bundle), service: service)
    }

    private static func describe(_ value: SettingsTransferValue?) -> String {
        guard let value else { return "nil" }
        switch value {
        case .null: return "null"
        case .bool(let flag): return "\(flag)"
        case .number(let number): return "\(number)"
        case .string(let string): return "\"\(string)\""
        case .array(let items): return "[\(items.count) items]"
        case .object: return "{object}"
        }
    }
}
