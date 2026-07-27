import Foundation

public enum AgentPhase: String, Sendable {
    case stopped
    case preparing
    case running
}

public enum AgentProvider: String, CaseIterable, Sendable {
    case codex = "Codex"
    case claude = "Claude Code"
    case antigravity = "Antigravity"
}

public struct AgentRecord: Equatable, Sendable {
    public let id: String
    public let phase: AgentPhase
    public let provider: AgentProvider
    public let tokens: Int?
    public let name: String
    public let activityTimestamp: TimeInterval

    public init(
        id: String,
        phase: AgentPhase,
        provider: AgentProvider = .codex,
        tokens: Int?,
        name: String,
        activityTimestamp: TimeInterval
    ) {
        self.id = id
        self.phase = phase
        self.provider = provider
        self.tokens = tokens
        self.name = name
        self.activityTimestamp = activityTimestamp
    }
}

public struct MonitorSnapshot: Equatable, Sendable {
    public let phase: AgentPhase
    public let tokens: Int?
    public let activeAgents: Int
    public let detail: String
    public let providers: [AgentProvider]
    public let tokenCoveragePartial: Bool
    public let lastActivity: TimeInterval?

    public static let empty = MonitorSnapshot(
        phase: .stopped,
        tokens: 0,
        activeAgents: 0,
        detail: "No recent task",
        providers: [],
        tokenCoveragePartial: false,
        lastActivity: nil
    )
}

public enum SnapshotResolver {
    public static func resolve(_ records: [AgentRecord]) -> MonitorSnapshot {
        guard let latest = records.max(by: { $0.activityTimestamp < $1.activityTimestamp }) else {
            return .empty
        }

        let running = records.filter { $0.phase == .running }
        let preparing = records.filter { $0.phase == .preparing }
        let active = running + preparing
        let phase: AgentPhase = !running.isEmpty ? .running : (!preparing.isEmpty ? .preparing : .stopped)
        let relevant = active.isEmpty ? [latest] : active
        let knownTokens = relevant.compactMap(\.tokens)
        let providers = Array(Set(relevant.map(\.provider))).sorted { $0.rawValue < $1.rawValue }
        let detail: String

        if active.count > 1 {
            detail = "\(active.count) agents active"
        } else if let agent = active.first {
            detail = agent.name
        } else {
            detail = latest.name
        }

        return MonitorSnapshot(
            phase: phase,
            tokens: knownTokens.isEmpty ? nil : knownTokens.reduce(0, +),
            activeAgents: active.count,
            detail: detail,
            providers: providers,
            tokenCoveragePartial: knownTokens.count != relevant.count,
            lastActivity: latest.activityTimestamp
        )
    }

    public static func parseTSV(_ text: String) -> [AgentRecord] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6,
                  let provider = AgentProvider(rawValue: fields[0]),
                  let phase = AgentPhase(rawValue: fields[2]),
                  let timestamp = TimeInterval(fields[5]) else { return nil }
            return AgentRecord(
                id: fields[1],
                phase: phase,
                provider: provider,
                tokens: Int(fields[3]),
                name: fields[4].isEmpty ? provider.rawValue : fields[4],
                activityTimestamp: timestamp
            )
        }
    }
}
