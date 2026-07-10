import Foundation

enum LaunchAtLogin {
    private static let plistPath = (
        NSHomeDirectory() + "/Library/LaunchAgents/com.local.WaveMute.plist"
    )

    private static var executablePath: String {
        Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
    }

    static var isEnabled: Bool {
        get { FileManager.default.fileExists(atPath: plistPath) }
        set { newValue ? install() : uninstall() }
    }

    private static func install() {
        let plist: [String: Any] = [
            "Label": "com.local.WaveMute",
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]
        let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try? data?.write(to: URL(fileURLWithPath: plistPath))

        // Tell launchd to load it immediately (so it's active without a reboot)
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", plistPath]
        try? task.run()
        task.waitUntilExit()
    }

    private static func uninstall() {
        // Unload from launchd first
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistPath]
        try? task.run()
        task.waitUntilExit()

        try? FileManager.default.removeItem(atPath: plistPath)
    }
}
