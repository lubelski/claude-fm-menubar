import AppKit
import WebKit

/// Web views that play YouTube without ever being seen.
@MainActor
enum HiddenWebView {
    /// The embed refuses to play without a referring origin, so pages are loaded under this one.
    static let pageOrigin = URL(string: "https://claude-fm-menubar.localhost/")!

    /// WebKit throttles media in views that are not in a window, so the view is hosted in a
    /// transparent window that never takes focus or shows up in the window cycle.
    static func make(configuration: WKWebViewConfiguration) -> (WKWebView, NSWindow) {
        let frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        let webView = WKWebView(frame: frame, configuration: configuration)

        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = .init(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .stationary]
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        return (webView, window)
    }
}

/// WKUserContentController retains its handlers. This breaks the cycle with the owner.
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
