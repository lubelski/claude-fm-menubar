import AppKit
import SwiftUI

/// The station list: search, reorder, rename, remove, and the ways into the Add Station sheet.
struct StationsTab: View {
    let model: AppModel
    @Bindable var navigation: SettingsNavigation

    @State private var selection = Set<UUID>()
    @State private var search = ""
    @State private var renaming: UUID?
    @State private var draftName = ""
    @FocusState private var renameFocused: Bool

    private var library: StationLibrary { model.library }

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var shown: [Station] {
        guard !query.isEmpty else { return library.stations }
        return library.stations.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.channel?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if !library.stations.isEmpty { searchField }
            VStack(spacing: 0) {
                if library.stations.isEmpty {
                    emptyState
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    list
                }
                Divider()
                footer
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        }
        .padding(16)
        // A link dragged from a browser lands in the sheet, like every other way in.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            addStation(link: url.absoluteString)
            return true
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(searchPrompt, text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private var searchPrompt: String {
        let count = library.stations.count
        return count == 1 ? "Search 1 station" : "Search \(count) stations"
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(shown) { station in
                row(for: station)
            }
            // Order has no meaning inside a filtered list, so dragging is off while searching.
            .onMove(perform: query.isEmpty ? { library.move(fromOffsets: $0, toOffset: $1) } : nil)
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button("Rename") { beginRename(id) }
                if library.station(id: id)?.videoID != nil {
                    Button("Replace Link…") { navigation.sheet = .init(replacing: id) }
                }
                Divider()
            }
            if !ids.isEmpty {
                Button(ids.count == 1 ? "Remove" : "Remove \(ids.count) Stations") { remove(ids) }
            }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first { beginRename(id) }
        }
        .onDeleteCommand { remove(selection) }
        .onPasteCommand(of: [.url, .utf8PlainText]) { _ in
            addStation(link: NSPasteboard.general.string(forType: .string))
        }
    }

    private func row(for station: Station) -> some View {
        let isCurrent = station.id == library.selectedID
        return HStack(spacing: 10) {
            StationThumbnail(videoID: station.videoID)
                .opacity(station.failure == nil ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 2) {
                if renaming == station.id {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .focused($renameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { renaming = nil }
                        .onChange(of: renameFocused) { _, focused in
                            if !focused { commitRename() }
                        }
                } else {
                    Text(station.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(station.failure == nil ? .primary : .secondary)
                        .lineLimit(1)
                }
                subtitle(for: station)
            }
            Spacer(minLength: 8)
            if station.failure != nil, station.videoID != nil {
                Button("Replace Link…") { navigation.sheet = .init(replacing: station.id) }
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            } else if isCurrent && model.isActive {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.claudeViolet)
                    .accessibilityLabel("Playing")
            } else {
                Button {
                    model.tune(to: station.id, andPlay: true)
                } label: {
                    Image(systemName: "play.circle").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Play \(station.name)")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func subtitle(for station: Station) -> some View {
        if let failure = station.failure {
            // Nothing rechecks a station, so say when this was learned.
            Text("\(failure.shortReason) · last tried \(failure.date.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        } else {
            Text(station.videoID == nil
                ? "clau.de/radio · follows the current stream"
                : ["youtube.com", station.channel].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Stations", systemImage: "radio")
        } description: {
            Text("Add a YouTube live stream or video to play it from the menu bar.")
        } actions: {
            VStack(spacing: 10) {
                Button("Add Station…") { addStation(link: nil) }
                    .buttonStyle(.borderedProminent)
                // clau.de/radio is not a link most people would know to paste.
                Button("Restore Claude FM") { model.restoreClaudeFM() }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                addStation(link: nil)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Station")
            Button {
                remove(selection)
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selection.isEmpty)
            .accessibilityLabel("Remove Station")
            Spacer()
            Text(countLine).font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private var countLine: String {
        let total = library.stations.count
        if total == 0 { return "No stations" }
        if !query.isEmpty { return "\(shown.count) of \(total) stations" }
        return total == 1 ? "1 station" : "\(total) stations"
    }

    // MARK: - Actions

    private func addStation(link: String?) {
        navigation.sheet = .init(link: link)
    }

    private func remove(_ ids: Set<UUID>) {
        model.remove(ids: ids)
        selection.subtract(ids)
    }

    private func beginRename(_ id: UUID) {
        guard let station = library.station(id: id) else { return }
        draftName = station.name
        renaming = id
        renameFocused = true
    }

    private func commitRename() {
        guard let id = renaming else { return }
        renaming = nil
        library.rename(id: id, to: draftName)
    }
}

extension Station.Failure {
    /// The reason, short enough for a row.
    var shortReason: String {
        if reason.contains("no longer available") { return "No longer available" }
        if reason.contains("embedded playback") { return "Doesn't allow embedded playback" }
        return reason.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
