import Foundation

/// A station the user added by pasting a YouTube link. Claude FM itself is not one of these:
/// it is built in, and its video ID is looked up each time.
struct Station: Codable, Equatable {
    var name: String
    /// The video the link pointed at. A live stream gets a new ID when its broadcast
    /// restarts, and then this station stops working until the user adds it again.
    let videoID: String

    /// The video ID in a pasted YouTube link, or nil if the text isn't one.
    static func videoID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased()
        else { return nil }

        let path = components.path.split(separator: "/").map(String.init)
        let candidate: String?
        if host == "youtu.be" {
            candidate = path.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "www.youtube-nocookie.com" {
            if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
                candidate = v
            } else if path.count >= 2, ["live", "embed", "shorts", "v"].contains(path[0]) {
                candidate = path[1]
            } else {
                candidate = nil
            }
        } else {
            candidate = nil
        }

        // The ID is written into the player page, so accept only the exact shape of one.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard let candidate, candidate.count == 11,
              candidate.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        return candidate
    }

    /// The video's title, or nil if it can't be found. YouTube's oEmbed endpoint has it for
    /// most videos. For the rest, it is read from the watch page.
    static func fetchTitle(videoID: String) async -> String? {
        let watchURL = "https://www.youtube.com/watch?v=\(videoID)"
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: watchURL),
            URLQueryItem(name: "format", value: "json"),
        ]
        struct Reply: Decodable { let title: String? }
        if let data = await fetch(components.url!),
           let title = clean((try? JSONDecoder().decode(Reply.self, from: data))?.title) {
            return title
        }

        guard let data = await fetch(URL(string: watchURL)!),
              let page = String(data: data, encoding: .utf8),
              let start = page.range(of: "<meta property=\"og:title\" content=\""),
              let end = page[start.upperBound...].firstIndex(of: "\"")
        else { return nil }
        var title = String(page[start.upperBound..<end])
        for (entity, character) in [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            title = title.replacingOccurrences(of: entity, with: character)
        }
        return clean(title)
    }

    private static func fetch(_ url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 10)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    private static func clean(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }
}

/// The user's stations and which one is selected, kept in UserDefaults.
enum StationStore {
    private static let listKey = "stations"
    private static let selectedKey = "selectedStation"

    static var stations: [Station] {
        get {
            guard let data = UserDefaults.standard.data(forKey: listKey) else { return [] }
            return (try? JSONDecoder().decode([Station].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: listKey) }
    }

    /// The selected station's video ID. Nil is Claude FM.
    static var selectedVideoID: String? {
        get {
            let id = UserDefaults.standard.string(forKey: selectedKey)
            return stations.contains { $0.videoID == id } ? id : nil
        }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }
}
