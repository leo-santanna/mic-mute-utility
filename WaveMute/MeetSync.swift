import AppKit
import Carbon
import Foundation

// Syncs the mute state to an active Google Meet call.
//
// Two paths are attempted independently:
//
// 1. Chrome tab (no permissions needed)
//    Finds a meet.google.com tab in Google Chrome via AppleScript and clicks
//    the mic button by injecting JavaScript.
//
// 2. Meet PWA (requires Accessibility permission)
//    Detects the Meet PWA process (app_mode_loader), briefly activates it,
//    sends Cmd+D (Meet's official mic toggle shortcut), then restores focus
//    to the previously active app.
//
// If neither surface is running the call is a no-op.
// Errors are silently discarded so a missing Meet session never interrupts muting.

final class MeetSync {
    static let shared = MeetSync()

    private let meetPWABundleID = "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"
    private var hasPromptedForAccessibility = false

    private init() {}

    /// Call once at app launch. If the Meet PWA is already running and we don't
    /// have Accessibility permission yet, prompt now rather than mid-mute-press.
    func prepareIfNeeded() {
        guard isPWARunning(), !AXIsProcessTrusted() else { return }
        hasPromptedForAccessibility = true
        requestAccessibility()
    }

    func sync(muted: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.syncChromeTab(muted: muted)
            self.syncPWA()
        }
    }

    // MARK: - Chrome tab (JS injection)

    private func syncChromeTab(muted: Bool) {
        guard let script = buildChromeScript(muted: muted) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    private func buildChromeScript(muted: Bool) -> String? {
        // aria-label flips with state: match by the action label, not current state.
        let targetLabel = muted ? "Turn off microphone" : "Turn on microphone"
        let js = """
        (function() {
            var btn = document.querySelector('button[aria-label*="\(targetLabel)"]');
            if (btn) { btn.click(); return 'clicked'; }
            return 'not_found';
        })()
        """
        let escapedJS = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
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
    }

    // MARK: - Meet PWA (CGEvent Cmd+D)

    private func syncPWA() {
        guard isPWARunning() else { return }
        guard AXIsProcessTrusted() else {
            // Only show the system permission prompt once per app launch.
            // Subsequent F9 presses while permission is missing are silent no-ops.
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
