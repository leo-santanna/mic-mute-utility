import AppKit
import Foundation

// Syncs the mute state to an active Google Meet call.
//
// Outbound (WaveMute -> Meet):
//   Both Chrome tabs and the Meet PWA are targeted via osascript subprocesses.
//   Chrome tab: JS injection clicks the mic button by aria-label.
//   Meet PWA:   osascript activates the PWA and sends Cmd+D via System Events.
//   Using osascript for both paths means NO Accessibility permission is required
//   from the app binary — osascript is a system binary with its own TCC grants.
//
// Inbound (Meet -> WaveMute):
//   Polls the mic button aria-label in any meet.google.com Chrome tab every 500ms.
//   This covers both Chrome tabs and the PWA (which appears as a Chrome tab).
//   A suppression window prevents reacting to our own outbound syncs.

final class MeetSync {
    static let shared = MeetSync()

    var onExternalStateChange: ((_ muted: Bool) -> Void)?

    private let meetPWABundleID = "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"

    private var pollTimer: Timer?
    private var lastKnownMeetState: Bool?
    private var suppressUntil: Date = .distantPast

    private init() {}

    func prepareIfNeeded() {
        startPolling()
    }

    // MARK: - Outbound sync (WaveMute -> Meet)

    func sync(muted: Bool) {
        suppressUntil = Date(timeIntervalSinceNow: 1.5)
        DispatchQueue.global(qos: .userInitiated).async {
            self.syncChromeTab(muted: muted)
            self.syncPWA(muted: muted)
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
                if previous != nil {
                    self.onExternalStateChange?(state)
                }
            }
        }
    }

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
        let output = runOsascript(script)
        switch output {
        case "muted": return true
        case "unmuted": return false
        default: return nil
        }
    }

    // MARK: - Chrome tab (JS injection)

    private func syncChromeTab(muted: Bool) {
        let targetLabel = muted ? "Turn off microphone" : "Turn on microphone"
        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with i from 1 to count of tabs in w
                    set t to tab i of w
                    if URL of t contains "meet.google.com" then
                        set js to "(function(){"
                        set js to js & "var btn=document.querySelector('button[aria-label*=\\"\(targetLabel)\\"]');"
                        set js to js & "if(btn){btn.click();return 'clicked';}return 'not_found';})()"
                        execute t javascript js
                    end if
                end repeat
            end repeat
        end tell
        """
        runOsascript(script, wait: false)
    }

    // MARK: - Meet PWA (osascript keystroke — no Accessibility permission needed)

    private func syncPWA(muted _: Bool) {
        guard isPWARunning() else { return }
        // Check if the Chrome tab path already covers the PWA.
        // The PWA appears as a Chrome tab, so if a meet.google.com tab was found
        // by syncChromeTab, the PWA is already handled. Send Cmd+D only when there
        // is no Chrome meet tab (i.e. the PWA is the sole Meet surface).
        guard !hasChromeMeetTab() else { return }
        let script = """
        tell application "Google Meet"
            activate
        end tell
        delay 0.15
        tell application "System Events"
            tell process "app_mode_loader"
                keystroke "d" using command down
            end tell
        end tell
        """
        runOsascript(script, wait: false)
    }

    private func isPWARunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: meetPWABundleID).isEmpty
    }

    private func hasChromeMeetTab() -> Bool {
        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with i from 1 to count of tabs in w
                    if URL of tab i of w contains "meet.google.com" then
                        return "yes"
                    end if
                end repeat
            end repeat
            return "no"
        end tell
        """
        return runOsascript(script) == "yes"
    }

    // MARK: - Helpers

    @discardableResult
    private func runOsascript(_ script: String, wait: Bool = true) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return "" }
        if wait {
            task.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return ""
    }
}
