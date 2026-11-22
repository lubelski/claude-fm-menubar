import AppKit
import SwiftUI

/// The link being added in the Add Station sheet, and what is known about it so far.
///
/// This is the one place a station is checked eagerly: there is a single link, and a bad
/// one should never reach the list. The link is looked up for its title and channel, then
/// loaded in a hidden player to see that it really plays.
@MainActor
@Observable
final class StationDraft {
    enum Phase: Equatable {
        case empty
        case notALink
        case duplicate(String)
        case lookingUp
        case checking(VideoInfo?)
        case ready(VideoInfo?, isLive: Bool)
        case failed(VideoInfo?, String)
    }

    var link = ""
    var name = ""
    private(set) var phase: Phase = .empty
    private(set) var videoID: String?
    private(set) var filledFromClipboard = false
    private(set) var isAuditioning = false
    /// The station whose link is being replaced. Nil when adding.
    let replacing: Station?

    @ObservationIgnored var nameWasEdited = false
    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let probe = PlaybackProbe()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var clipboardLink: String?

    init(model: AppModel, request: SettingsNavigation.SheetRequest) {
        self.model = model
        replacing = request.replacing.flatMap(model.library.station(id:))
        if let replacing {
            name = replacing.name
            nameWasEdited = true
        }
        if let given = request.link {
            link = given
        } else if let text = NSPasteboard.general.string(forType: .string),
                  Station.videoID(from: text) != nil {
            // The common path is copy a link, press +, press Return.
            link = text.trimmingCharacters(in: .whitespacesAndNewlines)
            clipboardLink = link
        }
    }

    var canCommit: Bool {
        guard case .ready = phase else { return false }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var info: VideoInfo? {
        switch phase {
        case .checking(let info), .ready(let info, _), .failed(let info, _): info
        default: nil
        }
    }

    /// Call when the link changes, and once when the sheet appears.
    func linkChanged() {
        work?.cancel()
        stopAudition()
        probe.stop()
        filledFromClipboard = clipboardLink != nil && link == clipboardLink

        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        videoID = Station.videoID(from: text)
        guard !text.isEmpty else { return phase = .empty }
        guard let videoID else { return phase = .notALink }
        if let existing = model.library.stations.first(where: { $0.videoID == videoID }),
           existing.id != replacing?.id {
            return phase = .duplicate(existing.name)
        }

        phase = .lookingUp
        work = Task {
            let info = await Station.lookup(videoID: videoID)
            guard !Task.isCancelled else { return }
            if !nameWasEdited {
                name = info?.channel ?? info?.title ?? "YouTube \(videoID)"
            }
            phase = .checking(info)
            let result = await probe.check(videoID: videoID, volume: model.volume)
            guard !Task.isCancelled else { return }
            switch result {
            case .plays(let isLive): phase = .ready(info, isLive: isLive)
            case .fails(let reason): phase = .failed(info, reason)
            }
        }
    }

    /// Plays the link out loud, or stops. The station that was playing waits meanwhile.
    func toggleAudition() {
        guard case .ready = phase else { return }
        if isAuditioning {
            stopAudition()
        } else {
            model.beginAudition()
            probe.setAudible(true)
            isAuditioning = true
        }
    }

    private func stopAudition() {
        guard isAuditioning else { return }
        isAuditioning = false
        probe.setAudible(false)
        model.endAudition()
    }

    /// Adds the station, or replaces the link. Returns the station's id.
    func commit() -> UUID? {
        guard canCommit, let videoID else { return nil }
        let name = name.trimmingCharacters(in: .whitespaces)
        if let replacing {
            model.replaceLink(id: replacing.id, videoID: videoID, channel: info?.channel)
            model.library.rename(id: replacing.id, to: name)
            return replacing.id
        }
        return model.add(Station(name: name, videoID: videoID, channel: info?.channel)).id
    }

    func close() {
        work?.cancel()
        stopAudition()
        probe.stop()
    }
}

struct AddStationSheet: View {
    @State private var draft: StationDraft
    @Environment(\.dismiss) private var dismiss
    @FocusState private var linkFocused: Bool

    init(model: AppModel, request: SettingsNavigation.SheetRequest) {
        _draft = State(wrappedValue: StationDraft(model: model, request: request))
    }

    private var title: String { draft.replacing == nil ? "Add Station" : "Replace Link" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)

            HStack(spacing: 8) {
                TextField("Paste a YouTube link", text: $draft.link)
                    .textFieldStyle(.roundedBorder)
                    .focused($linkFocused)
                    .onChange(of: draft.link) { draft.linkChanged() }
                if draft.videoID != nil {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                        .accessibilityLabel("This is a YouTube link")
                }
            }

            detail

            HStack {
                Text("Name")
                TextField("Name", text: Binding(
                    get: { draft.name },
                    set: {
                        draft.name = $0
                        draft.nameWasEdited = true
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(title) {
                    if draft.commit() != nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canCommit)
            }
        }
        .padding(18)
        .frame(width: 410)
        .onAppear {
            linkFocused = true
            draft.linkChanged()
        }
        .onDisappear { draft.close() }
    }

    @ViewBuilder
    private var detail: some View {
        switch draft.phase {
        case .empty:
            Link(destination: URL(string: "https://www.youtube.com/results?search_query=live+radio")!) {
                Label("Search YouTube in your browser", systemImage: "arrow.up.right.square")
            }
            .font(.caption)
        case .notALink:
            Text("This isn't a link to a YouTube video.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .duplicate(let name):
            Text("Already in your stations as “\(name)”.")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            if draft.filledFromClipboard {
                Text("Filled in from the clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            preview
        }
    }

    private var preview: some View {
        HStack(alignment: .center, spacing: 12) {
            StationThumbnail(videoID: draft.videoID, width: 112)
                .overlay {
                    if case .ready = draft.phase {
                        Button(action: draft.toggleAudition) {
                            Image(systemName: draft.isAuditioning ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .shadow(radius: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(draft.isAuditioning ? "Stop" : "Listen")
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.info?.title ?? "YouTube video")
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                if let channel = draft.info?.channel {
                    Text(channel).font(.caption).foregroundStyle(.secondary)
                }
                status
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    @ViewBuilder
    private var status: some View {
        switch draft.phase {
        case .lookingUp:
            progress("Looking up…")
        case .checking:
            progress("Checking playback…")
        case .ready(_, let isLive):
            HStack(spacing: 8) {
                if isLive {
                    Label("LIVE", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.red)
                }
                Text("Plays in Claude FM").foregroundStyle(.green)
            }
            .font(.caption.weight(.semibold))
        case .failed(_, let reason):
            Text(reason).font(.caption.weight(.semibold)).foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}
