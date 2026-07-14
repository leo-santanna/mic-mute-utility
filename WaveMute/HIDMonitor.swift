import Foundation

/// Keeps the Wave USB HID device open permanently on a background thread.
/// - Sends Report 6 to mute/unmute and LED.
/// - Reads incoming vendor heartbeat (Report ID 3, type 0xEF) and watches byte[29]
///   which reflects the device's actual mute state. When it changes (physical button),
///   onStateChanged is called with the new mute value.
/// - Automatically reconnects after USB re-enumeration (e.g. logout/login cycle).
final class HIDMonitor {
    var onStateChanged: ((_ muted: Bool) -> Void)?

    private var thread: Thread?
    private var running = false
    private var pendingMute: Bool? // set from main thread, consumed by loop
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

    /// Called from main thread; will be picked up by the loop on next iteration.
    func sendMute(_ muted: Bool) {
        lock.lock()
        pendingMute = muted
        lock.unlock()
    }

    // MARK: - Background loop

    private func loop() {
        guard let hidapi = dlopen(libPath, RTLD_NOW) else { return }
        defer { dlclose(hidapi) }

        typealias OpenFn = @convention(c) (UInt16, UInt16, UnsafePointer<Int32>?) -> UnsafeMutableRawPointer?
        typealias ReadFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>, Int, Int32) -> Int32
        typealias WriteFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>, Int) -> Int32
        typealias CloseFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

        guard
            let openSym = dlsym(hidapi, "hid_open"),
            let readSym = dlsym(hidapi, "hid_read_timeout"),
            let writeSym = dlsym(hidapi, "hid_write"),
            let closeSym = dlsym(hidapi, "hid_close")
        else { return }

        let hidOpen = unsafeBitCast(openSym, to: OpenFn.self)
        let hidRead = unsafeBitCast(readSym, to: ReadFn.self)
        let hidWrite = unsafeBitCast(writeSym, to: WriteFn.self)
        let hidClose = unsafeBitCast(closeSym, to: CloseFn.self)

        while running {
            // Open (or reopen after disconnect)
            guard let dev = hidOpen(0x18F0, 0x4E40, nil) else {
                // Device not available yet — wait and retry
                Thread.sleep(forTimeInterval: 2.0)
                continue
            }

            runSession(dev: dev, hidRead: hidRead, hidWrite: hidWrite, hidClose: hidClose)
            // runSession returned — device was lost. Close and loop back to reopen.
            hidClose(dev)

            if running {
                // Brief pause before reconnect attempt so we don't spin on rapid failures
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }

    /// Runs the read/write loop for a single open device handle.
    /// Returns when the device becomes unresponsive (consecutive empty reads),
    /// signalling the caller to close and reopen.
    private func runSession(
        dev: UnsafeMutableRawPointer,
        hidRead: (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>, Int, Int32) -> Int32,
        hidWrite: (UnsafeMutableRawPointer?, UnsafePointer<UInt8>, Int) -> Int32,
        hidClose _: (UnsafeMutableRawPointer?) -> Void
    ) {
        var buf = [UInt8](repeating: 0, count: 64)
        var lastMuteState: Bool?
        var suppressUntil: Date = .distantPast
        var emptyReadStreak = 0
        // After ~5 seconds of silence the device is considered lost
        let maxEmptyReads = 50

        while running {
            lock.lock()
            let pending = pendingMute
            pendingMute = nil
            lock.unlock()

            if let muted = pending {
                var report: [UInt8] = [0x06, muted ? 0x01 : 0x00]
                let written = hidWrite(dev, &report, 2)
                if written > 0 {
                    lastMuteState = muted
                    suppressUntil = Date(timeIntervalSinceNow: 0.4)
                    emptyReadStreak = 0
                }
            }

            let readCount = hidRead(dev, &buf, 64, 100)

            if readCount < 0 {
                // Hard error — device disconnected
                return
            }

            if readCount == 0 {
                emptyReadStreak += 1
                if emptyReadStreak >= maxEmptyReads {
                    // Device stopped sending heartbeats — treat as disconnected
                    return
                }
                continue
            }

            emptyReadStreak = 0

            guard buf[0] == 0x03, buf[1] == 0xEF else { continue }
            guard Date() >= suppressUntil else { continue }

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
