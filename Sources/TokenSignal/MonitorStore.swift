import AppKit
import Foundation
import TokenSignalCore

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var snapshot = MonitorSnapshot.empty
    @Published private(set) var errorMessage: String?
    @Published var lightOnly: Bool {
        didSet { UserDefaults.standard.set(lightOnly, forKey: "lightOnlyMode") }
    }

    private var timer: Timer?
    private var isRefreshing = false
    private let reader = LocalAgentReader()

    init() {
        lightOnly = UserDefaults.standard.bool(forKey: "lightOnlyMode")
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let records = await reader.read()
            snapshot = SnapshotResolver.resolve(records)
            errorMessage = records.isEmpty ? "No local agent data found" : nil
            isRefreshing = false
        }
    }
}

private actor LocalAgentReader {
    private let sqlite = "/usr/bin/sqlite3"
    private var antigravityFingerprint: Int?
    private var antigravityLastChange: Date?

    func read() -> [AgentRecord] {
        var records = (try? readCodex()) ?? []
        if let claude = readClaude() {
            records.append(claude)
        } else if isClaudeInstalled() {
            records.append(AgentRecord(
                id: "claude-installed",
                phase: .stopped,
                provider: .claude,
                tokens: nil,
                name: "Claude Code",
                activityTimestamp: 0
            ))
        }

        if let antigravity = readAntigravity() {
            records.append(antigravity)
        } else if isAntigravityInstalled() {
            records.append(AgentRecord(
                id: "antigravity-installed",
                phase: .stopped,
                provider: .antigravity,
                tokens: nil,
                name: "Antigravity",
                activityTimestamp: 0
            ))
        }

        if records.filter({ $0.provider == .codex }).isEmpty && isCodexInstalled() {
            records.append(AgentRecord(
                id: "codex-installed",
                phase: .stopped,
                provider: .codex,
                tokens: nil,
                name: "Codex",
                activityTimestamp: 0
            ))
        }

        return records
    }

    private func isCodexInstalled() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return FileManager.default.fileExists(atPath: "\(home)/.codex")
    }

    private func isClaudeInstalled() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return FileManager.default.fileExists(atPath: "\(home)/.claude") || commandSucceeds("/usr/bin/which", ["claude"])
    }

    private func isAntigravityInstalled() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return FileManager.default.fileExists(atPath: "\(home)/.gemini/antigravity")
            || FileManager.default.fileExists(atPath: "\(home)/Library/Application Support/Antigravity")
            || FileManager.default.fileExists(atPath: "\(home)/Library/Application Support/Antigravity IDE")
            || commandSucceeds("/usr/bin/pgrep", ["-f", "Antigravity( IDE)?\\.app"])
    }

    private func readCodex() throws -> [AgentRecord] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let logs = "\(home)/.codex/logs_2.sqlite"
        let state = "\(home)/.codex/state_5.sqlite"

        guard FileManager.default.fileExists(atPath: logs),
              FileManager.default.fileExists(atPath: state) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let query = """
        ATTACH DATABASE '\(state.replacingOccurrences(of: "'", with: "''"))' AS state;
        WITH turn_events AS (
          SELECT thread_id,
                 substr(feedback_log_body, instr(feedback_log_body, 'turn.id=') + 8, 36) AS turn_id,
                 min(ts) AS started_at,
                 max(ts) AS last_activity
          FROM logs
          WHERE thread_id IS NOT NULL
            AND ts >= strftime('%s','now') - 43200
            AND feedback_log_body LIKE '%turn.id=%'
          GROUP BY thread_id, turn_id
        ), ranked_turns AS (
          SELECT *, row_number() OVER (
            PARTITION BY thread_id ORDER BY last_activity DESC
          ) AS rank
          FROM turn_events
        ), usage_events AS (
          SELECT thread_id,
                 substr(feedback_log_body, instr(feedback_log_body, 'turn_id=') + 8, 36) AS turn_id,
                 feedback_log_body,
                 row_number() OVER (
                   PARTITION BY thread_id,
                     substr(feedback_log_body, instr(feedback_log_body, 'turn_id=') + 8, 36)
                   ORDER BY ts DESC, ts_nanos DESC, id DESC
                 ) AS rank
          FROM logs
          WHERE ts >= strftime('%s','now') - 43200
            AND feedback_log_body LIKE '%post sampling token usage turn_id=%'
        ), terminal_events AS (
          SELECT thread_id, max(ts) AS stopped_at
          FROM logs
          WHERE thread_id IS NOT NULL
            AND ts >= strftime('%s','now') - 43200
            AND (
              (target = 'codex_core::session' AND feedback_log_body LIKE '%interrupt received%')
              OR (target = 'codex_core::session::handlers' AND (
                feedback_log_body LIKE '%Shutting down Codex instance%'
                OR feedback_log_body LIKE '%Agent loop exited%'
              ))
            )
          GROUP BY thread_id
        )
        SELECT 'Codex',
               t.thread_id,
               CASE
                 WHEN x.stopped_at >= t.started_at THEN 'stopped'
                 WHEN strftime('%s','now') - t.last_activity > 30 THEN 'stopped'
                 WHEN u.feedback_log_body IS NULL
                      AND strftime('%s','now') - t.started_at <= 2 THEN 'preparing'
                 WHEN u.feedback_log_body LIKE '%needs_follow_up=true'
                      AND strftime('%s','now') - t.last_activity <= 30 THEN 'running'
                 ELSE 'stopped'
               END,
               coalesce(s.tokens_used, 0),
               substr(replace(replace(replace(
                 coalesce(nullif(s.agent_nickname, ''), nullif(s.title, ''), 'Codex Agent'),
                 char(9), ' '), char(10), ' '), char(13), ' '), 1, 80),
               t.last_activity
        FROM ranked_turns t
        LEFT JOIN usage_events u
          ON u.thread_id = t.thread_id AND u.turn_id = t.turn_id AND u.rank = 1
        LEFT JOIN state.threads s ON s.id = t.thread_id
        LEFT JOIN terminal_events x ON x.thread_id = t.thread_id
        WHERE t.rank = 1
        ORDER BY t.last_activity DESC
        LIMIT 200;
        """

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: sqlite)
        process.arguments = ["-tabs", "-noheader", logs, query]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "TokenSignal.SQLite",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "sqlite3 failed"]
            )
        }

        return SnapshotResolver.parseTSV(String(data: data, encoding: .utf8) ?? "")
    }

    private func readClaude() -> AgentRecord? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects", directoryHint: .isDirectory)
        guard let file = newestFile(in: root, extension: "jsonl"),
              let data = try? Data(contentsOf: file.url),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var usages: [String: Int] = [:]
        var lastType: String?
        var lastStopReason: String?
        var sessionID = file.url.deletingPathExtension().lastPathComponent

        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = object["type"] as? String else { continue }

            if let value = object["sessionId"] as? String { sessionID = value }
            if type == "user" {
                lastType = "user"
                lastStopReason = nil
            } else if type == "assistant", let message = object["message"] as? [String: Any] {
                lastType = "assistant"
                lastStopReason = message["stop_reason"] as? String
                if let id = message["id"] as? String,
                   let usage = message["usage"] as? [String: Any] {
                    usages[id] = [
                        "input_tokens", "cache_creation_input_tokens",
                        "cache_read_input_tokens", "output_tokens"
                    ].reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
                }
            }
        }

        let processRunning = commandSucceeds("/usr/bin/pgrep", ["-x", "claude"])
        let age = Date().timeIntervalSince(file.modified)
        let phase: AgentPhase
        if !processRunning || (lastType == "assistant" && lastStopReason == "end_turn") {
            phase = .stopped
        } else if lastType == "user" && age <= 2 {
            phase = .preparing
        } else {
            phase = .running
        }

        return AgentRecord(
            id: "claude-\(sessionID)",
            phase: phase,
            provider: .claude,
            tokens: usages.values.reduce(0, +),
            name: "Claude Code",
            activityTimestamp: file.modified.timeIntervalSince1970
        )
    }

    private func readAntigravity() -> AgentRecord? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [(url: URL, modified: Date)] = []

        let liveDir = home.appending(path: ".gemini/antigravity/conversations", directoryHint: .isDirectory)
        if let entries = try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for url in entries where url.pathExtension == "db" {
                if let dbMtime = modificationDate(url) {
                    let walUrl = url.deletingPathExtension().appendingPathExtension("db-wal")
                    let walMtime = modificationDate(walUrl) ?? .distantPast
                    let newestMtime = max(dbMtime, walMtime)
                    candidates.append((url, newestMtime))
                }
            }
        }

        let legacyPaths = ["Antigravity", "Antigravity IDE"].map {
            home.appending(path: "Library/Application Support/\($0)/User/globalStorage/state.vscdb")
        }
        for url in legacyPaths {
            if let mtime = modificationDate(url) {
                candidates.append((url, mtime))
            }
        }

        guard let database = candidates.max(by: { $0.1 < $1.1 }) else { return nil }

        let processRunning = commandSucceeds("/usr/bin/pgrep", ["-f", "Antigravity( IDE)?\\.app"])
        let isLive = database.url.pathExtension == "db" && database.url.path.contains(".gemini/antigravity/conversations")

        let fingerprint: Int
        let latestStatus: Int?
        let latestFinished: TimeInterval?

        if isLive {
            let stepInfo = run("/usr/bin/sqlite3", [
                "-noheader", database.url.path,
                "SELECT max(idx), (SELECT status FROM steps WHERE idx = (SELECT max(idx) FROM steps)) FROM steps;"
            ]) ?? ""
            let components = stepInfo.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
            let maxIdx = components.first.flatMap { Int($0) } ?? 0
            let status = components.count > 1 ? Int(components[1]) : nil
            latestStatus = status
            latestFinished = nil
            fingerprint = "\(database.url.path):\(maxIdx):\(status ?? -1)".hashValue
        } else {
            let value = run("/usr/bin/sqlite3", [
                "-noheader", database.url.path,
                "select value from ItemTable where key='antigravityUnifiedStateSync.trajectorySummaries';"
            ]) ?? ""
            latestStatus = nil
            latestFinished = run("/usr/bin/sqlite3", [
                "-noheader", database.url.path,
                "select max(cast(substr(key, length(key) - 12) as integer)) / 1000.0 from ItemTable where key like 'antigravity.notification.agent-finished-%';"
            ]).flatMap { TimeInterval($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            fingerprint = value.hashValue
        }

        let dbMtime = database.modified
        let dbMtimeAge = Date().timeIntervalSince(dbMtime)

        if let old = antigravityFingerprint {
            if old != fingerprint {
                antigravityLastChange = Date()
            }
        } else {
            if dbMtimeAge <= 30 {
                antigravityLastChange = dbMtime
            }
        }
        antigravityFingerprint = fingerprint

        let changeAge = antigravityLastChange.map { Date().timeIntervalSince($0) }
        let finishedRecently = latestFinished.map { Date().timeIntervalSince1970 - $0 < 3 } ?? false

        let phase: AgentPhase
        if !processRunning || finishedRecently {
            phase = .stopped
        } else if isLive, let status = latestStatus, status == 2 {
            if changeAge != nil && changeAge! <= 2 {
                phase = .preparing
            } else {
                phase = .running
            }
        } else {
            if changeAge == nil || changeAge! > 30 || dbMtimeAge > 30 {
                phase = .stopped
            } else if changeAge! <= 2 {
                phase = .preparing
            } else {
                phase = .running
            }
        }

        return AgentRecord(
            id: "antigravity-local",
            phase: phase,
            provider: .antigravity,
            tokens: nil,
            name: "Antigravity",
            activityTimestamp: (antigravityLastChange ?? dbMtime).timeIntervalSince1970
        )
    }

    private func newestFile(in root: URL, extension wanted: String) -> (url: URL, modified: Date)? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (URL, Date)?
        for case let url as URL in enumerator where url.pathExtension == wanted {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate else { continue }
            if newest == nil || modified > newest!.1 { newest = (url, modified) }
        }
        return newest
    }

    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func commandSucceeds(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
