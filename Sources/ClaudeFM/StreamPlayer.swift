import AppKit
import WebKit

/// Plays a YouTube stream through YouTube's embedded IFrame player, hosted in a web view
/// that is never shown. The stream is Claude FM unless the user picked another station.
@MainActor
final class StreamPlayer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    enum State: Equatable {
        case stopped
        case loading
        case playing
        case failed(String)
    }

    /// The short link that `/radio` in Claude Code opens. It redirects to the current stream,
    /// whose video ID changes when the broadcast restarts.
    static let radioLink = URL(string: "https://clau.de/radio")!
    static let fallbackVideoID = "tRsQsTMvPNg"

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .stopped {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    private(set) var videoID: String?
    /// The video of the station the user picked. Nil is Claude FM, whose video is looked up
    /// through the radio link.
    private(set) var pinnedVideoID: String?
    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID ?? Self.fallbackVideoID)")!
    }

    var volume: Int {
        didSet {
            UserDefaults.standard.set(volume, forKey: "volume")
            run("player && player.setVolume(\(volume))")
        }
    }

    private var webView: WKWebView?
    private var window: NSWindow?
    private var playerReady = false
    private var wantsPlayback = false
    private var hasPlayedOnce = false
    /// Counts loads, so a lookup that finishes after the station changed is dropped.
    private var loadGeneration = 0

    override init() {
        let saved = UserDefaults.standard.object(forKey: "volume") as? Int
        volume = saved ?? 80
        super.init()
    }

    var isActive: Bool { state == .playing || state == .loading }

    func toggle() {
        isActive ? stop() : play()
    }

    func play() {
        wantsPlayback = true
        state = .loading
        if webView == nil {
            Task { await load() }
        } else if playerReady {
            startPlayer()
        }
    }

    func stop() {
        wantsPlayback = false
        run("player && player.stopVideo()")
        state = .stopped
    }

    /// Looks up the current stream again and rebuilds the player.
    func reconnect() {
        let resume = wantsPlayback
        tearDown()
        if resume { play() }
    }

    /// Switches to another station, and starts it if `andPlay` is set. Nil is Claude FM.
    func tune(to pinned: String?, andPlay: Bool) {
        if pinned != pinnedVideoID {
            tearDown()
            wantsPlayback = false
            pinnedVideoID = pinned
            videoID = pinned
        }
        if andPlay && !isActive { play() }
    }

    // MARK: - Loading

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        var id = pinnedVideoID
        if id == nil { id = await Self.resolveVideoID() }
        guard generation == loadGeneration, wantsPlayback else { return }
        videoID = id
        buildWebView(videoID: id ?? Self.fallbackVideoID)
    }

    /// Follows the clau.de/radio redirect and reads the `v` parameter of the YouTube URL it lands on.
    private static func resolveVideoID() async -> String? {
        var request = URLRequest(url: radioLink, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let finalURL = response.url,
              let items = URLComponents(url: finalURL, resolvingAgainstBaseURL: false)?.queryItems,
              let id = items.first(where: { $0.name == "v" })?.value, !id.isEmpty
        else { return nil }
        return id
    }

    private func buildWebView(videoID: String) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakHandler(self), name: "bridge")

        let frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        let webView = WKWebView(frame: frame, configuration: config)
        webView.navigationDelegate = self

        // WebKit throttles media in views that are not in a window, so host the view in a
        // transparent window that never takes focus or shows up in the window cycle.
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = .init(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .stationary]
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()

        self.webView = webView
        self.window = window
        playerReady = false
        hasPlayedOnce = false

        // The embed refuses to play without a referring origin, so give the page one.
        webView.loadHTMLString(Self.html(videoID: videoID, volume: volume),
                               baseURL: URL(string: "https://claude-fm-menubar.localhost/"))
    }

    private func tearDown() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "bridge")
        webView?.stopLoading()
        window?.contentView = nil
        window?.close()
        webView = nil
        window = nil
        playerReady = false
        loadGeneration += 1
        state = .stopped
    }

    private func startPlayer() {
        // Pausing a live stream leaves it behind the live edge. Reloading the video starts at
        // the live edge, which is what a radio should do.
        let id = videoID ?? Self.fallbackVideoID
        run(hasPlayedOnce ? "player.loadVideoById('\(id)')" : "player.playVideo()")
        hasPlayedOnce = true
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Messages from the page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
        let value = body["value"] as? Int
        switch event {
        case "ready":
            playerReady = true
            if wantsPlayback { startPlayer() }
        case "state":
            // YT.PlayerState: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
            switch value {
            case 1: state = .playing
            case 3: if wantsPlayback { state = .loading }
            case 0:
                if wantsPlayback && pinnedVideoID != nil {
                    // A pasted link can be an ordinary video. A radio keeps going, so loop it.
                    run("player.playVideo()")
                } else {
                    state = wantsPlayback ? .failed("The stream ended. Try Reconnect.") : .stopped
                }
            case 2: if !wantsPlayback { state = .stopped }
            default: break
            }
        case "error":
            state = .failed(Self.describe(errorCode: value))
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        state = .failed(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        state = .failed(error.localizedDescription)
    }

    private static func describe(errorCode: Int?) -> String {
        switch errorCode {
        case 2: "YouTube rejected the video ID."
        case 5: "The player could not play this stream."
        case 100: "The stream is no longer available."
        case 101, 150: "The stream does not allow embedded playback."
        default: "YouTube player error \(errorCode.map(String.init) ?? "unknown")."
        }
    }

    private static func html(videoID: String, volume: Int) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"></head>
        <body style="margin:0;background:#000">
        <div id="player"></div>
        <script>
          function post(m) { window.webkit.messageHandlers.bridge.postMessage(m); }
          var player;
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              width: 320, height: 180, videoId: '\(videoID)',
              playerVars: { autoplay: 0, controls: 0, playsinline: 1, origin: location.origin },
              events: {
                onReady: function () { player.setVolume(\(volume)); player.unMute(); post({ event: 'ready' }); },
                onStateChange: function (e) { post({ event: 'state', value: e.data }); },
                onError: function (e) { post({ event: 'error', value: e.data }); }
              }
            });
          }
        </script>
        <script src="https://www.youtube.com/iframe_api"></script>
        </body></html>
        """
    }
}

/// WKUserContentController retains its handlers. This breaks the cycle with the player.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
