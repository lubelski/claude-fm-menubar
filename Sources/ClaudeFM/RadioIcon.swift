import AppKit

/// The menu bar icon: the radio from the app icon, with an antenna that shows what the
/// player is doing. Off, it is faded and the antenna is pushed down into the body. While it
/// looks for the stream the antenna swings back and forth, and when the stream is broken
/// the antenna sags and twitches. Playing, it looks like the app icon.
@MainActor
final class RadioIcon {
    enum Mode: Equatable {
        case off
        case searching
        case trouble
        case on
    }

    struct Pose {
        var antenna: RadioDrawing.Antenna
        var alpha: CGFloat
    }

    static let onPose = Pose(antenna: .standard, alpha: 1)
    static let offPose = Pose(antenna: .init(angle: 0, reach: 0.35), alpha: 0.4)

    /// Called with each new frame.
    var onImage: ((NSImage) -> Void)?

    private(set) var mode: Mode = .off
    private var pose = offPose
    private var modeStart = Date()
    private var timer: Timer?

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        modeStart = Date()
        if reduceMotion {
            pose = target(at: 0)
            stopTimer()
            onImage?(Self.image(pose))
            return
        }
        startTimer()
        tick()
    }

    /// The current frame, for the first image at launch.
    func currentImage() -> NSImage {
        Self.image(pose)
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
        let k: CGFloat = 0.22
        pose.antenna.angle += (goal.antenna.angle - pose.antenna.angle) * k
        pose.antenna.reach += (goal.antenna.reach - pose.antenna.reach) * k
        pose.alpha += (goal.alpha - pose.alpha) * k

        // Off and on hold still, so stop drawing once they settle.
        let settled = abs(goal.antenna.angle - pose.antenna.angle) < 0.2
            && abs(goal.antenna.reach - pose.antenna.reach) < 0.005
            && abs(goal.alpha - pose.alpha) < 0.005
        if settled && (mode == .off || mode == .on) {
            pose = goal
            stopTimer()
        }
        onImage?(Self.image(pose))
    }

    /// Where the icon wants to be, `t` seconds into the current mode.
    private func target(at t: Double) -> Pose {
        switch mode {
        case .off:
            return Self.offPose
        case .on:
            return Self.onPose
        case .searching:
            // Swing the antenna back and forth, like hunting for a station. It swings down
            // from where it rests, because there is no room above: see `image`.
            let swing = reduceMotion ? 0 : CGFloat(sin(2 * .pi * t / 1.6))
            return Pose(antenna: .init(angle: 14 + 20 * swing, reach: 1), alpha: 1)
        case .trouble:
            // Sagging and shorter, with a short shake every couple of seconds.
            var angle: CGFloat = 8
            let phase = t.truncatingRemainder(dividingBy: 2.2)
            if !reduceMotion && phase < 0.6 {
                angle += 7 * CGFloat(sin(2 * .pi * phase * 6) * (1 - phase / 0.6))
            }
            return Pose(antenna: .init(angle: angle, reach: 0.75), alpha: 1)
        }
    }

    // MARK: - Drawing

    /// The icon is 18pt wide like the radio and 22pt tall. The radio's body is centered in
    /// it, so the body lines up with the other menu bar icons. The antenna takes the room
    /// above, and at rest its tip just reaches the top edge.
    static let size = NSSize(width: 18, height: 22)

    /// The middle of the body in the drawing's coordinates. Keep in step with RadioDrawing.
    private static let bodyMidY: CGFloat = 270 + 360 / 2

    static func image(_ pose: Pose) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Fade the whole radio as one layer, so the cutouts stay clear.
            context.setAlpha(pose.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            let scale = size.width / RadioDrawing.bounds.width
            context.translateBy(x: 0, y: size.height / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -RadioDrawing.bounds.minX, y: -bodyMidY)
            context.setFillColor(.black)
            RadioDrawing.draw(in: context, antenna: pose.antenna)
            context.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        return image
    }
}
