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
        case about
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
        window.makeKeyAndOrderFront(nil)
        activate()
        // When this runs from a menu item, the menu is still closing, and macOS hands focus
        // back to the app that had it. Ask again once the menu is gone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.activate()
        }
    }

    /// A menu bar app is not active when its menu is used. The plain activate() is a
    /// request that macOS turns down here, which leaves the window in front but unable to
    /// take typing until it is clicked. So insist.
    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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
        // Lets the SwiftUI toolbar, which holds the tabs, become the window's toolbar.
        host.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: host)
        window.toolbarStyle = .expanded
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
        Group {
            switch navigation.tab {
            case .stations: StationsTab(model: model, navigation: navigation)
            case .general: GeneralTab(model: model)
            case .about: AboutTab()
            }
        }
        .frame(width: 480)
        .frame(minHeight: 420)
        // The tabs sit in the window's toolbar, under the title. TabView draws them on the
        // edge of a bordered box instead, and the box's border runs through the control.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $navigation.tab) {
                    tabLabel("Stations").tag(SettingsNavigation.Tab.stations)
                    tabLabel("General").tag(SettingsNavigation.Tab.general)
                    tabLabel("About").tag(SettingsNavigation.Tab.about)
                }
                .labelsHidden()
                .tabsPickerStyle()
                .controlSize(.large)
                .fixedSize()
            }
        }
        .sheet(item: $navigation.sheet) { request in
            AddStationSheet(model: model, request: request)
        }
    }
}

/// A tab's label with room around its text. The picker sizes each tab to its label and
/// ignores padding on it, so the room is made of spaces that don't collapse.
private func tabLabel(_ title: String) -> Text {
    let space = "\u{2002}"
    return Text(space + title + space)
}

private extension View {
    /// The picker style made for switching sections, where the system has one.
    @ViewBuilder
    func tabsPickerStyle() -> some View {
        if #available(macOS 27.0, *) {
            pickerStyle(.tabs)
        } else {
            pickerStyle(.segmented)
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
            Section {
                Picker("Clicking the icon", selection: $clickToPlay) {
                    Text("Opens the menu").tag(false)
                    Text("Plays or stops").tag(true)
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text("Right-click does the other.")
                    .frame(maxWidth: .infinity, alignment: .leading)
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

/// What the app is, which version this is, and where it comes from.
struct AboutTab: View {
    private static let repository = URL(string: "https://github.com/lubelski/claude-fm-menubar")!

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Claude FM").font(.title2.weight(.semibold))
                Text(versionLine).font(.callout).foregroundStyle(.secondary)
            }
            Text("A menu bar radio for Claude FM, Anthropic's lo-fi stream on YouTube, and for any other YouTube stream you add.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
            HStack(spacing: 18) {
                Link("Source on GitHub", destination: Self.repository)
                Link("clau.de/radio", destination: StreamPlayer.radioLink)
            }
            Spacer(minLength: 0)
            Text("A personal project, not affiliated with Anthropic. The music belongs to the streams and their artists. MIT license.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
        }
        .padding(.top, 36)
        .padding(.bottom, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "development"
        return "Version \(version)" + ((info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? "")
    }
}
