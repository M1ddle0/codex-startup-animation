import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Write a center-cropped copy; the caller decides whether to replace the source.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let width = Int(CommandLine.arguments[3])!, height = Int(CommandLine.arguments[4])!
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Cannot read source image") }
let scale = max(Double(width) / Double(image.width), Double(height) / Double(image.height))
let w = Double(image.width) * scale, h = Double(image.height) * scale
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.interpolationQuality = .high
context.draw(image, in: CGRect(x: (Double(width)-w)/2, y: (Double(height)-h)/2, width: w, height: h))
let isPNG = output.pathExtension.lowercased() == "png"
let type = isPNG ? UTType.png : UTType.jpeg
guard let result = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else { fatalError("Cannot write runtime image") }
let properties: CFDictionary? = isPNG ? nil : [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary
CGImageDestinationAddImage(destination, result, properties)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot finish runtime image") }
print("Prepared \(output.lastPathComponent): \(width) × \(height)")
