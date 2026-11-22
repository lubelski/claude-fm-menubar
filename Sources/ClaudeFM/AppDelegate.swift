import AppKit
import SwiftUI

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
            // A link dropped on the icon opens the Add Station sheet with it filled in.
            let drop = LinkDropView(frame: button.bounds)
            drop.onLink = { [weak self] link in self?.settings.showAddStation(link: link) }
            button.addSubview(drop)
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

    /// How many stations the submenu lists before it falls back to the ones played last.
    private static let menuStationLimit = 10

    private func rebuildMenu() {
        menu.removeAllItems()

        let playerItem = NSMenuItem()
        let playerView = NSHostingView(rootView: MenuPlayer(
            model: model,
            addStation: { [weak self] in self?.addStation() },
            closeMenu: { [weak self] in self?.menu.cancelTracking() }
        ))
        playerView.frame.size = playerView.fittingSize
        playerItem.view = playerView
        menu.addItem(playerItem)

        menu.addItem(.separator())
        menu.addItem(submenu("Stations", stationItems()))

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit Claude FM", #selector(quit), key: "q"))
    }

    /// A short list shows every station in the order set in Settings. A long one shows the
    /// stations played last, so the menu stays the same height however large the list is.
    private func stationItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let all = library.stations
        if all.isEmpty {
            let none = NSMenuItem(title: "No Stations", action: nil, keyEquivalent: "")
            none.isEnabled = false
            items.append(none)
        } else if all.count <= Self.menuStationLimit {
            items += all.map(stationItem)
        } else {
            items.append(.sectionHeader(title: "Recently Played"))
            items += library.recents(limit: Self.menuStationLimit).map(stationItem)
        }
        items.append(.separator())
        items.append(item("Add Station…", #selector(addStation)))
        let allStations = item("All Stations…", #selector(manageStations))
        if !all.isEmpty { allStations.badge = NSMenuItemBadge(count: all.count) }
        items.append(allStations)
        return items
    }

    private func stationItem(_ station: Station) -> NSMenuItem {
        let entry = item(station.name, #selector(selectStation(_:)))
        entry.representedObject = station.id
        entry.state = station.id == library.selectedID ? .on : .off
        if station.failure != nil {
            // Gray with a warning, and still pickable: picking it is how it gets retried.
            let title = NSMutableAttributedString(
                string: station.name + "  ",
                attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.menuFont(ofSize: 0)]
            )
            if let symbol = NSImage(systemSymbolName: "exclamationmark.triangle",
                                    accessibilityDescription: "No longer available")?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed])) {
                let attachment = NSTextAttachment()
                attachment.image = symbol
                title.append(NSAttributedString(attachment: attachment))
            }
            entry.attributedTitle = title
        }
        return entry
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

    @objc private func quit() { NSApp.terminate(nil) }

    /// When true, a left click toggles playback and a right click opens the menu. Off by
    /// default. The General tab in Settings changes it.
    private var clickToPlay: Bool { UserDefaults.standard.bool(forKey: "clickToPlay") }

    /// When true, playback stops once another app starts playing audio. Off by default.
    private var stopForOtherAudio: Bool { UserDefaults.standard.bool(forKey: "stopForOtherAudio") }
}
