// Redraws the app icon's artwork, Resources/AppIcon.icon/Assets/radio.png: a white radio on
// a clear background. Icon.json in the same folder supplies the gradient behind it, and
// bundle.sh compiles the two into the app icon.
//
//   swift scripts/render-icon.swift Resources/AppIcon.icon/Assets/radio.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
context.setFillColor(white)
context.setStrokeColor(white)

// Antenna, from the top left corner of the body up to the right.
context.setLineWidth(30)
context.setLineCap(.round)
context.move(to: CGPoint(x: 330, y: 610))
context.addLine(to: CGPoint(x: 600, y: 790))
context.strokePath()
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

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("couldn't write \(output.path)") }
