import SwiftUI
import TokenSignalCore

struct MonitorView: View {
    @ObservedObject var store: MonitorStore

    private var phase: AgentPhase { store.snapshot.phase }

    var body: some View {
        HStack(spacing: 0) {
            signalColumn
                .frame(width: 104)

            if !store.lightOnly {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)

                telemetry
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(width: store.lightOnly ? 104 : 370, height: 196)
        .background(Color(red: 0.055, green: 0.059, blue: 0.064))
        .overlay(alignment: .top) {
            Rectangle().fill(activeColor).frame(height: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var signalColumn: some View {
        VStack(spacing: 15) {
            signal(.stopped, color: .signalRed, label: "Stopped")
            signal(.preparing, color: .signalOrange, label: "Preparing")
            signal(.running, color: .signalGreen, label: "Running")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.18))
    }

    private func signal(_ target: AgentPhase, color: Color, label: String) -> some View {
        let active = phase == target
        return ZStack {
            Circle()
                .fill(active ? color : color.opacity(0.10))
                .overlay(Circle().stroke(Color.white.opacity(active ? 0.28 : 0.08), lineWidth: 1))
                .shadow(color: active ? color.opacity(0.48) : .clear, radius: 10, y: 2)
            Circle()
                .fill(Color.white.opacity(active ? 0.20 : 0.03))
                .frame(width: 13, height: 7)
                .blur(radius: 2)
                .offset(x: -7, y: -8)
        }
        .frame(width: 40, height: 40)
        .animation(.easeOut(duration: 0.28), value: phase)
        .accessibilityLabel(label)
        .accessibilityValue(active ? "On" : "Off")
    }

    private var telemetry: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(activeColor).frame(width: 7, height: 7)
                Text(statusText.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(activeColor)
            }

            Spacer(minLength: 13)

            Text(formattedTokens)
                .font(.system(size: 42, weight: .medium, design: .monospaced))
                .tracking(-1.4)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.22), value: store.snapshot.tokens)

            Text(store.snapshot.tokenCoveragePartial ? "TOKENS / REPORTED" : "TOKENS")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.top, 3)

            Spacer(minLength: 14)

            HStack {
                Text(store.errorMessage ?? providerText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(agentCountText)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.58))
        }
        .padding(.vertical, 20)
    }

    private var statusText: String {
        switch phase {
        case .stopped: "Stopped"
        case .preparing: "Preparing"
        case .running: "Running"
        }
    }

    private var activeColor: Color {
        switch phase {
        case .stopped: .signalRed
        case .preparing: .signalOrange
        case .running: .signalGreen
        }
    }

    private var formattedTokens: String {
        store.snapshot.tokens?.formatted(.number.grouping(.automatic)) ?? "—"
    }

    private var accessibilitySummary: String {
        store.lightOnly
            ? "Agent status \(statusText)"
            : "Agent status \(statusText), \(formattedTokens) tokens"
    }

    private var providerText: String {
        let names = store.snapshot.providers.map(\.rawValue)
        return names.isEmpty ? store.snapshot.detail : names.joined(separator: " + ")
    }

    private var agentCountText: String {
        let count = store.snapshot.activeAgents
        return count == 1 ? "1 AGENT" : "\(count) AGENTS"
    }
}

private extension Color {
    static let signalRed = Color(red: 1.00, green: 0.25, blue: 0.29)
    static let signalOrange = Color(red: 1.00, green: 0.57, blue: 0.16)
    static let signalGreen = Color(red: 0.20, green: 0.86, blue: 0.46)
}
