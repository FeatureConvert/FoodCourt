#!/usr/bin/env swift
//
// Renders the 1024pt App Store icon with CoreGraphics and writes it into the asset
// catalog. The game's art is all vector, so the icon is too - regenerate with:
//
//     swift Scripts/make-icon.swift
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

guard let context = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("could not create bitmap context") }

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let S = CGFloat(side)
/// Unit-space helpers, y measured from the top the way the SwiftUI art is authored.
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * S, y: (1 - y) * S) }
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x * S, y: (1 - y - h) * S, width: w * S, height: h * S)
}

func fill(_ path: CGPath, _ color: CGColor, outline: Bool = true) {
    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
    if outline {
        context.addPath(path)
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
        context.setLineWidth(S * 0.014)
        context.strokePath()
    }
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius * S, cornerHeight: radius * S, transform: nil)
}

// Background: the same warm gradient the Burger Shack counter uses.
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [rgb(0xF5C242), rgb(0xE8733A)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0),
                           options: [])

// Soft plate behind the burger so it reads at small sizes.
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
context.fillEllipse(in: rect(0.11, 0.09, 0.78, 0.78))

// Top bun.
let dome = CGMutablePath()
dome.move(to: p(0.16, 0.46))
dome.addQuadCurve(to: p(0.84, 0.46), control: p(0.5, 0.10))
dome.closeSubpath()
fill(dome, rgb(0xD9903F))

// Sesame seeds.
for seed in [(0.34, 0.30), (0.50, 0.24), (0.66, 0.31)] {
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    context.fillEllipse(in: rect(seed.0 - 0.035, seed.1, 0.07, 0.045))
}

// Lettuce, patty, bottom bun.
fill(rounded(rect(0.13, 0.46, 0.74, 0.085), 0.03), rgb(0x5C9E4A))
fill(rounded(rect(0.11, 0.545, 0.78, 0.115), 0.035), rgb(0x8B4A2B))

let base = CGMutablePath()
base.move(to: p(0.16, 0.66))
base.addLine(to: p(0.84, 0.66))
base.addQuadCurve(to: p(0.16, 0.66), control: p(0.5, 0.83))
base.closeSubpath()
fill(base, rgb(0xD9903F))

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not encode PNG") }

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write PNG") }
print("Wrote \(output.path)")
