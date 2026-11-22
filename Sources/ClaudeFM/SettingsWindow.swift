import AppKit
import ServiceManagement
import SwiftUI

/// Where the settings window is: which tab, and whether the Add Station sheet is down.
@MainActor
@Observable
final class SettingsNavigation {
    enum Tab: Hashable {
        case stations
        case general
    }

    /// A request to show the Add Station sheet.
    struct SheetRequest: Identifiable {
        let id = UUID()
        /// The station whose link is being replaced. Nil adds a new station.
        var replacing: UUID?
        /// The link to start with. Nil looks on the clipboard.
        var link: String?
    }

    var tab: Tab = .stations
    var sheet: SheetRequest?
}

/// The app's one window: the station list and the settings.
@MainActor
final class SettingsWindowController {
    let navigation = SettingsNavigation()
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show(tab: SettingsNavigation.Tab? = nil) {
        if let tab { navigation.tab = tab }
        let window = self.window ?? makeWindow()
        self.window = window
        // A menu bar app is not active when its menu is used, so ask for it.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens the window on the Stations tab with the Add Station sheet down.
    func showAddStation(link: String? = nil, replacing: UUID? = nil) {
        show(tab: .stations)
        // A sheet asked for before the window has drawn once is dropped, so ask on the next turn.
        DispatchQueue.main.async { [navigation] in
            navigation.sheet = SettingsNavigation.SheetRequest(replacing: replacing, link: link)
        }
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(model: model, navigation: navigation))
        let window = NSWindow(contentViewController: host)
        window.title = "Claude FM Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 520))
        window.center()
        return window
    }
}

struct SettingsView: View {
    let model: AppModel
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Stations", systemImage: "radio", value: SettingsNavigation.Tab.stations) {
                StationsTab(model: model, navigation: navigation)
            }
            Tab("General", systemImage: "gearshape", value: SettingsNavigation.Tab.general) {
                GeneralTab(model: model)
            }
        }
        .padding(.top, 10)
        .frame(width: 480)
        .frame(minHeight: 420)
        .tint(.claudeViolet)
        .sheet(item: $navigation.sheet) { request in
            AddStationSheet(model: model, request: request)
                .tint(.claudeViolet)
        }
    }
}

/// The switches that used to be the menu's Options submenu.
struct GeneralTab: View {
    let model: AppModel

    @AppStorage("stopForOtherAudio") private var stopForOtherAudio = false
    @AppStorage("clickToPlay") private var clickToPlay = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var updatesAutomatically = false

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Stop when other audio plays", isOn: $stopForOtherAudio)
            }
            Section("Menu bar") {
                Picker("Clicking the icon", selection: $clickToPlay) {
                    Text("Click opens the menu, right-click plays").tag(false)
                    Text("Click plays, right-click opens the menu").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            Section("System") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            }
            Section("Updates") {
                if model.updater.isAvailable {
                    Toggle("Update automatically", isOn: Binding(
                        get: { updatesAutomatically },
                        set: {
                            model.updater.updatesAutomatically = $0
                            updatesAutomatically = $0
                        }
                    ))
                }
                HStack {
                    if model.updater.isAvailable {
                        Button("Check for Updates…") { model.updater.checkForUpdates() }
                    }
                    Text(versionLine).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            updatesAutomatically = model.updater.updatesAutomatically
        }
        .alert("Couldn't change Launch at Login", isPresented: Binding(
            get: { loginError != nil }, set: { if !$0 { loginError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(loginError ?? "")
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "development"
        let build = info?["CFBundleVersion"] as? String
        let suffix = model.updater.isAvailable ? "" : " · this build doesn't update itself"
        return "Version \(version)" + (build.map { " (\($0))" } ?? "") + suffix
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
