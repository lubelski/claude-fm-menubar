import AppKit

/// Sits over the menu bar icon so a YouTube link can be dropped on it. Clicks pass
/// through to the status item's button underneath.
final class LinkDropView: NSView {
    var onLink: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes([.URL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        link(in: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let link = link(in: sender.draggingPasteboard) else { return false }
        onLink?(link)
        return true
    }

    /// The dragged text, if it is a link to a YouTube video. Anything else is refused,
    /// so dragging other things across the menu bar does nothing.
    private func link(in pasteboard: NSPasteboard) -> String? {
        let text = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first?.absoluteString
            ?? pasteboard.string(forType: .string)
        guard let text, Station.videoID(from: text) != nil else { return nil }
        return text
    }
}
