import Cocoa
import Carbon

class ShortcutRecorderWindowController: NSWindowController {
    var onShortcutSelected: ((UInt32, UInt32, String) -> Void)?
    var onCancelled: (() -> Void)?

    private var captureView: ShortcutCaptureView!
    private var label: NSTextField!
    private var saveButton: NSButton!
    private var cancelButton: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Shortcut"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let instruction = NSTextField(labelWithString: "Press the key combination you want to use:")
        instruction.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(instruction)

        captureView = ShortcutCaptureView()
        captureView.translatesAutoresizingMaskIntoConstraints = false
        captureView.onChanged = { [weak self] in self?.updateSaveButton() }
        contentView.addSubview(captureView)

        saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.isEnabled = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(saveButton)

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            instruction.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            instruction.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            instruction.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            captureView.topAnchor.constraint(equalTo: instruction.bottomAnchor, constant: 10),
            captureView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            captureView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            captureView.heightAnchor.constraint(equalToConstant: 32),

            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),

            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    private func updateSaveButton() {
        saveButton.isEnabled = captureView.capturedKeyCode != nil
    }

    @objc private func save() {
        guard let keyCode = captureView.capturedKeyCode else { return }
        let modifiers = captureView.capturedModifiers
        let display = captureView.capturedDisplay
        window?.close()
        onShortcutSelected?(keyCode, modifiers, display)
    }

    @objc private func cancel() {
        window?.close()
        onCancelled?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCancelled?()
        return true
    }
}

// MARK: - Key capture view

class ShortcutCaptureView: NSView {
    var onChanged: (() -> Void)?
    private(set) var capturedKeyCode: UInt32?
    private(set) var capturedModifiers: UInt32 = 0
    private(set) var capturedDisplay: String = ""

    private var label: NSTextField!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label = NSTextField(labelWithString: "Click here, then press a key…")
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    override func becomeFirstResponder() -> Bool {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return true
    }

    override func resignFirstResponder() -> Bool {
        layer?.borderColor = NSColor.separatorColor.cgColor
        return true
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let cocoaMods = event.modifierFlags.intersection([.command, .option, .shift, .control])

        // Reject bare modifier keys (keyCode 54–63 range covers modifiers)
        guard !event.modifierFlags.contains(.function) || keyCode > 63 else {
            // Allow pure function keys (F1–F19) even without modifiers
            // Key codes for F1-F12 and other function keys
            let fnKeys: Set<UInt32> = [
                122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                105, 107, 113, 106, 64, 79, 80
            ]
            if !fnKeys.contains(keyCode) { return }
            capturedKeyCode = keyCode
            capturedModifiers = 0
            capturedDisplay = keyName(for: keyCode, modifiers: 0)
            label.stringValue = capturedDisplay
            onChanged?()
            return
        }

        capturedKeyCode = keyCode
        capturedModifiers = carbonModifiers(from: cocoaMods)
        capturedDisplay = keyName(for: keyCode, modifiers: capturedModifiers)
        label.stringValue = capturedDisplay
        onChanged?()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    private func keyName(for keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }

        let knownKeys: [UInt32: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        if let name = knownKeys[keyCode] {
            parts.append(name)
        } else if let str = keyCodeToString(keyCode) {
            parts.append(str.uppercased())
        } else {
            parts.append("Key\(keyCode)")
        }
        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyLayoutPtr = unsafeBitCast(
            CFDataGetBytePtr(layout),
            to: UnsafePointer<CoreServices.UCKeyboardLayout>.self
        )
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        UCKeyTranslate(
            keyLayoutPtr, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
            0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState, 4, &length, &chars
        )
        return length > 0 ? String(utf16CodeUnits: Array(chars.prefix(length)), count: length) : nil
    }
}
