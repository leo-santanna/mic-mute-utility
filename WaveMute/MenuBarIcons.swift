import Cocoa

func makeMicIcon(muted: Bool) -> NSImage {
    let name = muted ? "mic.slash.fill" : "mic.fill"
    var config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular, scale: .medium)
    if muted {
        config = config.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
    }
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    let sized = base.withSymbolConfiguration(config) ?? base
    if !muted { sized.isTemplate = true }
    return sized
}
