import AppKit

/// The menu bar icon. It draws the `radio` symbol's body with its own antenna, so the antenna
/// can move: folded down and faded when off, swinging around while it looks for the stream,
/// and twitching when the stream is broken. While playing it shows the `waveform` symbol.
@MainActor
final class RadioIcon {
    enum Mode: Equatable {
        case off
        case searching
        case trouble
        case on
    }

    /// Antenna angle in degrees above horizontal (leaning left), how far it is pulled out
    /// (0...1), and the opacity of the whole icon.
    struct Pose {
        var angle: Double
        var reach: Double
        var alpha: Double
    }

    static let upPose = Pose(angle: 17, reach: 1, alpha: 1)
    static let downPose = Pose(angle: 0, reach: 0.35, alpha: 0.4)

    /// Called with each new frame.
    var onImage: ((NSImage) -> Void)?

    private(set) var mode: Mode = .off
    private var pose = downPose
    private var modeStart = Date()
    private var timer: Timer?
    private let body = NSImage(systemSymbolName: "radio", accessibilityDescription: nil)!
    private let waveform = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!

    init() {
        waveform.isTemplate = true
    }

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        modeStart = Date()
        if mode == .on {
            // Stopping from here starts the fold-down from a raised antenna.
            pose = Self.upPose
            stopTimer()
            onImage?(waveform)
            return
        }
        if reduceMotion {
            pose = target(at: 0)
            stopTimer()
            onImage?(render(pose))
            return
        }
        startTimer()
        tick()
    }

    /// Draws the current frame without animating, for the first image at launch.
    func currentImage() -> NSImage {
        mode == .on ? waveform : render(pose)
    }

    // MARK: - Animation

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common keeps it running while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let goal = target(at: Date().timeIntervalSince(modeStart))
        // Ease toward the goal each frame. This also carries the fade and the fold between modes.
        let k = 0.22
        pose.angle += (goal.angle - pose.angle) * k
        pose.reach += (goal.reach - pose.reach) * k
        pose.alpha += (goal.alpha - pose.alpha) * k
        onImage?(render(pose))

        if mode == .off,
           abs(goal.angle - pose.angle) < 0.2, abs(goal.reach - pose.reach) < 0.005,
           abs(goal.alpha - pose.alpha) < 0.005 {
            pose = goal
            onImage?(render(pose))
            stopTimer()
        }
    }

    /// Where the antenna wants to be, `t` seconds into the current mode.
    private func target(at t: Double) -> Pose {
        switch mode {
        case .off, .on:
            return mode == .off ? Self.downPose : Self.upPose
        case .searching:
            // Swing the antenna back and forth, like hunting for a station.
            let swing = reduceMotion ? 0 : sin(2 * .pi * t / 1.6)
            return Pose(angle: 22 + 16 * swing, reach: 1, alpha: 1)
        case .trouble:
            // Leaned over, with a short shake every couple of seconds.
            var angle = 30.0
            let phase = t.truncatingRemainder(dividingBy: 2.2)
            if !reduceMotion && phase < 0.6 {
                angle += 7 * sin(2 * .pi * phase * 6) * (1 - phase / 0.6)
            }
            return Pose(angle: angle, reach: 0.75, alpha: 1)
        }
    }

    // MARK: - Drawing

    private func render(_ pose: Pose) -> NSImage {
        let body = self.body
        // Extra room above and below so a raised antenna fits. The body stays centered.
        let pad = 2.0
        let size = NSSize(width: body.size.width, height: body.size.height + 2 * pad)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.width / size.width
            let bodyRect = NSRect(x: 0, y: pad * scale, width: rect.width, height: rect.height - 2 * pad * scale)
            let w = bodyRect.width, h = bodyRect.height, y0 = bodyRect.minY

            // Fade the body and antenna as one layer, so they don't stack where they overlap.
            cg.setAlpha(pose.alpha)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)

            // The symbol's own antenna sits entirely above the body's top edge. Clip it off.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: y0 + h * 0.758)).setClip()
            body.draw(in: bodyRect)
            NSGraphicsContext.restoreGraphicsState()

            // Pivot where the symbol's antenna meets the body, near the top-right corner.
            let pivot = NSPoint(x: w * 0.765, y: y0 + h * 0.745)
            let length = w * 0.51 * pose.reach
            let radians = pose.angle * .pi / 180
            let antenna = NSBezierPath()
            antenna.move(to: pivot)
            antenna.line(to: NSPoint(x: pivot.x - length * cos(radians), y: pivot.y + length * sin(radians)))
            antenna.lineWidth = w * 0.053
            antenna.lineCapStyle = .round
            NSColor.black.setStroke()
            antenna.stroke()

            cg.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        return image
    }
}
