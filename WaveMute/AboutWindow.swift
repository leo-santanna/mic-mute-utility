import Cocoa

final class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About WaveMute"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let view = window?.contentView else { return }
        let iconView = makeIconView()
        let nameLabel = makeLabel("WaveMute", size: 18, bold: true)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let versionLabel = makeLabel("Version \(version)", size: 12, color: .secondaryLabelColor)
        let descLabel = NSTextField(wrappingLabelWithString:
            "A lightweight menu bar utility to control your Insta360 Wave USB microphone with a global hotkey, LED sync, and Google Meet integration.")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        let githubButton = makeButton("View on GitHub", action: #selector(openGitHub))
        let coffeeButton = makeButton("Buy Me a Coffee", action: #selector(openBuyMeACoffee))
        [iconView, nameLabel, versionLabel, descLabel, githubButton, coffeeButton].forEach { view.addSubview($0) }
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            versionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            versionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            descLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 14),
            descLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            descLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            githubButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            githubButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -6),
            coffeeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            coffeeButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 6),
        ])
    }

    private func makeIconView() -> NSImageView {
        let view = NSImageView()
        view.image = NSApp.applicationIconImage
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func makeLabel(_ text: String, size: CGFloat, bold: Bool = false, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.textColor = color
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/leo-santanna/mic-mute-utility")!)
    }

    @objc private func openBuyMeACoffee() {
        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/leonardoebs")!)
    }
}
