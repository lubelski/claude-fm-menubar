import AppKit
import Observation

/// What the menu and the settings window both show and change: the station list, the
/// player, and the updater.
@MainActor
@Observable
final class AppModel {
    let library: StationLibrary
    @ObservationIgnored let player: StreamPlayer
    @ObservationIgnored private(set) lazy var updater = AppUpdater { [weak self] in self?.player.isActive != true }

    private(set) var playerState: StreamPlayer.State = .stopped
    var volume: Int {
        didSet { player.volume = volume }
    }

    /// Called after the player's state changes, for the parts of the app that aren't views.
    @ObservationIgnored var onPlayerStateChange: (() -> Void)?

    @ObservationIgnored private var resumeAfterAudition = false

    init(library: StationLibrary = StationLibrary(), player: StreamPlayer = StreamPlayer()) {
        self.library = library
        self.player = player
        volume = player.volume
        player.onStateChange = { [weak self] state in
            NSLog("Claude FM state: %@", String(describing: state))
            self?.playerStateChanged(to: state)
        }
        player.tune(to: library.selected?.source, andPlay: false)
    }

    var isActive: Bool { playerState == .playing || playerState == .loading }

    /// The video that is playing or would play, on YouTube.
    var watchURL: URL { player.watchURL }

    // MARK: - Playback

    func toggle() { player.toggle() }
    func play() { player.play() }
    func stop() { player.stop() }
    func reconnect() { player.reconnect() }

    /// Selects a station, and starts it if `andPlay` is set.
    func tune(to id: UUID?, andPlay: Bool) {
        library.select(id)
        player.tune(to: library.selected?.source, andPlay: andPlay)
    }

    /// Stations are never checked in the background. What is known about one comes from
    /// playing it: when it last played, or why it couldn't.
    private func playerStateChanged(to state: StreamPlayer.State) {
        playerState = state
        if let id = library.selectedID {
            switch state {
            case .playing:
                library.markPlayed(id: id)
            case .failed(let reason) where player.failureIsPermanent:
                library.markFailed(id: id, reason: reason)
            default:
                break
            }
        }
        onPlayerStateChange?()
        updater.installPendingUpdate()
    }

    // MARK: - The station list

    /// Removes stations. If the playing one goes, playback moves to the station that is
    /// selected in its place.
    func remove(ids: Set<UUID>) {
        let wasActive = isActive
        library.remove(ids: ids)
        player.tune(to: library.selected?.source, andPlay: wasActive && library.selected != nil)
        onPlayerStateChange?()
    }

    func replaceLink(id: UUID, videoID: String, channel: String?) {
        let wasActive = isActive
        library.replaceLink(id: id, videoID: videoID, channel: channel)
        if id == library.selectedID {
            player.tune(to: library.selected?.source, andPlay: wasActive)
        }
    }

    func restoreClaudeFM() {
        library.restoreClaudeFM()
        player.tune(to: library.selected?.source, andPlay: false)
        onPlayerStateChange?()
    }

    @discardableResult
    func add(_ station: Station) -> Station {
        let added = library.add(station)
        // The first station in an empty list becomes the selected one.
        player.tune(to: library.selected?.source, andPlay: false)
        onPlayerStateChange?()
        return added
    }

    // MARK: - Auditioning a link in the Add Station sheet

    /// Quiets the station that is playing, so a link can be heard on its own.
    func beginAudition() {
        guard !resumeAfterAudition else { return }
        resumeAfterAudition = isActive
        if isActive { player.stop() }
    }

    func endAudition() {
        guard resumeAfterAudition else { return }
        resumeAfterAudition = false
        player.play()
    }
}
