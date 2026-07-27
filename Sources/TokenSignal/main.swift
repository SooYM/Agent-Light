import AppKit
import Combine
import SwiftUI
import TokenSignalCore

/*
 THESIS: One physical signal answers “is Codex working?”; no dashboard grid.
 OWN-WORLD: Near-black instrument face, three true signal lamps, white telemetry, state color only.
 STORY: Glance at phase, read live tokens, confirm active agent count, return to work.
 FIRST VIEWPORT: Vertical lamps occupy left rail; status and large token total fill right field.
 FORM: Native floating utility panel, traffic-light staging pinned by user brief.
*/

@MainActor
final class TokenSignalApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = MonitorStore()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var statusLabelItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var lightOnlyItem: NSMenuItem!
    private var snapshotSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildStatusItem()
        observeStatus()
        store.start()
        showPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showPanel() }
        return true
    }

    private func buildPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 196),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Token Signal"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = NSColor(red: 0.055, green: 0.059, blue: 0.064, alpha: 1)
        panel.contentView = NSHostingView(rootView: MonitorView(store: store))
        panel.center()
        panel.setFrameAutosaveName("TokenSignalPanel")
        applyPanelMode(animated: false)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self
        statusLabelItem = NSMenuItem(title: "Status: Stopped", action: nil, keyEquivalent: "")
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)
        menu.addItem(.separator())
        toggleItem = NSMenuItem(title: "Hide Token Signal", action: #selector(togglePanel), keyEquivalent: "s")
        toggleItem.target = self
        menu.addItem(toggleItem)
        lightOnlyItem = NSMenuItem(title: "Light Only Mode", action: #selector(toggleLightOnly), keyEquivalent: "l")
        lightOnlyItem.target = self
        menu.addItem(lightOnlyItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func observeStatus() {
        snapshotSubscription = store.$snapshot
            .map(\.phase)
            .removeDuplicates()
            .sink { [weak self] phase in self?.updateStatusItem(for: phase) }
    }

    private func updateStatusItem(for phase: AgentPhase) {
        let status = phase.label
        statusItem.button?.image = statusImage(color: phase.menuBarColor)
        statusItem.button?.toolTip = "Token Signal — \(status)"
        statusItem.button?.setAccessibilityLabel("Token Signal, \(status)")
    }

    private func statusImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let lamp = NSRect(x: 4, y: 4, width: 10, height: 10)
            NSColor.black.withAlphaComponent(0.45).setStroke()
            color.setFill()
            let path = NSBezierPath(ovalIn: lamp)
            path.lineWidth = 2
            path.fill()
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusTitle = "Status: \(store.snapshot.phase.label)"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        let agentsHeader = NSMenuItem(title: "Detected Agents:", action: nil, keyEquivalent: "")
        agentsHeader.isEnabled = false
        menu.addItem(agentsHeader)

        let allAgents = store.snapshot.allAgents
        if allAgents.isEmpty {
            let emptyItem = NSMenuItem(title: "  No local agents found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for agent in allAgents {
                let tokenText = agent.tokens.map { " (\($0.formatted(.number.grouping(.automatic))) tokens)" } ?? ""
                let title = "  \(agent.phase.symbol) \(agent.name): \(agent.phase.label)\(tokenText)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        toggleItem.title = panel.isVisible ? "Hide Token Signal" : "Show Token Signal"
        menu.addItem(toggleItem)

        lightOnlyItem.state = store.lightOnly ? .on : .off
        menu.addItem(lightOnlyItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Token Signal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func togglePanel() {
        panel.isVisible ? panel.orderOut(nil) : showPanel()
    }

    @objc private func toggleLightOnly() {
        store.lightOnly.toggle()
        applyPanelMode(animated: true)
    }

    @objc private func showPanel() {
        panel.orderFrontRegardless()
    }

    private var panelWidth: CGFloat { store.lightOnly ? 104 : 370 }

    private func applyPanelMode(animated: Bool) {
        var frame = panel.frame
        let rightEdge = frame.maxX
        frame.size.width = panelWidth
        frame.origin.x = rightEdge - panelWidth
        panel.standardWindowButton(.closeButton)?.isHidden = store.lightOnly
        panel.setFrame(frame, display: true, animate: animated)
    }
}

private extension AgentPhase {
    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .preparing: "Preparing"
        case .running: "Running"
        }
    }

    var menuBarColor: NSColor {
        switch self {
        case .stopped: NSColor(red: 1.00, green: 0.25, blue: 0.29, alpha: 1)
        case .preparing: NSColor(red: 1.00, green: 0.57, blue: 0.16, alpha: 1)
        case .running: NSColor(red: 0.20, green: 0.86, blue: 0.46, alpha: 1)
        }
    }
}

let app = NSApplication.shared
let delegate = TokenSignalApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
