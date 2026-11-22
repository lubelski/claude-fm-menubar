import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let player = StreamPlayer()
    private let library = StationLibrary()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let otherAudio = OtherAudioMonitor()
    private let icon = RadioIcon()
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
        icon.onImage = { [weak self] image in self?.statusItem.button?.image = image }
        player.onStateChange = { [weak self] state in
            NSLog("Claude FM state: %@", String(describing: state))
            self?.recordOutcome(of: state)
            self?.updateButton()
            self?.updateMonitor()
            self?.updater.installPendingUpdate()
        }
        otherAudio.onOtherAudioStarted = { [weak self] in
            NSLog("Claude FM: stopping because another app started playing")
            self?.player.stop()
        }
        player.tune(to: library.selected?.source, andPlay: false)
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

    /// Stations are never checked in the background. What is known about one comes from
    /// playing it: when it last played, or why it couldn't.
    private func recordOutcome(of state: StreamPlayer.State) {
        guard let id = library.selectedID else { return }
        switch state {
        case .playing:
            library.markPlayed(id: id)
        case .failed(let reason) where player.failureIsPermanent:
            library.markFailed(id: id, reason: reason)
        default:
            break
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    /// The icon is always the radio. Its antenna and opacity show the player's state.
    private func updateButton() {
        guard let button = statusItem.button else { return }
        let (mode, tip): (RadioIcon.Mode, String) = switch player.state {
        case .stopped where library.selected == nil: (.off, "Claude FM: no stations")
        case .stopped: (.off, "\(stationName): \(clickToPlay ? "click" : "right-click") to play")
        case .loading: (.searching, "\(stationName): connecting…")
        case .playing: (.on, "\(stationName): playing. \(clickToPlay ? "Click" : "Right-click") to stop.")
        case .failed(let reason): (.trouble, "\(stationName): \(reason)")
        }
        icon.setMode(mode)
        if button.image == nil { button.image = icon.currentImage() }
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let playback = item(player.isActive ? "Stop" : "Play", #selector(togglePlayback))
        if library.selected == nil { playback.action = nil }
        menu.addItem(playback)
        menu.addItem(VolumeMenuItem(volume: player.volume) { [weak self] in self?.player.volume = $0 })
        menu.addItem(item("Reconnect", #selector(reconnect)))
        menu.addItem(submenu("Stations", stationItems()))

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

    private func stationItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for station in library.stations {
            let entry = item(station.name, #selector(selectStation(_:)))
            entry.representedObject = station.id
            entry.state = station.id == library.selectedID ? .on : .off
            items.append(entry)
        }
        if !items.isEmpty { items.append(.separator()) }
        items.append(item("Add Station from Clipboard", #selector(addStationFromClipboard)))
        if let current = library.selected {
            items.append(item("Remove “\(current.name)”", #selector(removeCurrentStation)))
        }
        return items
    }

    private var stationName: String { library.selected?.name ?? "No Stations" }

    private func tune(to id: UUID?, andPlay: Bool) {
        library.select(id)
        player.tune(to: library.selected?.source, andPlay: andPlay)
        updateButton()
    }

    @objc private func selectStation(_ sender: NSMenuItem) {
        tune(to: sender.representedObject as? UUID, andPlay: true)
    }

    @objc private func addStationFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let videoID = Station.videoID(from: text)
        else {
            let alert = NSAlert()
            alert.messageText = "No YouTube link on the clipboard"
            alert.informativeText = "Copy the link to a YouTube video or live stream, then choose Add Station from Clipboard again."
            NSApp.activate()
            alert.runModal()
            return
        }
        // Show the ID until the title arrives, so the station is usable right away.
        let placeholder = "YouTube \(videoID)"
        let station = library.add(Station(name: placeholder, videoID: videoID))
        if station.name == placeholder {
            Task {
                guard let title = await Station.fetchTitle(videoID: videoID) else { return }
                library.rename(id: station.id, to: title)
                updateButton()
            }
        }
        tune(to: station.id, andPlay: true)
    }

    @objc private func removeCurrentStation() {
        guard let current = library.selected else { return }
        let wasActive = player.isActive
        library.remove(ids: [current.id])
        player.tune(to: library.selected?.source, andPlay: wasActive && library.selected != nil)
        updateButton()
    }

    private var statusLine: String {
        switch player.state {
        case .stopped where library.selected == nil: "No Stations"
        case .stopped: "\(stationName): stopped"
        case .loading: "\(stationName): connecting…"
        case .playing: "\(stationName): playing"
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
