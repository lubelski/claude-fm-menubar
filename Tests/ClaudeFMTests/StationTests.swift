import Foundation
import Testing
@testable import ClaudeFM

@Suite struct StationLinkTests {
    @Test(arguments: [
        ("https://www.youtube.com/watch?v=jfKfPfyJRdk", "jfKfPfyJRdk"),
        ("https://youtu.be/jfKfPfyJRdk?si=abc", "jfKfPfyJRdk"),
        ("https://www.youtube.com/live/jfKfPfyJRdk", "jfKfPfyJRdk"),
        ("https://music.youtube.com/watch?v=jfKfPfyJRdk&list=x", "jfKfPfyJRdk"),
        ("  https://www.youtube.com/embed/jfKfPfyJRdk\n", "jfKfPfyJRdk"),
    ])
    func readsVideoID(link: String, expected: String) {
        #expect(Station.videoID(from: link) == expected)
    }

    @Test(arguments: [
        "", "lofi radio", "https://example.com/watch?v=jfKfPfyJRdk",
        "https://www.youtube.com/watch?v=short", "https://www.youtube.com/watch?v=jfKfPfyJRd'",
        "https://www.youtube.com/@LofiGirl",
    ])
    func rejectsOtherText(text: String) {
        #expect(Station.videoID(from: text) == nil)
    }
}

@MainActor
@Suite struct StationLibraryTests {
    /// A library on a file of its own, with empty legacy defaults unless some are given.
    private func makeLibrary(legacy: [String: Any] = [:]) -> (StationLibrary, URL, UserDefaults) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("stations.json")
        let suite = "ClaudeFMTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        for (key, value) in legacy { defaults.set(value, forKey: key) }
        return (StationLibrary(fileURL: url, legacy: defaults), url, defaults)
    }

    private func video(_ n: Int) -> Station {
        Station(name: "Station \(n)", videoID: String(format: "video%06d", n))
    }

    @Test func firstLaunchSeedsClaudeFM() {
        let (library, url, _) = makeLibrary()
        #expect(library.stations.map(\.name) == ["Claude FM"])
        #expect(library.stations[0].videoID == nil)
        #expect(library.selected?.name == "Claude FM")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func migratesStationsFromDefaults() throws {
        let old = try JSONSerialization.data(withJSONObject: [
            ["name": "Lofi Girl", "videoID": "jfKfPfyJRdk"],
            ["name": "Chillhop", "videoID": "5yx6BWlEVcY"],
        ])
        let (library, _, _) = makeLibrary(legacy: ["stations": old, "selectedStation": "5yx6BWlEVcY"])
        #expect(library.stations.map(\.name) == ["Claude FM", "Lofi Girl", "Chillhop"])
        #expect(library.selected?.videoID == "5yx6BWlEVcY")
    }

    @Test func migrationWithNoSelectionPicksClaudeFM() throws {
        let old = try JSONSerialization.data(withJSONObject: [["name": "Lofi Girl", "videoID": "jfKfPfyJRdk"]])
        let (library, _, _) = makeLibrary(legacy: ["stations": old])
        #expect(library.selected?.videoID == nil)
        #expect(library.selected?.name == "Claude FM")
    }

    @Test func changesSurviveAReload() {
        let (library, url, defaults) = makeLibrary()
        let added = library.add(video(1))
        library.select(added.id)
        library.markFailed(id: added.id, reason: "The stream is no longer available.",
                           at: Date(timeIntervalSince1970: 1_800_000_000))
        library.rename(id: added.id, to: "Renamed")

        let reloaded = StationLibrary(fileURL: url, legacy: defaults)
        #expect(reloaded.stations == library.stations)
        #expect(reloaded.selected?.name == "Renamed")
        #expect(reloaded.selected?.failure?.reason == "The stream is no longer available.")
    }

    @Test func anExistingFileWinsOverLegacyDefaults() throws {
        let (library, url, defaults) = makeLibrary()
        library.remove(ids: Set(library.stations.map(\.id)))
        defaults.set(try JSONSerialization.data(withJSONObject: [["name": "Old", "videoID": "jfKfPfyJRdk"]]),
                     forKey: "stations")
        let reloaded = StationLibrary(fileURL: url, legacy: defaults)
        #expect(reloaded.stations.isEmpty)
        #expect(reloaded.selected == nil)
    }

    @Test func anUnreadableFileIsSetAsideAndTheListReseeded() throws {
        let (_, url, defaults) = makeLibrary()
        try Data("not json".utf8).write(to: url)
        let library = StationLibrary(fileURL: url, legacy: defaults)
        #expect(library.stations.map(\.name) == ["Claude FM"])
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
        #expect(try String(contentsOf: aside, encoding: .utf8) == "not json")
    }

    @Test func addingTheSameLinkTwiceKeepsOneStation() {
        let (library, _, _) = makeLibrary()
        let first = library.add(video(1))
        let second = library.add(Station(name: "Another name", videoID: first.videoID))
        #expect(second.id == first.id)
        #expect(library.stations.count == 2)
    }

    @Test func removingTheSelectedStationSelectsItsNeighbor() {
        let (library, _, _) = makeLibrary()
        let a = library.add(video(1)), b = library.add(video(2))
        library.select(a.id)
        library.remove(ids: [a.id])
        #expect(library.selectedID == b.id)
        library.remove(ids: [b.id])
        #expect(library.selected?.name == "Claude FM")
    }

    @Test func theListCanBeEmptiedAndClaudeFMRestored() {
        let (library, _, _) = makeLibrary()
        library.remove(ids: Set(library.stations.map(\.id)))
        #expect(library.stations.isEmpty)
        #expect(library.selected == nil)
        #expect(library.recents().isEmpty)

        let restored = library.restoreClaudeFM()
        #expect(library.stations == [restored])
        #expect(library.selectedID == restored.id)
        #expect(library.restoreClaudeFM().id == restored.id)
    }

    @Test func addingToAnEmptyListSelectsTheStation() {
        let (library, _, _) = makeLibrary()
        library.remove(ids: Set(library.stations.map(\.id)))
        let added = library.add(video(1))
        #expect(library.selectedID == added.id)
    }

    @Test func movingRowsMatchesListSemantics() {
        let (library, _, _) = makeLibrary()
        for n in 1...4 { library.add(video(n)) }
        // Claude FM, 1, 2, 3, 4. Move rows 1 and 2 to the end.
        library.move(fromOffsets: IndexSet([1, 2]), toOffset: 5)
        #expect(library.stations.map(\.name) == ["Claude FM", "Station 3", "Station 4", "Station 1", "Station 2"])
        library.move(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        #expect(library.stations.first?.name == "Station 2")
    }

    @Test func playingClearsAFailure() {
        let (library, _, _) = makeLibrary()
        let station = library.add(video(1))
        library.markFailed(id: station.id, reason: "gone")
        #expect(library.station(id: station.id)?.failure != nil)
        library.markPlayed(id: station.id)
        #expect(library.station(id: station.id)?.failure == nil)
        #expect(library.station(id: station.id)?.lastPlayed != nil)
    }

    @Test func replacingALinkClearsTheFailure() {
        let (library, _, _) = makeLibrary()
        let station = library.add(video(1))
        library.markFailed(id: station.id, reason: "gone")
        library.replaceLink(id: station.id, videoID: "newVideo001", channel: "Channel")
        let updated = library.station(id: station.id)
        #expect(updated?.videoID == "newVideo001")
        #expect(updated?.channel == "Channel")
        #expect(updated?.failure == nil)
    }

    @Test func recentsAreLastPlayedFirstThenTheTopOfTheList() {
        let (library, _, _) = makeLibrary()
        let added = (1...20).map { library.add(video($0)) }
        library.markPlayed(id: added[14].id, at: Date(timeIntervalSince1970: 100))
        library.markPlayed(id: added[7].id, at: Date(timeIntervalSince1970: 300))
        library.markPlayed(id: added[2].id, at: Date(timeIntervalSince1970: 200))

        let recents = library.recents(limit: 5).map(\.name)
        #expect(recents == ["Station 8", "Station 3", "Station 15", "Claude FM", "Station 1"])
    }

    @Test func recentsAlwaysIncludeTheSelectedStation() {
        let (library, _, _) = makeLibrary()
        let added = (1...20).map { library.add(video($0)) }
        for (offset, station) in added.prefix(10).enumerated() {
            library.markPlayed(id: station.id, at: Date(timeIntervalSince1970: Double(offset)))
        }
        library.select(added[19].id)
        let recents = library.recents(limit: 10)
        #expect(recents.count == 10)
        #expect(recents.last?.id == added[19].id)
    }

    @Test func aVeryLargeListStaysQuick() throws {
        let (_, url, defaults) = makeLibrary()
        let file = StationLibrary.File(stations: (1...5000).map(video), selectedID: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(file).write(to: url)

        let clock = ContinuousClock()
        var library: StationLibrary!
        let reading = clock.measure {
            library = StationLibrary(fileURL: url, legacy: defaults)
            _ = library.recents()
        }
        let changing = clock.measure {
            library.markPlayed(id: library.stations[4000].id)
        }
        #expect(library.stations.count == 5000)
        #expect(reading < .milliseconds(500))
        #expect(changing < .milliseconds(250))
    }
}
