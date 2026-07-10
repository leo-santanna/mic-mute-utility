import Carbon
import Cocoa
import CoreAudio

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isMuted = false
    private var hotKeyRef: EventHotKeyRef?
    private var shortcutMenuItem: NSMenuItem!
    private var recorderWindowController: ShortcutRecorderWindowController?

    private var shortcutKeyCode: UInt32 = 101 // F9 default
    private var shortcutModifiers: UInt32 = 0
    private var shortcutDisplay: String = "F9"
    private let hidMonitor = HIDMonitor()

    func applicationDidFinishLaunching(_: Notification) {
        loadShortcut()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Wave Mute", action: #selector(toggleMute), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        shortcutMenuItem = NSMenuItem(title: shortcutMenuTitle(), action: nil, keyEquivalent: "")
        shortcutMenuItem.isEnabled = false
        menu.addItem(shortcutMenuItem)
        menu.addItem(NSMenuItem(title: "Change Shortcut…", action: #selector(changeShortcut), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        installEventHandler()
        registerHotKey()
        installCoreAudioGuard()
        startHIDMonitor()

        // Always start unmuted on launch
        hidMonitor.sendMute(false)
        updateMenuBarIcon()
    }

    // MARK: - Mute

    @objc func toggleMute() {
        isMuted.toggle()
        hidMonitor.sendMute(isMuted)
        updateMenuBarIcon()
    }

    // MARK: - Menu bar

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = makeMicIcon(muted: isMuted)
        button.imagePosition = .imageOnly
    }

    private func shortcutMenuTitle() -> String {
        "Shortcut: \(shortcutDisplay)"
    }

    // MARK: - Hotkey

    private func installEventHandler() {
        let handler: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.toggleMute() }
            return noErr
        }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(), handler, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), nil
        )
    }

    private func registerHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType("WMUT".fourCharCode), id: 1)
        RegisterEventHotKey(shortcutKeyCode, shortcutModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Shortcut persistence

    private func loadShortcut() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "shortcutKeyCode") != nil else { return }
        shortcutKeyCode = UInt32(defaults.integer(forKey: "shortcutKeyCode"))
        shortcutModifiers = UInt32(defaults.integer(forKey: "shortcutModifiers"))
        shortcutDisplay = defaults.string(forKey: "shortcutDisplay") ?? "F9"
    }

    func applyNewShortcut(keyCode: UInt32, modifiers: UInt32, display: String) {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: "shortcutKeyCode")
        defaults.set(Int(modifiers), forKey: "shortcutModifiers")
        defaults.set(display, forKey: "shortcutDisplay")
        shortcutKeyCode = keyCode
        shortcutModifiers = modifiers
        shortcutDisplay = display
        registerHotKey()
        shortcutMenuItem.title = shortcutMenuTitle()
    }

    // MARK: - Launch at login

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = !LaunchAtLogin.isEnabled
        LaunchAtLogin.isEnabled = newState
        sender.state = newState ? .on : .off
    }

    // MARK: - Physical button monitoring

    private func startHIDMonitor() {
        hidMonitor.onStateChanged = { [weak self] muted in
            guard let self else { return }
            isMuted = muted
            updateMenuBarIcon()
        }
        hidMonitor.start()
    }

    // MARK: - CoreAudio bounce-back guard

    /// When Report 6 mutes the device at hardware level, the device bounces a
    /// USB Audio Class mute event back to macOS CoreAudio. Meet detects that as
    /// "system muted". We subscribe to that property and immediately reset it to
    /// unmuted so macOS never sees a persistent mute state.
    private func installCoreAudioGuard() {
        guard let deviceID = findWaveInputDeviceID() else { return }
        var muteProp = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &muteProp, DispatchQueue.main) { [weak self] _, _ in
            self?.resetCoreAudioMute(deviceID)
        }
        resetCoreAudioMute(deviceID)
    }

    private func findWaveInputDeviceID() -> AudioDeviceID? {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size, &ids)
        for id in ids {
            var nameProp = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameSize: UInt32 = 256
            var name = [CChar](repeating: 0, count: 256)
            AudioObjectGetPropertyData(id, &nameProp, 0, nil, &nameSize, &name)
            guard String(cString: name) == "Insta360 Wave USB" else { continue }
            var muteProp = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(id, &muteProp) {
                return id
            }
        }
        return nil
    }

    private func resetCoreAudioMute(_ deviceID: AudioDeviceID) {
        var muteProp = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var val: UInt32 = 0
        var size: UInt32 = 4
        AudioObjectGetPropertyData(deviceID, &muteProp, 0, nil, &size, &val)
        guard val != 0 else { return } // already unmuted, nothing to do
        var zero: UInt32 = 0
        AudioObjectSetPropertyData(deviceID, &muteProp, 0, nil, size, &zero)
    }

    // MARK: - Change shortcut

    @objc func changeShortcut() {
        if recorderWindowController == nil {
            recorderWindowController = ShortcutRecorderWindowController()
        }
        recorderWindowController?.onShortcutSelected = { [weak self] keyCode, modifiers, display in
            self?.applyNewShortcut(keyCode: keyCode, modifiers: modifiers, display: display)
            self?.recorderWindowController = nil
        }
        recorderWindowController?.onCancelled = { [weak self] in
            self?.recorderWindowController = nil
        }
        recorderWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for char in utf8.prefix(4) {
            result = result << 8 + FourCharCode(char)
        }
        return result
    }
}
