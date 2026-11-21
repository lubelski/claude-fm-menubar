// Renders the menu bar icon as it animates through each player state, on light and dark
// menu bars: docs/menubar-icon.gif, and a still of each state in docs/menubar-icon.png.
// Run through scripts/render-menubar-icon.sh, which compiles this with the app's icon code.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
let scale: CGFloat = 4
let backgrounds = [NSColor(white: 0.93, alpha: 1), NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)]
let foregrounds = [NSColor.black, NSColor.white]
let cell = NSSize(width: 32 * scale, height: 30 * scale)

/// Draws one frame: the icon tinted the way the menu bar tints a template image.
func frame(_ icons: [NSImage], caption: String) -> CGImage {
    let width = Int(cell.width) * icons.count * 2, height = Int(cell.height) + Int(14 * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    for (side, (background, foreground)) in zip(backgrounds, foregrounds).enumerated() {
        for (i, icon) in icons.enumerated() {
            let x = CGFloat(side * icons.count + i) * cell.width
            background.setFill()
            NSRect(x: x, y: 0, width: cell.width, height: cell.height).fill()
            let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
            let rect = NSRect(x: x + (cell.width - size.width) / 2, y: (cell.height - size.height) / 2,
                              width: size.width, height: size.height)
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r)
                foreground.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect)
        }
    }
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9 * scale), .foregroundColor: NSColor.black]
    caption.draw(at: NSPoint(x: 3 * scale, y: cell.height + 2 * scale), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

func write(_ images: [CGImage], to name: String, type: UTType, delay: Double = 0) {
    let url = outputDir.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil)!
    if type == .gif {
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    }
    for image in images {
        let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        CGImageDestinationAddImage(destination, image, type == .gif ? props : nil)
    }
    guard CGImageDestinationFinalize(destination) else { fatalError("couldn't write \(url.path)") }
    print("Wrote \(url.path)")
}

MainActor.assumeIsolated {
    // The animation, driven in real time through the app's own RadioIcon.
    let icon = RadioIcon()
    var frames: [CGImage] = []
    var caption = ""
    icon.onImage = { frames.append(frame([$0], caption: caption)) }
    let script: [(RadioIcon.Mode, String, Double)] = [
        (.searching, "connecting", 2.4), (.on, "playing", 1.2), (.off, "stopped", 1.2),
        (.trouble, "stream failed", 3.0), (.off, "stopped", 1.2),
    ]
    for (mode, label, seconds) in script {
        caption = label
        icon.setMode(mode)
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let count = frames.count
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 30))
            // Hold the last frame while the icon is still.
            if frames.count == count, let last = frames.last { frames.append(last) }
        }
    }
    write(frames, to: "menubar-icon.gif", type: .gif, delay: 1.0 / 30)

    // A still of each state's resting pose. Searching and failed show one moment of their motion.
    let stills = [RadioIcon.offPose, RadioIcon.Pose(antenna: .init(angle: 50, reach: 1), alpha: 1),
                  RadioIcon.Pose(antenna: .init(angle: 8, reach: 0.75), alpha: 1), RadioIcon.onPose]
    write([frame(stills.map(RadioIcon.image), caption: "stopped · connecting · failed · playing")],
          to: "menubar-icon.png", type: .png)
}
