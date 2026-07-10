import Foundation

// Keeps the Wave USB HID device open permanently on a background thread.
// - Sends Report 6 to mute/unmute and LED.
// - Reads incoming vendor heartbeat (Report ID 3, type 0xEF) and watches byte[29]
//   which reflects the device's actual mute state. When it changes (physical button),
//   onStateChanged is called with the new mute value.
final class HIDMonitor {
    var onStateChanged: ((_ muted: Bool) -> Void)?

    private var thread: Thread?
    private var running = false
    private var pendingMute: Bool?       // set from main thread, consumed by loop
    private let lock = NSLock()

    private let libPath: String = {
        let bundlePath = (Bundle.main.privateFrameworksPath ?? "") + "/libhidapi.dylib"
        return FileManager.default.fileExists(atPath: bundlePath)
            ? bundlePath
            : "/opt/homebrew/lib/libhidapi.dylib"
    }()

    func start() {
        running = true
        let thread = Thread { [weak self] in self?.loop() }
        thread.name = "HIDMonitor"
        thread.qualityOfService = .utility
        thread.start()
        self.thread = thread
    }

    func stop() {
        running = false
    }

    // Called from main thread; will be picked up by the loop on next iteration.
    func sendMute(_ muted: Bool) {
        lock.lock()
        pendingMute = muted
        lock.unlock()
    }

    // MARK: - Background loop

    private func loop() {
        guard let hidapi = dlopen(libPath, RTLD_NOW) else { return }
        defer { dlclose(hidapi) }

        typealias OpenFn  = @convention(c) (UInt16, UInt16, UnsafePointer<Int32>?) -> UnsafeMutableRawPointer?
        typealias ReadFn  = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>, Int, Int32) -> Int32
        typealias WriteFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>, Int) -> Int32
        typealias CloseFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

        guard
            let openSym  = dlsym(hidapi, "hid_open"),
            let readSym  = dlsym(hidapi, "hid_read_timeout"),
            let writeSym = dlsym(hidapi, "hid_write"),
            let closeSym = dlsym(hidapi, "hid_close")
        else { return }

        let hidOpen  = unsafeBitCast(openSym, to: OpenFn.self)
        let hidRead  = unsafeBitCast(readSym, to: ReadFn.self)
        let hidWrite = unsafeBitCast(writeSym, to: WriteFn.self)
        let hidClose = unsafeBitCast(closeSym, to: CloseFn.self)

        guard let dev = hidOpen(0x18F0, 0x4E40, nil) else { return }
        defer { hidClose(dev) }

        var buf = [UInt8](repeating: 0, count: 64)
        var lastMuteState: Bool?
        // After we send a write, suppress heartbeat-driven state changes for this many
        // milliseconds to give the device time to update byte[29] consistently.
        var suppressUntil: Date = .distantPast

        while running {
            // Check for a pending mute command from the main thread
            lock.lock()
            let pending = pendingMute
            pendingMute = nil
            lock.unlock()

            if let muted = pending {
                var report: [UInt8] = [0x06, muted ? 0x01 : 0x00]
                _ = hidWrite(dev, &report, 2)
                lastMuteState = muted
                suppressUntil = Date(timeIntervalSinceNow: 0.4)
            }

            // Read next report with a short timeout so we stay responsive
            let readCount = hidRead(dev, &buf, 64, 100)
            guard readCount > 0 else { continue }

            // Only care about vendor heartbeat: Report ID 3, type 0xEF
            guard buf[0] == 0x03, buf[1] == 0xEF else { continue }

            // Skip if we just issued a write and the device hasn't settled yet
            guard Date() >= suppressUntil else { continue }

            // byte[29] = 0x01 muted, 0x00 unmuted
            let deviceMuted = buf[29] != 0x00

            if deviceMuted != lastMuteState {
                lastMuteState = deviceMuted
                DispatchQueue.main.async { [weak self] in
                    self?.onStateChanged?(deviceMuted)
                }
            }
        }
    }
}
