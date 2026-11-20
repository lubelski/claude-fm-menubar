// Redraws the app icon's artwork: a white radio on a clear background, from the app's own
// radio drawing. Run through scripts/render-icon.sh, which compiles this with that drawing.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = Int(RadioDrawing.canvas)
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
RadioDrawing.draw(in: context)

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("couldn't write \(output.path)") }
