import SwiftUI

/// The top of the menu: the station's name, what the player is doing, the transport
/// buttons, and the volume.
struct MenuPlayerView: View {
    /// What the player shows. Plain values, so the view can be drawn without a player.
    struct Content: Equatable {
        /// The selected station's name. Nil when the list is empty.
        var stationName: String?
        var state: StreamPlayer.State
        var volume: Int
    }

    /// What the buttons do.
    struct Actions {
        var toggle: () -> Void = {}
        var play: () -> Void = {}
        var reconnect: () -> Void = {}
        var openOnYouTube: () -> Void = {}
        var addStation: () -> Void = {}
        var setVolume: (Int) -> Void = { _ in }
    }

    let content: Content
    var actions = Actions()

    static let width: CGFloat = 280

    private var hasStation: Bool { content.stationName != nil }
    private var state: StreamPlayer.State { content.state }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(content.stationName ?? "No Stations")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hasStation ? .primary : .secondary)
                    .lineLimit(1)
                status
            }
            HStack(spacing: 30) {
                reconnectButton
                mainButton
                openButton
            }
            volume
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: Self.width)
        // The menu is monochrome, like the menus around it. Only a failure has a color.
        .tint(.primary)
    }

    @ViewBuilder
    private var status: some View {
        if !hasStation {
            Button(action: actions.addStation) {
                Text("Add a Station…").underline()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
        } else {
            switch state {
            case .stopped: statusText("Stopped")
            case .loading: statusText("Connecting…")
            case .playing: statusText("Playing")
            case .failed(let reason): statusText(reason, color: .red)
            }
        }
    }

    private func statusText(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Reconnect looks the stream up again. It is dimmed when stopped, where there is
    /// nothing to reconnect, and lit when the stream failed, where it is the way out.
    private var reconnectButton: some View {
        let failed = if case .failed = state { true } else { false }
        return Button {
            failed ? actions.play() : actions.reconnect()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(failed ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!hasStation || state == .stopped)
        .opacity(!hasStation || state == .stopped ? 0.35 : 1)
        .help("Reconnect")
        .accessibilityLabel("Reconnect")
    }

    private var mainButton: some View {
        Button(action: actions.toggle) {
            ZStack {
                switch state {
                case .playing:
                    Image(systemName: "stop.circle")
                        .foregroundStyle(.primary)
                case .loading:
                    // Click to cancel.
                    Circle().strokeBorder(.tertiary, lineWidth: 2.5).padding(3)
                    ProgressView().controlSize(.small)
                case .failed:
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                case .stopped:
                    Image(systemName: "play.circle")
                        .foregroundStyle(hasStation ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
            }
            .font(.system(size: 42, weight: .regular))
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!hasStation)
        .accessibilityLabel(mainLabel)
    }

    private var mainLabel: String {
        switch state {
        case .playing: "Stop"
        case .loading: "Cancel"
        case .failed: "Try Again"
        case .stopped: "Play"
        }
    }

    private var openButton: some View {
        Button(action: actions.openOnYouTube) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!hasStation)
        .opacity(hasStation ? 1 : 0.35)
        .help("Watch on YouTube")
        .accessibilityLabel("Watch on YouTube")
    }

    private var volume: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
            Slider(value: Binding(
                get: { Double(content.volume) },
                set: { actions.setVolume(Int($0.rounded())) }
            ), in: 0...100)
                .controlSize(.small)
                .accessibilityLabel("Volume")
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .disabled(!hasStation)
        .opacity(hasStation ? 1 : 0.35)
    }
}

/// The player in the menu, drawn from the app's model. It redraws while the menu is open.
struct MenuPlayer: View {
    let model: AppModel
    /// Opens the Add Station sheet.
    let addStation: () -> Void
    /// Closes the menu, for actions that leave it.
    let closeMenu: () -> Void

    var body: some View {
        MenuPlayerView(
            content: .init(stationName: model.library.selected?.name,
                           state: model.playerState, volume: model.volume),
            actions: .init(
                toggle: model.toggle,
                play: model.play,
                reconnect: model.reconnect,
                openOnYouTube: {
                    closeMenu()
                    NSWorkspace.shared.open(model.watchURL)
                },
                addStation: {
                    closeMenu()
                    addStation()
                },
                setVolume: { model.volume = $0 }
            )
        )
    }
}
