import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let player = StreamPlayer()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self
        player.onStateChange = { [weak self] state in
            NSLog("Claude FM state: %@", String(describing: state))
            self?.updateButton()
        }
        updateButton()

        // For testing from a terminal: CLAUDE_FM_AUTOPLAY=1 starts playback at launch.
        if ProcessInfo.processInfo.environment["CLAUDE_FM_AUTOPLAY"] == "1" {
            player.play()
        }
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            rebuildMenu()
            // Attach the menu only for this click, so a left click keeps toggling playback.
            statusItem.menu = menu
            sender.performClick(nil)
        } else {
            player.toggle()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let (symbol, tip, dimmed): (String, String, Bool) = switch player.state {
        case .stopped: ("radio", "Claude FM: click to play", false)
        case .loading: ("radio", "Claude FM: connecting…", true)
        case .playing: ("waveform", "Claude FM: playing. Click to stop.", false)
        case .failed(let reason): ("exclamationmark.triangle", "Claude FM: \(reason)", false)
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        image?.isTemplate = true
        button.image = image
        button.toolTip = tip
        button.appearsDisabled = dimmed
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(item(player.isActive ? "Stop" : "Play", #selector(togglePlayback)))
        menu.addItem(VolumeMenuItem(volume: player.volume) { [weak self] in self?.player.volume = $0 })
        menu.addItem(item("Reconnect", #selector(reconnect)))

        menu.addItem(.separator())
        menu.addItem(item("Watch on YouTube", #selector(openStream)))
        menu.addItem(item("Claude FM Radio Link (clau.de/radio)", #selector(openRadioLink)))
        menu.addItem(item("Claude Code", #selector(openClaudeCode)))

        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Claude FM", #selector(quit), key: "q"))
    }

    private var statusLine: String {
        switch player.state {
        case .stopped: "Claude FM: stopped"
        case .loading: "Claude FM: connecting…"
        case .playing: "Claude FM: playing"
        case .failed(let reason): reason
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePlayback() { player.toggle() }
    @objc private func reconnect() { player.reconnect() }
    @objc private func openStream() { NSWorkspace.shared.open(player.watchURL) }
    @objc private func openRadioLink() { NSWorkspace.shared.open(StreamPlayer.radioLink) }
    @objc private func openClaudeCode() { NSWorkspace.shared.open(URL(string: "https://claude.com/product/claude-code")!) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            alert.runModal()
        }
    }
}
