import Foundation

// Syncs the mute state to an active Google Meet call running in Chrome.
//
// Approach: AppleScript JS injection into the Meet tab.
// - No Accessibility permission required.
// - Works regardless of which window/app is currently focused.
// - Finds the Meet tab by URL, then clicks the mic toggle button via JS.
//
// Meet's mute button is identified by the aria-label attribute, which is
// the most stable public selector. The button text reads "Turn off microphone"
// when unmuted and "Turn on microphone" when muted, so we match by state
// rather than a hardcoded label string.
//
// Known limitation: only works when Meet is open in Google Chrome (not Firefox
// or Safari, which don't expose AppleScript JS execution).

final class MeetSync {
    static let shared = MeetSync()

    private init() {}

    // Called after every mute toggle. Finds the Meet tab and syncs the state.
    func sync(muted: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.applySyncToChrome(muted: muted)
        }
    }

    // MARK: - Private

    private func applySyncToChrome(muted: Bool) {
        guard let script = buildScript(muted: muted) else { return }
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let err = error {
            // Non-fatal: Meet may not be open, or Chrome may not be running.
            _ = err  // suppress unused warning; callers don't need to know
        }
    }

    // Builds an AppleScript that:
    // 1. Finds all Chrome tabs whose URL contains meet.google.com
    // 2. On each matching tab, runs JS to click the mic button if it's in
    //    the wrong state relative to `muted`.
    private func buildScript(muted: Bool) -> String? {
        // The JS to run inside the Meet tab.
        // Meet renders the mic button with aria-label that changes with state:
        //   "Turn off microphone" = currently unmuted
        //   "Turn on microphone"  = currently muted
        // We click whichever matches the desired transition.
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
            set meetResult to "no_tab"
            repeat with w in windows
                repeat with i from 1 to count of tabs in w
                    set t to tab i of w
                    if URL of t contains "meet.google.com" then
                        set meetResult to execute t javascript "\(escapedJS)"
                    end if
                end repeat
            end repeat
            return meetResult
        end tell
        """
    }
}
