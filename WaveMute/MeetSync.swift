import AppKit
import Carbon
import Foundation

// Syncs the mute state to an active Google Meet call.
//
// Outbound (WaveMute -> Meet):
//   Chrome tab: JS injection via osascript subprocess — no permissions needed.
//   Meet PWA:   CGEvent Cmd+D sent to app_mode_loader — needs Accessibility.
//
// Inbound (Meet -> WaveMute):
//   Polls the mic button aria-label in any meet.google.com Chrome tab every 500ms.
//   This covers both Chrome tabs and the Meet PWA, which appears as a Chrome tab.
//   When the state flips and WaveMute did not cause it, onExternalStateChange fires.
//   A suppression window prevents reacting to our own outbound syncs.

final class MeetSync {
    static let shared = MeetSync()

    /// Fired on the main thread when Meet's mic state changes externally.
    var onExternalStateChange: ((_ muted: Bool) -> Void)?

    private let meetPWABundleID = "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"
    private var hasPromptedForAccessibility = false

    private var pollTimer: Timer?
    private var lastKnownMeetState: Bool? // nil = not in a call
    private var suppressUntil: Date = .distantPast // ignore poll hits after our own sync

    private init() {}

    // MARK: - Launch setup

    func prepareIfNeeded() {
        if isPWARunning(), !AXIsProcessTrusted() {
            hasPromptedForAccessibility = true
            requestAccessibility()
        }
        startPolling()
    }

    // MARK: - Outbound sync (WaveMute -> Meet)

    func sync(muted: Bool) {
        // Suppress the inbound poller briefly so we don't react to our own change.
        suppressUntil = Date(timeIntervalSinceNow: 1.5)
        DispatchQueue.global(qos: .userInitiated).async {
            self.syncChromeTab(muted: muted)
            self.syncPWA()
        }
    }

    // MARK: - Inbound polling (Meet -> WaveMute)

    private func startPolling() {
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.poll()
            }
        }
    }

    private func poll() {
        guard Date() >= suppressUntil else { return }
        DispatchQueue.global(qos: .background).async {
            let state = self.readMeetMuteState()
            DispatchQueue.main.async {
                guard let state else {
                    self.lastKnownMeetState = nil
                    return
                }
                guard state != self.lastKnownMeetState else { return }
                let previous = self.lastKnownMeetState
                self.lastKnownMeetState = state
                // Only fire callback for changes, not the initial read.
                if previous != nil {
                    self.onExternalStateChange?(state)
                }
            }
        }
    }

    /// Returns true=muted, false=unmuted, nil=no Meet tab found.
    private func readMeetMuteState() -> Bool? {
        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with i from 1 to count of tabs in w
                    set t to tab i of w
                    if URL of t contains "meet.google.com" then
                        set js to "(function(){"
                        set js to js & "var off=document.querySelector('button[aria-label*=\\"Turn off microphone\\"]');"
                        set js to js & "var on=document.querySelector('button[aria-label*=\\"Turn on microphone\\"]');"
                        set js to js & "if(off)return 'unmuted';if(on)return 'muted';return 'unknown';})()"
                        return execute t javascript js
                    end if
                end repeat
            end repeat
            return "none"
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "none"
        switch output {
        case "muted": return true
        case "unmuted": return false
        default: return nil
        }
    }

    // MARK: - Chrome tab (JS injection)

    private func syncChromeTab(muted: Bool) {
        let targetLabel = muted ? "Turn off microphone" : "Turn on microphone"
        let js = "(function(){" +
            "var btn=document.querySelector('button[aria-label*=\"\(targetLabel)\"]');" +
            "if(btn){btn.click();return 'clicked';}return 'not_found';})()"
        let escapedJS = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with i from 1 to count of tabs in w
                    set t to tab i of w
                    if URL of t contains "meet.google.com" then
                        execute t javascript "\(escapedJS)"
                    end if
                end repeat
            end repeat
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    // MARK: - Meet PWA (CGEvent Cmd+D)

    private func syncPWA() {
        guard isPWARunning() else { return }
        guard AXIsProcessTrusted() else {
            if !hasPromptedForAccessibility {
                hasPromptedForAccessibility = true
                requestAccessibility()
            }
            return
        }
        let previousApp = NSWorkspace.shared.frontmostApplication
        if let meetApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: meetPWABundleID
        ).first {
            meetApp.activate()
            Thread.sleep(forTimeInterval: 0.15)
            postCmdD()
            Thread.sleep(forTimeInterval: 0.05)
            previousApp?.activate()
        }
    }

    private func isPWARunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: meetPWABundleID).isEmpty
    }

    private func postCmdD() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(0x02), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(0x02), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func requestAccessibility() {
        DispatchQueue.main.async {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(opts as CFDictionary)
        }
    }
}
