import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private lazy var settings = SettingsWindowController(model: model)
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let otherAudio = OtherAudioMonitor()
    private let icon = RadioIcon()

    private var player: StreamPlayer { model.player }
    private var library: StationLibrary { model.library }
    private var updater: AppUpdater { model.updater }

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
        model.onPlayerStateChange = { [weak self] in
            self?.updateButton()
            self?.updateMonitor()
        }
        // The General tab writes its switches to UserDefaults.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateButton()
                self?.updateMonitor()
            }
        }
        NSApp.mainMenu = makeMainMenu()
        otherAudio.onOtherAudioStarted = { [weak self] in
            NSLog("Claude FM: stopping because another app started playing")
            self?.player.stop()
        }
        updateButton()
        // Start the updater at launch, so it checks on its own schedule.
        _ = updater

        // For testing from a terminal: CLAUDE_FM_AUTOPLAY=1 starts playback at launch, and
        // CLAUDE_FM_OPEN opens the settings window on "stations", "general" or "add-station".
        let environment = ProcessInfo.processInfo.environment
        if environment["CLAUDE_FM_AUTOPLAY"] == "1" {
            player.play()
        }
        switch environment["CLAUDE_FM_OPEN"] {
        case "stations": settings.show(tab: .stations)
        case "general": settings.show(tab: .general)
        case "add-station": settings.showAddStation(link: environment["CLAUDE_FM_LINK"])
        default: break
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

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))

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
        items.append(item("Add Station…", #selector(addStation)))
        items.append(item("Manage Stations…", #selector(manageStations)))
        return items
    }

    private var stationName: String { library.selected?.name ?? "No Stations" }

    @objc private func selectStation(_ sender: NSMenuItem) {
        model.tune(to: sender.representedObject as? UUID, andPlay: true)
        updateButton()
    }

    @objc private func addStation() { settings.showAddStation() }
    @objc private func manageStations() { settings.show(tab: .stations) }
    @objc private func openSettings() { settings.show() }

    /// A menu bar app shows no main menu, but its key equivalents still work. Without
    /// these, the settings window has no Paste, Close or Select All.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(item("Settings…", #selector(openSettings), key: ","))
        app.addItem(item("Quit Claude FM", #selector(quit), key: "q"))
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "\u{8}"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        for submenu in [app, edit, window] {
            let parent = NSMenuItem()
            parent.submenu = submenu
            main.addItem(parent)
        }
        return main
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
