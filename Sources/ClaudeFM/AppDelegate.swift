import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let player = StreamPlayer()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let otherAudio = OtherAudioMonitor()
    private lazy var updater = AppUpdater { [weak self] in self?.player.isActive != true }

    private func updateMonitor() {
        if stopForOtherAudio && player.isActive {
            otherAudio.start()
        } else {
            otherAudio.stop()
        }
    }

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
            self?.updateMonitor()
            self?.updater.installPendingUpdate()
        }
        otherAudio.onOtherAudioStarted = { [weak self] in
            NSLog("Claude FM: stopping because another app started playing")
            self?.player.stop()
        }
        updateButton()
        // Start the updater at launch, so it checks on its own schedule.
        _ = updater

        // For testing from a terminal: CLAUDE_FM_AUTOPLAY=1 starts playback at launch.
        if ProcessInfo.processInfo.environment["CLAUDE_FM_AUTOPLAY"] == "1" {
            player.play()
        }
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondaryClick == clickToPlay {
            rebuildMenu()
            // Attach the menu only for this click, so the other button keeps toggling playback.
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
        case .stopped: ("radio", "Claude FM: \(clickToPlay ? "click" : "right-click") to play", false)
        case .loading: ("radio", "Claude FM: connecting…", true)
        case .playing: ("waveform", "Claude FM: playing. \(clickToPlay ? "Click" : "Right-click") to stop.", false)
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
        menu.addItem(submenu("Links", [
            item("Watch on YouTube", #selector(openStream)),
            item("Claude FM Radio Link (clau.de/radio)", #selector(openRadioLink)),
            item("Claude Code", #selector(openClaudeCode)),
        ]))

        let playOnClick = item("Click to Play", #selector(toggleClickToPlay))
        playOnClick.state = clickToPlay ? .on : .off
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let stopForOther = item("Stop When Other Audio Plays", #selector(toggleStopForOtherAudio))
        stopForOther.state = stopForOtherAudio ? .on : .off
        var options = [playOnClick, stopForOther, login]
        if updater.isAvailable {
            let check = item("Check for Updates…", #selector(checkForUpdates))
            if !updater.canCheck {
                check.action = nil
            }
            let automatic = item("Update Automatically", #selector(toggleUpdatesAutomatically))
            automatic.state = updater.updatesAutomatically ? .on : .off
            options += [.separator(), check, automatic]
        }
        options += [.separator(), item("Quit Claude FM", #selector(quit), key: "q")]
        menu.addItem(submenu("Options", options))
    }

    private var statusLine: String {
        switch player.state {
        case .stopped: "Claude FM: stopped"
        case .loading: "Claude FM: connecting…"
        case .playing: "Claude FM: playing"
        case .failed(let reason): reason
        }
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach(sub.addItem)
        parent.submenu = sub
        return parent
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

    /// When true, a left click toggles playback and a right click opens the menu. Off by default.
    private var clickToPlay: Bool {
        get { UserDefaults.standard.bool(forKey: "clickToPlay") }
        set { UserDefaults.standard.set(newValue, forKey: "clickToPlay") }
    }

    @objc private func toggleClickToPlay() { clickToPlay.toggle(); updateButton() }

    /// When true, playback stops once another app starts playing audio. Off by default.
    private var stopForOtherAudio: Bool {
        get { UserDefaults.standard.bool(forKey: "stopForOtherAudio") }
        set { UserDefaults.standard.set(newValue, forKey: "stopForOtherAudio") }
    }

    @objc private func toggleStopForOtherAudio() { stopForOtherAudio.toggle(); updateMonitor() }

    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func toggleUpdatesAutomatically() { updater.updatesAutomatically.toggle() }

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
