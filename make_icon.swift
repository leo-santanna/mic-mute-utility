import AppKit
import CoreGraphics

// Renders the WaveMute app icon at a given pixel size and saves it as a PNG.
// Usage: swift make_icon.swift <size> <output_path>

let size = Int(CommandLine.arguments[1])!
let outputPath = CommandLine.arguments[2]

let canvas = NSSize(width: size, height: size)
let image = NSImage(size: canvas)

image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let s = CGFloat(size)

// --- Rounded rect clip (standard macOS icon shape: corner radius = 22.37% of size) ---
let radius = s * 0.2237
let roundRect = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(roundRect)
ctx.clip()

// --- Background gradient: deep slate blue → rich indigo ---
let colors = [
    CGColor(red: 0.08, green: 0.10, blue: 0.22, alpha: 1), // top: deep navy
    CGColor(red: 0.20, green: 0.14, blue: 0.45, alpha: 1), // bottom: rich indigo
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: s / 2, y: s),
                       end:   CGPoint(x: s / 2, y: 0),
                       options: [])

// --- Subtle inner glow ring ---
let glowRadius = s * 0.38
let glowColors = [
    CGColor(red: 0.55, green: 0.45, blue: 1.0, alpha: 0.18),
    CGColor(red: 0.55, green: 0.45, blue: 1.0, alpha: 0),
] as CFArray
let glowGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: glowColors, locations: [0, 1])!
ctx.drawRadialGradient(glowGradient,
                       startCenter: CGPoint(x: s * 0.5, y: s * 0.56),
                       startRadius: 0,
                       endCenter:   CGPoint(x: s * 0.5, y: s * 0.56),
                       endRadius:   glowRadius,
                       options: [])

// --- Draw mic.fill SF Symbol centered ---
let symbolSize = s * 0.52
let symbolRect = CGRect(
    x: (s - symbolSize) / 2,
    y: (s - symbolSize) / 2 + s * 0.015, // very slightly above center
    width:  symbolSize,
    height: symbolSize
)

let cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.38, weight: .medium)
if let sym = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {

    sym.isTemplate = false
    // Draw white
    NSColor.white.setFill()
    let symSize = sym.size
    let symX = (s - symSize.width)  / 2
    let symY = (s - symSize.height) / 2 + s * 0.015

    // Use image drawing with white tint
    ctx.saveGState()
    ctx.clip(to: CGRect(x: symX, y: symY, width: symSize.width, height: symSize.height),
             mask: sym.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: symX, y: symY, width: symSize.width, height: symSize.height))
    ctx.restoreGState()
}

// --- Soft bottom shadow inside the icon for depth ---
let shadowColors = [
    CGColor(red: 0, green: 0, blue: 0, alpha: 0),
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.30),
] as CFArray
let shadowGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: shadowColors, locations: [0, 1])!
ctx.drawLinearGradient(shadowGradient,
                       start: CGPoint(x: s / 2, y: s * 0.25),
                       end:   CGPoint(x: s / 2, y: 0),
                       options: [])

image.unlockFocus()

// Save as PNG
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to render PNG")
    exit(1)
}

try! png.write(to: URL(fileURLWithPath: outputPath))
print("Saved \(size)x\(size) → \(outputPath)")
