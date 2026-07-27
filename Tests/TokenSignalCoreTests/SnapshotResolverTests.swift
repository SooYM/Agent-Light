import Testing
@testable import TokenSignalCore

@Test func runningWinsAndActiveTokensAreSummed() {
    let records = [
        AgentRecord(id: "a", phase: .preparing, tokens: 100, name: "A", activityTimestamp: 10),
        AgentRecord(id: "b", phase: .running, provider: .claude, tokens: 250, name: "B", activityTimestamp: 11),
        AgentRecord(id: "c", phase: .stopped, tokens: 900, name: "C", activityTimestamp: 9)
    ]
    let snapshot = SnapshotResolver.resolve(records)
    #expect(snapshot.phase == .running)
    #expect(snapshot.tokens == 350)
    #expect(snapshot.activeAgents == 2)
}

@Test func stoppedKeepsLatestFinalTotal() {
    let records = [
        AgentRecord(id: "old", phase: .stopped, tokens: 500, name: "Old", activityTimestamp: 10),
        AgentRecord(id: "new", phase: .stopped, tokens: 725, name: "New", activityTimestamp: 20)
    ]
    let snapshot = SnapshotResolver.resolve(records)
    #expect(snapshot.phase == .stopped)
    #expect(snapshot.tokens == 725)
    #expect(snapshot.detail == "New")
}

@Test func parsesSQLiteTSV() {
    let records = SnapshotResolver.parseTSV("Codex\tid-1\trunning\t1234\tAgent One\t42\n")
    #expect(records == [AgentRecord(
        id: "id-1",
        phase: .running,
        provider: .codex,
        tokens: 1234,
        name: "Agent One",
        activityTimestamp: 42
    )])
}

@Test func missingProviderUsageIsMarkedPartial() {
    let records = [
        AgentRecord(id: "a", phase: .running, provider: .codex, tokens: 100, name: "Codex", activityTimestamp: 1),
        AgentRecord(id: "b", phase: .running, provider: .antigravity, tokens: nil, name: "Antigravity", activityTimestamp: 2)
    ]
    let snapshot = SnapshotResolver.resolve(records)
    #expect(snapshot.tokens == 100)
    #expect(snapshot.tokenCoveragePartial)
}
