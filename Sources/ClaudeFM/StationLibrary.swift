import Foundation
import Observation

/// The station list and which station is selected, kept in a file of its own.
///
/// The list can grow very large, so nothing here walks it on a timer or checks stations
/// over the network. A station's failure is recorded only when playing it fails.
@MainActor
@Observable
final class StationLibrary {
    /// What is written to disk.
    struct File: Codable, Equatable {
        var version = 1
        var stations: [Station]
        var selectedID: UUID?
    }

    private(set) var stations: [Station]
    private(set) var selectedID: UUID?

    @ObservationIgnored private let fileURL: URL

    static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Claude FM/stations.json")
    }

    /// Reads the file. Without one, builds the list from what earlier versions kept in
    /// UserDefaults, or seeds Claude FM on a first launch.
    init(fileURL: URL = StationLibrary.defaultFileURL, legacy: UserDefaults = .standard) {
        self.fileURL = fileURL
        let file: File
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? Self.decoder.decode(File.self, from: data) {
                file = decoded
            } else {
                // Keep an unreadable file for inspection instead of overwriting it.
                let aside = fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: fileURL, to: aside)
                file = Self.migrate(legacyStations: nil, legacySelected: nil)
            }
            stations = file.stations
            selectedID = file.selectedID
        } else {
            file = Self.migrate(legacyStations: legacy.data(forKey: "stations"),
                                legacySelected: legacy.string(forKey: "selectedStation"))
            stations = file.stations
            selectedID = file.selectedID
            save()
        }
    }

    /// The first list for this file format. Earlier versions had Claude FM built in, kept
    /// added stations as name and video ID, and stored the selected video ID, with none
    /// meaning Claude FM.
    static func migrate(legacyStations: Data?, legacySelected: String?) -> File {
        struct Legacy: Decodable {
            let name: String
            let videoID: String
        }
        let claudeFM = Station.claudeFM()
        let old = legacyStations.flatMap { try? JSONDecoder().decode([Legacy].self, from: $0) } ?? []
        let added = old.map { Station(name: $0.name, videoID: $0.videoID) }
        let selected = added.first { $0.videoID == legacySelected } ?? claudeFM
        return File(stations: [claudeFM] + added, selectedID: selected.id)
    }

    // MARK: - Reading

    var selected: Station? {
        stations.first { $0.id == selectedID }
    }

    func station(id: UUID) -> Station? {
        stations.first { $0.id == id }
    }

    /// The stations to offer in the menu: the most recently played first, then the top of
    /// the list until `limit` is reached. The selected station is always among them.
    func recents(limit: Int = 10) -> [Station] {
        guard limit > 0 else { return [] }
        let played = stations
            .filter { $0.lastPlayed != nil }
            .sorted { $0.lastPlayed! > $1.lastPlayed! }
        var result = Array(played.prefix(limit))
        if result.count < limit {
            let have = Set(result.map(\.id))
            result += stations.lazy.filter { !have.contains($0.id) }.prefix(limit - result.count)
        }
        if let selected, !result.contains(where: { $0.id == selected.id }) {
            result[result.count - 1] = selected
        }
        return result
    }

    // MARK: - Changing

    func select(_ id: UUID?) {
        guard id != selectedID, id == nil || stations.contains(where: { $0.id == id }) else { return }
        selectedID = id
        save()
    }

    /// Adds a station to the end of the list. A link that is already in the list is not
    /// added twice: the station that has it is returned instead.
    @discardableResult
    func add(_ station: Station) -> Station {
        if let videoID = station.videoID, let existing = stations.first(where: { $0.videoID == videoID }) {
            return existing
        }
        stations.append(station)
        if selectedID == nil { selectedID = station.id }
        save()
        return station
    }

    /// Removes stations. If the selected one goes, the station that takes its place in
    /// the list is selected, or none when the list is empty.
    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let selectedIndex = stations.firstIndex { $0.id == selectedID }
        stations.removeAll { ids.contains($0.id) }
        if let selectedID, ids.contains(selectedID) {
            let index = min(selectedIndex ?? 0, stations.count - 1)
            self.selectedID = stations.isEmpty ? nil : stations[index].id
        }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { stations[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.reversed() { stations.remove(at: index) }
        stations.insert(contentsOf: moving, at: destination - before)
        save()
    }

    func rename(id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update(id) { $0.name = name }
    }

    /// Points a station at another video, after its old link died.
    func replaceLink(id: UUID, videoID: String, channel: String?) {
        update(id) {
            $0.videoID = videoID
            $0.channel = channel
            $0.failure = nil
        }
    }

    /// Records that the station played. This also clears a failure, so a stream that came
    /// back is no longer shown as broken.
    func markPlayed(id: UUID, at date: Date = Date()) {
        update(id) {
            $0.lastPlayed = date
            $0.failure = nil
        }
    }

    func markFailed(id: UUID, reason: String, at date: Date = Date()) {
        update(id) { $0.failure = Station.Failure(reason: reason, date: date) }
    }

    /// Puts Claude FM back at the top of the list, if no station follows clau.de/radio.
    @discardableResult
    func restoreClaudeFM() -> Station {
        if let existing = stations.first(where: { $0.videoID == nil }) { return existing }
        let station = Station.claudeFM()
        stations.insert(station, at: 0)
        if selectedID == nil { selectedID = station.id }
        save()
        return station
    }

    private func update(_ id: UUID, _ change: (inout Station) -> Void) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { return }
        var station = stations[index]
        change(&station)
        guard station != stations[index] else { return }
        stations[index] = station
        save()
    }

    // MARK: - Storage

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private func save() {
        let file = File(stations: stations, selectedID: selectedID)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Self.encoder.encode(file).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Claude FM: couldn't save stations: %@", error.localizedDescription)
        }
    }
}
