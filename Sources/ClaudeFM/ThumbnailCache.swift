import AppKit
import SwiftUI

/// Video thumbnails, fetched the first time a row asks for one and kept on disk after
/// that. Rows ask only when they scroll into view, so a very large list fetches little.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let memory = NSCache<NSString, NSImage>()
    private let directory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("dev.lubelski.ClaudeFM/thumbnails")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 300
    }

    func image(for videoID: String) async -> NSImage? {
        if let cached = memory.object(forKey: videoID as NSString) { return cached }
        let file = directory.appendingPathComponent("\(videoID).jpg")
        guard let data = await Self.load(videoID: videoID, file: file), let image = NSImage(data: data)
        else { return nil }
        memory.setObject(image, forKey: videoID as NSString)
        return image
    }

    private nonisolated static func load(videoID: String, file: URL) async -> Data? {
        if let data = try? Data(contentsOf: file) { return data }
        // The 16:9 size first. Some videos only have the older 4:3 one.
        for size in ["mqdefault", "hqdefault"] {
            let url = URL(string: "https://i.ytimg.com/vi/\(videoID)/\(size).jpg")!
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { continue }
            try? data.write(to: file, options: .atomic)
            return data
        }
        return nil
    }
}

/// A station's picture: the video's thumbnail, or the radio on violet for the station
/// that follows clau.de/radio. A pale block stands in until the thumbnail arrives.
struct StationThumbnail: View {
    let videoID: String?
    var width: CGFloat = 44

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if videoID == nil {
                Color.claudeViolet
                Image(systemName: "radio")
                    .font(.system(size: width * 0.3, weight: .medium))
                    .foregroundStyle(.white)
            } else if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.primary.opacity(0.08)
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: videoID) {
            image = nil
            if let videoID { image = await ThumbnailCache.shared.image(for: videoID) }
        }
        .accessibilityHidden(true)
    }
}

extension Color {
    /// The violet behind the radio on the Claude FM station's thumbnail. It sits inside the
    /// app icon's gradient. Controls don't use it: they follow the system accent color.
    static let claudeViolet = Color(red: 0x5B / 255, green: 0x48 / 255, blue: 0xC9 / 255)
}
