import Cocoa

// Set to true at build time for beta builds. build.sh passes -D BETA_BUILD
// when building from a non-tag commit, adding a small "β" badge to the icon.
#if BETA_BUILD
    let isBetaBuild = true
#else
    let isBetaBuild = false
#endif

func makeMicIcon(muted: Bool) -> NSImage {
    let name = muted ? "mic.slash.fill" : "mic.fill"
    var config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular, scale: .medium)
    if muted {
        config = config.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
    }
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    let sized = base.withSymbolConfiguration(config) ?? base
    if !muted {
        sized.isTemplate = true
    }
    guard isBetaBuild else { return sized }
    return withBetaBadge(sized, muted: muted)
}

/// Composites a small "β" in the bottom-right corner of the icon.
private func withBetaBadge(_ source: NSImage, muted: Bool) -> NSImage {
    let size = source.size
    let result = NSImage(size: size)
    result.lockFocus()

    source.draw(in: NSRect(origin: .zero, size: size))

    let text = "β" as NSString
    let fontSize: CGFloat = size.width * 0.45
    let font = NSFont.boldSystemFont(ofSize: fontSize)
    let color: NSColor = muted ? .white : .controlAccentColor
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
    ]
    let textSize = text.size(withAttributes: attrs)
    let origin = NSPoint(
        x: size.width - textSize.width - 0.5,
        y: 0
    )
    text.draw(at: origin, withAttributes: attrs)

    result.unlockFocus()
    result.isTemplate = false
    return result
}
