#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let canvasSize = 1024
private let artworkRect = CGRect(x: 98, y: 112, width: 828, height: 828)

private func superellipse(in rect: CGRect, exponent: CGFloat = 5.0) -> CGPath {
    let path = CGMutablePath()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radiusX = rect.width / 2
    let radiusY = rect.height / 2
    let sampleCount = 256

    for sample in 0...sampleCount {
        let angle = (CGFloat(sample) / CGFloat(sampleCount)) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = center.x + radiusX * copysign(pow(abs(cosine), 2 / exponent), cosine)
        let y = center.y + radiusY * copysign(pow(abs(sine), 2 / exponent), sine)
        let point = CGPoint(x: x, y: y)

        if sample == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }

    path.closeSubpath()
    return path
}

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate_dmg_icon.swift <source.png> <output.png>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
    let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Unable to decode source icon: \(sourceURL.path)\n", stderr)
    exit(1)
}

guard
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    fputs("Unable to create icon canvas\n", stderr)
    exit(1)
}

context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high

let mask = superellipse(in: artworkRect)

// Generic Finder files do not receive the automatic mask and shadow applied to
// app bundles, so render those treatments directly into the DMG-specific icon.
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -14),
    blur: 30,
    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.48)
)
context.addPath(mask)
context.setFillColor(CGColor(srgbRed: 0.02, green: 0.024, blue: 0.028, alpha: 1))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(mask)
context.clip()
context.draw(sourceImage, in: artworkRect)
context.restoreGState()

guard let renderedImage = context.makeImage() else {
    fputs("Unable to render DMG icon\n", stderr)
    exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Unable to create output file: \(outputURL.path)\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, renderedImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write output file: \(outputURL.path)\n", stderr)
    exit(1)
}
