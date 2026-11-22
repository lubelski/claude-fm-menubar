import AppKit
import WebKit

/// Finds out whether one video plays in the embedded player, by loading it there muted.
/// The Add Station sheet uses this before a link is allowed into the list, and to audition it.
@MainActor
final class PlaybackProbe: NSObject, WKScriptMessageHandler {
    enum Result: Equatable {
        case plays(isLive: Bool)
        case fails(String)
    }

    private var webView: WKWebView?
    private var window: NSWindow?
    private var waiting: CheckedContinuation<Result, Never>?
    private var timeout: Task<Void, Never>?

    /// Loads the video and reports whether it started. Replaces any check in progress.
    func check(videoID: String, volume: Int) async -> Result {
        stop()
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakHandler(self), name: "bridge")
        let (webView, window) = HiddenWebView.make(configuration: config)
        self.webView = webView
        self.window = window
        webView.loadHTMLString(Self.html(videoID: videoID, volume: volume), baseURL: HiddenWebView.pageOrigin)

        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.finish(.fails("YouTube didn't answer. Check the connection and try again."))
        }
        return await withCheckedContinuation { waiting = $0 }
    }

    /// Plays the checked video out loud, or silences it again.
    func setAudible(_ audible: Bool) {
        run(audible ? "player.unMute(); player.playVideo()" : "player.mute(); player.pauseVideo()")
    }

    func stop() {
        finish(.fails("Cancelled."))
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "bridge")
        webView?.stopLoading()
        window?.contentView = nil
        window?.close()
        webView = nil
        window = nil
    }

    private func finish(_ result: Result) {
        timeout?.cancel()
        timeout = nil
        waiting?.resume(returning: result)
        waiting = nil
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript("player && (function(){ \(script) })()", completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard waiting != nil, let body = message.body as? [String: Any],
              let event = body["event"] as? String
        else { return }
        switch event {
        case "playing":
            // The answer is in. Stop pulling the stream until someone auditions it.
            run("player.pauseVideo()")
            finish(.plays(isLive: body["live"] as? Bool ?? false))
        case "error":
            finish(.fails(StreamPlayer.describe(errorCode: body["value"] as? Int)))
        default:
            break
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
              playerVars: { autoplay: 1, mute: 1, controls: 0, playsinline: 1, origin: location.origin },
              events: {
                onReady: function () { player.mute(); player.setVolume(\(volume)); player.playVideo(); },
                onStateChange: function (e) {
                  if (e.data !== 1) return;
                  var data = player.getVideoData ? player.getVideoData() : null;
                  post({ event: 'playing', live: !!(data && data.isLive) });
                },
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
