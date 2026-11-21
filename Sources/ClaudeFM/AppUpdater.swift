import Foundation
import Sparkle

/// Keeps the app up to date with Sparkle.
///
/// Only a release build updates itself. `scripts/release.sh` writes the feed address and
/// the public signing key into Info.plist. A build without them, such as one from
/// `scripts/bundle.sh` alone, has no updater, so a development copy is never replaced.
@MainActor
final class AppUpdater {
    /// Whether this build can update itself.
    let isAvailable: Bool

    private let controller: SPUStandardUpdaterController?
    private let delegate: Delegate

    /// `canRelaunch` says whether the app may quit and relaunch right now.
    init(bundle: Bundle = .main, canRelaunch: @escaping @MainActor () -> Bool) {
        delegate = Delegate(canRelaunch: canRelaunch)
        let info = bundle.infoDictionary
        guard info?["SUFeedURL"] is String, info?["SUPublicEDKey"] is String else {
            isAvailable = false
            controller = nil
            return
        }
        isAvailable = true
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil
        )
    }

    /// False while a check is already running.
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Whether Sparkle looks for, downloads and installs updates without asking.
    var updatesAutomatically: Bool {
        get {
            guard let updater = controller?.updater else { return false }
            return updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
        }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    /// Checks now and shows Sparkle's own windows with the result.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Installs an update that was held back because the app couldn't relaunch then.
    /// Call this whenever relaunching becomes possible.
    func installPendingUpdate() {
        delegate.installPendingUpdate()
    }

    private final class Delegate: NSObject, SPUUpdaterDelegate {
        private let canRelaunch: @MainActor () -> Bool
        private var pendingInstall: (() -> Void)?

        init(canRelaunch: @escaping @MainActor () -> Bool) {
            self.canRelaunch = canRelaunch
        }

        /// Sparkle normally installs a downloaded update when the app quits. A menu bar
        /// app stays open for weeks, so install and relaunch as soon as the update is
        /// ready. A relaunch would cut the music off, so while the stream is playing the
        /// install waits until it stops.
        func updater(
            _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
            immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
        ) -> Bool {
            // Sparkle calls its delegate on the main thread.
            MainActor.assumeIsolated {
                if canRelaunch() {
                    immediateInstallHandler()
                } else {
                    pendingInstall = immediateInstallHandler
                }
            }
            return true
        }

        @MainActor
        func installPendingUpdate() {
            guard let install = pendingInstall, canRelaunch() else { return }
            pendingInstall = nil
            install()
        }
    }
}
