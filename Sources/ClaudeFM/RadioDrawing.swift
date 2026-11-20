import CoreGraphics

/// The one routine that draws the radio, for the app icon and the menu bar icon.
enum RadioDrawing {
    /// The side of the square canvas the radio is drawn on.
    static let canvas: CGFloat = 1024
    /// The square around the radio itself, for callers that want it without the margin.
    static let bounds = CGRect(x: 212, y: 242, width: 600, height: 600)

    /// Draws the radio in the context's current fill color, on a clear background.
    /// The context needs a transparent backing, because the details are cut out of the body.
    static func draw(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        // Antenna, from the top left corner of the body up to the right.
        context.setLineWidth(30)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 330, y: 610))
        context.addLine(to: CGPoint(x: 600, y: 790))
        context.replacePathWithStrokedPath()
        context.fillPath()
        context.fillEllipse(in: CGRect(x: 576, y: 766, width: 48, height: 48))

        // Body.
        let body = CGRect(x: 222, y: 270, width: 580, height: 360)
        context.addPath(CGPath(roundedRect: body, cornerWidth: 76, cornerHeight: 76, transform: nil))
        context.fillPath()

        // Cut the speaker, the tuning window, and two knobs out of the body.
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: 282, y: 330, width: 240, height: 240))
        context.addPath(CGPath(roundedRect: CGRect(x: 572, y: 480, width: 180, height: 62),
                               cornerWidth: 31, cornerHeight: 31, transform: nil))
        context.fillPath()
        context.fillEllipse(in: CGRect(x: 578, y: 350, width: 72, height: 72))
        context.fillEllipse(in: CGRect(x: 674, y: 350, width: 72, height: 72))

        // The speaker cone, and the needle in the tuning window.
        context.setBlendMode(.normal)
        context.fillEllipse(in: CGRect(x: 347, y: 395, width: 110, height: 110))
        context.fill(CGRect(x: 690, y: 480, width: 16, height: 62))
    }
}
