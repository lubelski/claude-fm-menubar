import AppKit
import SwiftUI
import Testing
@testable import ClaudeFM

/// Draws the menu's player in each state, on light and dark, into one picture. This is
/// not a check: scripts/render-menu-player.sh runs it to make docs/menu-player.png.
@MainActor
@Suite struct MenuPlayerRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDE_FM_RENDER_DIR"] != nil))
    func rendersEachState() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_FM_RENDER_DIR"]!)
        let states: [(String, MenuPlayerView.Content)] = [
            ("Playing", .init(stationName: "Claude FM", state: .playing, volume: 80)),
            ("Stopped", .init(stationName: "Claude FM", state: .stopped, volume: 80)),
            ("Connecting", .init(stationName: "Claude FM", state: .loading, volume: 80)),
            ("Failed", .init(stationName: "Synthwave Radio",
                             state: .failed("The stream is no longer available."), volume: 80)),
            ("No stations", .init(stationName: nil, state: .stopped, volume: 80)),
        ]
        let sheet = VStack(alignment: .leading, spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(states, id: \.0) { name, content in
                        VStack(spacing: 6) {
                            MenuPlayerView(content: content)
                                .background(.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(scheme == .light ? Color(white: 0.93) : Color(white: 0.14))
                .environment(\.colorScheme, scheme)
            }
        }

        // A window that is never shown, so AppKit-backed controls like the slider draw too.
        let host = NSHostingView(rootView: sheet)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("menu-player.png"))
    }
}
