import AppKit
import SwiftUI

/*
 THESIS: One physical signal answers “is Codex working?”; no dashboard grid.
 OWN-WORLD: Near-black instrument face, three true signal lamps, white telemetry, state color only.
 STORY: Glance at phase, read live tokens, confirm active agent count, return to work.
 FIRST VIEWPORT: Vertical lamps occupy left rail; status and large token total fill right field.
 FORM: Native floating utility panel, traffic-light staging pinned by user brief.
*/

@MainActor
final class TokenSignalApp: NSObject, NSApplicationDelegate {
    private let store = MonitorStore()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildStatusItem()
        store.start()
        showPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    private func buildPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 370, height: 196),
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
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "trafficlight",
            accessibilityDescription: "Token Signal"
        )
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Token Signal", action: #selector(showPanel), keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func togglePanel() {
        panel.isVisible ? panel.orderOut(nil) : showPanel()
    }

    @objc private func showPanel() {
        panel.orderFrontRegardless()
    }
}

let app = NSApplication.shared
let delegate = TokenSignalApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
