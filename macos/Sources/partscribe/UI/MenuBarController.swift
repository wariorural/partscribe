import AppKit

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and provides the only persistent control surface for the daemon
/// (since we run as `.accessory` — no dock icon, no main window).
@MainActor
final class MenuBarController {
    /// What the menu communicates about capture. Recovering and degraded are
    /// distinct from healthy recording so a user glancing mid-meeting can see
    /// that something happened; elapsed time stays visible in every recording
    /// state.
    enum Display: Equatable {
        case idle
        case recording(elapsed: String)
        case recovering(track: String, elapsed: String)
        case degraded(track: String, elapsed: String)
    }

    private let statusItem: NSStatusItem
    private let stateLabel: NSMenuItem
    private let warningLabel: NSMenuItem
    private let transcriptionLabel: NSMenuItem
    private let toggleItem: NSMenuItem
    private let norwegianItem: NSMenuItem
    private let englishItem: NSMenuItem
    private let panelItem: NSMenuItem

    var onToggle: (() -> Void)?
    var onSelectEngine: ((String) -> Void)?
    var onOpenFolder: (() -> Void)?
    var onOpenLast: (() -> Void)?
    var onTogglePanel: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        stateLabel = NSMenuItem(title: "Klar", action: nil, keyEquivalent: "")
        stateLabel.isEnabled = false
        menu.addItem(stateLabel)

        warningLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        warningLabel.isEnabled = false
        warningLabel.isHidden = true
        menu.addItem(warningLabel)

        transcriptionLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        transcriptionLabel.isEnabled = false
        transcriptionLabel.isHidden = true
        menu.addItem(transcriptionLabel)

        menu.addItem(.separator())

        toggleItem = NSMenuItem(
            title: "Start opptak",
            action: #selector(toggleClicked),
            keyEquivalent: "r"
        )
        menu.addItem(toggleItem)

        let openFolder = NSMenuItem(
            title: "Åpne opptaksmappe",
            action: #selector(openFolderClicked),
            keyEquivalent: "o"
        )
        menu.addItem(openFolder)

        let openLast = NSMenuItem(
            title: "Åpne siste transkript",
            action: #selector(openLastClicked),
            keyEquivalent: "t"
        )
        menu.addItem(openLast)

        panelItem = NSMenuItem(
            title: "Vis flytende vindu",
            action: #selector(panelClicked),
            keyEquivalent: ""
        )
        menu.addItem(panelItem)

        menu.addItem(.separator())

        // Engine choice applies to the next transcription: the coordinator
        // releases its engine after every queue drain, so nothing reloads
        // mid-job.
        norwegianItem = NSMenuItem(
            title: "Norsk (NB-Whisper)",
            action: #selector(norwegianClicked),
            keyEquivalent: ""
        )
        englishItem = NSMenuItem(
            title: "Engelsk (Parakeet)",
            action: #selector(englishClicked),
            keyEquivalent: ""
        )
        menu.addItem(norwegianItem)
        menu.addItem(englishItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Avslutt PartScribe",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        for item in [toggleItem, openFolder, openLast, panelItem, norwegianItem, englishItem, quit] {
            item.target = self
        }

        statusItem.menu = menu

        if let button = statusItem.button {
            let image = Self.featherImage()
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeft
        }
    }

    /// Reflect capture state in the icon tint and menu item titles. The menu
    /// bar shows only the feather (red while healthy, orange while capture is
    /// recovering or lost); the elapsed counter lives in the menu's state
    /// label. Call once a second while recording and on every status change.
    /// `signalWarning` is a secondary diagnostic (exact digital silence on a
    /// track that is still delivering callbacks) — its own line, never the
    /// same visual state as stopped callbacks.
    func update(_ display: Display, signalWarning: Bool = false) {
        switch display {
        case .idle:
            stateLabel.title = "Klar"
            toggleItem.title = "Start opptak"
            statusItem.button?.contentTintColor = nil
        case .recording(let elapsed):
            stateLabel.title = "● tar opp · \(elapsed)"
            toggleItem.title = "Stopp opptak"
            statusItem.button?.contentTintColor = .systemRed
        case .recovering(let track, let elapsed):
            stateLabel.title = "◐ henter inn igjen \(track) · \(elapsed)"
            toggleItem.title = "Stopp opptak"
            statusItem.button?.contentTintColor = .systemOrange
        case .degraded(let track, let elapsed):
            stateLabel.title = "⚠ mistet \(track) · \(elapsed)"
            toggleItem.title = "Stopp opptak"
            statusItem.button?.contentTintColor = .systemOrange
        }
        let warn = signalWarning && display != .idle
        warningLabel.title = warn ? "△ systemlyden er stille" : ""
        warningLabel.isHidden = !warn
    }

    /// Show transcription progress/failure as a second status line in the
    /// menu; nil hides it. Independent of recording state — a new recording
    /// can run while the last one transcribes.
    func updateTranscription(_ text: String?) {
        transcriptionLabel.title = text ?? ""
        transcriptionLabel.isHidden = text == nil
    }

    /// Tick the engine that the next transcription will use.
    func updateEngine(_ engine: String) {
        norwegianItem.state = engine == "parakeet" ? .off : .on
        englishItem.state = engine == "parakeet" ? .on : .off
    }

    // Inlined Lucide feather SVG. Keeping it in source means the executable
    // has no separate resource bundle to install alongside it — true
    // single-binary.
    private static let featherSVG = """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" \
        viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" \
        stroke-linecap="round" stroke-linejoin="round">\
        <path d="M12.67 19a2 2 0 0 0 1.416-.588l6.154-6.172a6 6 0 0 0-8.49-8.49L5.586 9.914A2 2 0 0 0 5 11.328V18a1 1 0 0 0 1 1z"/>\
        <path d="M16 8 2 22"/>\
        <path d="M17.5 15H9"/>\
        </svg>
        """

    private static func featherImage() -> NSImage? {
        guard let data = featherSVG.data(using: .utf8),
            let image = NSImage(data: data)
        else { return nil }
        // Menu-bar status icons are nominally 18pt tall; size the SVG to match.
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func toggleClicked() { onToggle?() }
    @objc private func openFolderClicked() { onOpenFolder?() }
    func updatePanel(visible: Bool) {
        panelItem.state = visible ? .on : .off
    }

    @objc private func openLastClicked() { onOpenLast?() }
    @objc private func panelClicked() { onTogglePanel?() }
    @objc private func norwegianClicked() { onSelectEngine?("nb-whisper") }
    @objc private func englishClicked() { onSelectEngine?("parakeet") }
    @objc private func quitClicked() { onQuit?() }
}
