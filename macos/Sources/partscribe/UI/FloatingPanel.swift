import AppKit

/// Small always-on-top panel with the menu's core controls, for when the
/// menu-bar icon is out of reach — macOS silently hides status items behind
/// the notch when the menu bar is full. Non-activating, so clicking it never
/// pulls focus away from the meeting app.
@MainActor
final class FloatingPanel {
    private let panel: NSPanel
    private let dot = NSTextField(labelWithString: "●")
    private let stateLabel = NSTextField(labelWithString: "Klar")
    private let warningLabel = NSTextField(labelWithString: "")
    private let transcriptionLabel = NSTextField(labelWithString: "")
    private let toggleButton = NSButton(title: "Start opptak", target: nil, action: nil)
    private let lastButton = NSButton(title: "", target: nil, action: nil)

    var onToggle: (() -> Void)?
    var onOpenLast: (() -> Void)?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Ask the window server to leave the panel out of screen shares.
        // Not every capture path honours this, so treat it as best-effort.
        panel.sharingType = .none

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        panel.contentView = background

        dot.font = .systemFont(ofSize: 11)
        dot.textColor = .tertiaryLabelColor
        stateLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        stateLabel.lineBreakMode = .byTruncatingTail
        stateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for label in [warningLabel, transcriptionLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.isHidden = true
        }

        toggleButton.bezelStyle = .rounded
        toggleButton.controlSize = .small
        toggleButton.target = self
        toggleButton.action = #selector(toggleClicked)

        lastButton.image = NSImage(
            systemSymbolName: "doc.text", accessibilityDescription: "Åpne siste transkript")
        lastButton.imagePosition = .imageOnly
        lastButton.bezelStyle = .rounded
        lastButton.controlSize = .small
        lastButton.toolTip = "Åpne siste transkript"
        lastButton.target = self
        lastButton.action = #selector(lastClicked)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [dot, stateLabel, spacer, toggleButton, lastButton])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY

        let column = NSStackView(views: [row, warningLabel, transcriptionLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            column.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8),
            row.widthAnchor.constraint(equalTo: column.widthAnchor),
            column.widthAnchor.constraint(equalToConstant: 240),
        ])

        // Remember where the user dragged it; first launch puts it top-right,
        // just under the menu bar.
        if !panel.setFrameUsingName("PartScribePanel"), let screen = NSScreen.main {
            fit()
            let visible = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visible.maxX - panel.frame.width - 16,
                    y: visible.maxY - panel.frame.height - 16
                ))
        }
        panel.setFrameAutosaveName("PartScribePanel")
    }

    var isVisible: Bool { panel.isVisible }

    func show(_ visible: Bool) {
        if visible {
            fit()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    /// Mirror of `MenuBarController.update`, in the same words.
    func update(_ display: MenuBarController.Display, signalWarning: Bool = false) {
        switch display {
        case .idle:
            stateLabel.stringValue = "Klar"
            toggleButton.title = "Start opptak"
            dot.textColor = .tertiaryLabelColor
        case .recording(let elapsed):
            stateLabel.stringValue = "tar opp · \(elapsed)"
            toggleButton.title = "Stopp"
            dot.textColor = .systemRed
        case .recovering(let track, let elapsed):
            stateLabel.stringValue = "henter inn igjen \(track) · \(elapsed)"
            toggleButton.title = "Stopp"
            dot.textColor = .systemOrange
        case .degraded(let track, let elapsed):
            stateLabel.stringValue = "mistet \(track) · \(elapsed)"
            toggleButton.title = "Stopp"
            dot.textColor = .systemOrange
        }
        let warn = signalWarning && display != .idle
        warningLabel.stringValue = warn ? "△ systemlyden er stille" : ""
        warningLabel.isHidden = !warn
        fit()
    }

    func updateTranscription(_ text: String?) {
        transcriptionLabel.stringValue = text ?? ""
        transcriptionLabel.isHidden = text == nil
        fit()
    }

    /// Grow or shrink with the optional status lines, keeping the top edge
    /// where the user put it.
    private func fit() {
        guard let content = panel.contentView else { return }
        let size = content.fittingSize
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    @objc private func toggleClicked() { onToggle?() }
    @objc private func lastClicked() { onOpenLast?() }
}
