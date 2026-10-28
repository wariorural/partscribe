import AppKit
import ArgumentParser
import Foundation

@main
struct PartScribe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "partscribe",
        abstract: "Local meeting recorder + transcriber. Records mic and system audio as two tracks, then transcribes on-device.",
        subcommands: [Run.self, Doctor.self, Install.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the menu-bar daemon (default)."
    )

    @Option(name: .long, help: "Recordings root directory (overrides the config file).")
    var out: String?

    func run() throws {
        // ArgumentParser invokes run() on the main thread; promote that fact
        // to the type system so AppKit calls are cleanly isolated.
        try MainActor.assumeIsolated { try runMain() }
    }

    @MainActor
    private func runMain() throws {
        let root = Config.resolveRoot(cliOverride: out)

        // Non-blocking: permissions prompt on first recording, so warnings at
        // startup are informational, not fatal.
        let checks = DoctorReport.run(recordingsRoot: root)
        if !DoctorReport.allOK(checks) {
            FileHandle.standardError.write(Data("startup checks failed:\n".utf8))
            DoctorReport.print(checks)
            throw ExitCode(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let controller = AppController(root: root)

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            MainActor.assumeIsolated { controller.shutdown() }
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        FileHandle.standardError.write(
            Data(
                "partscribe up · recordings → \(root.path) · ^C to quit\n".utf8
            ))
        app.run()
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, system audio, and recordings folder."
    )

    func run() throws {
        let checks = DoctorReport.run(recordingsRoot: Config.resolveRoot(cliOverride: nil))
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

/// Owns the menu bar, the current recording session, and the elapsed-time
/// ticker. All state transitions happen on the main actor.
@MainActor
final class AppController {
    private let root: URL
    private let menuBar = MenuBarController()
    private let panel = FloatingPanel()
    private let transcription = TranscriptionCoordinator()
    private var session: RecordingSession?
    private var captureStatus = RecordingSession.CaptureStatus.allHealthy
    private var ticker: Timer?

    init(root: URL) {
        self.root = root
        menuBar.onToggle = { [weak self] in self?.toggle() }
        menuBar.onOpenFolder = { [weak self] in self?.openFolder() }
        menuBar.onQuit = { [weak self] in self?.shutdown() }
        menuBar.onSelectEngine = { [weak self] in self?.selectEngine($0) }
        menuBar.onOpenLast = { [weak self] in self?.openLastTranscript() }
        menuBar.onTogglePanel = { [weak self] in self?.togglePanel() }
        panel.onToggle = { [weak self] in self?.toggle() }
        panel.onOpenLast = { [weak self] in self?.openLastTranscript() }
        show(.idle)
        menuBar.updateEngine(Config.transcriptionEngine())
        panel.show(Config.floatingWindow())
        menuBar.updatePanel(visible: panel.isVisible)

        Task { [transcription, root] in
            await transcription.setStatusHandler { status in
                Task { @MainActor [weak self] in
                    self?.showTranscription(status)
                }
            }
            await transcription.resumePending(root: root)
        }
    }

    /// Stop any live session cleanly (finalizing files) and exit.
    func shutdown() {
        stopSession()
        NSApp.terminate(nil)
    }

    private func toggle() {
        if session == nil {
            startSession()
        } else {
            stopSession()
        }
    }

    private func startSession() {
        do {
            let newSession = try RecordingSession(root: root)
            newSession.onStatus = { [weak self] status in
                self?.captureStatus = status
                self?.refreshMenu()
            }
            newSession.onDegraded = { kind in
                // The session fires this once per degradation episode, so the
                // user gets one notification, not one per watchdog tick.
                notifyUser(
                    title: "PartScribe — mistet \(Self.spoken(kind))",
                    body: "Fikk det ikke tilbake. Opptaket blir merket som ufullstendig."
                )
            }
            try newSession.start()
            session = newSession
            captureStatus = .allHealthy
            FileHandle.standardError.write(Data("● recording → \(newSession.dir.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("recording start failed: \(error)\n".utf8))
            notifyUser(title: "PartScribe — opptaket startet ikke", body: "\(error)")
            return
        }

        refreshMenu()
        // Explicitly .common so the elapsed counter and menu state keep
        // updating while the menu is open (event-tracking run-loop mode).
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopSession() {
        guard let session else { return }
        let result = session.stop()
        let elapsed = Self.format(Date().timeIntervalSince(session.startedAt))
        FileHandle.standardError.write(
            Data(
                "○ stopped · \(elapsed) · \(result.status.rawValue) · \(session.dir.path)\n".utf8
            ))
        self.session = nil
        captureStatus = .allHealthy
        ticker?.invalidate()
        ticker = nil
        show(.idle)

        // Warn about a gap before the later "transcript ready" notification
        // implies everything went fine. Transcription still runs — recovered
        // and incomplete sessions keep whatever audio they have.
        switch result.status {
        case .complete:
            break
        case .recovered:
            notifyUser(
                title: "PartScribe — opptaket ble reddet",
                body: "Opptaket ble avbrutt og tok seg opp igjen. Hullet står i meta.json."
            )
        case .incomplete:
            notifyUser(
                title: "PartScribe — opptaket er ufullstendig",
                body: "En del av møtet ble ikke tatt opp. Se meta.json."
            )
        }
        let dir = session.dir
        Task { [transcription] in await transcription.enqueue(dir) }
    }

    /// Rebuild the menu presentation from capture status plus elapsed time.
    private func refreshMenu() {
        guard let session else { return }
        let elapsed = Self.format(Date().timeIntervalSince(session.startedAt))
        let display: MenuBarController.Display
        switch captureStatus.display {
        case .healthy:
            display = .recording(elapsed: elapsed)
        case .recovering(let kind):
            display = .recovering(track: Self.spoken(kind), elapsed: elapsed)
        case .degraded(let kind):
            display = .degraded(track: Self.spoken(kind), elapsed: elapsed)
        }
        show(display, signalWarning: captureStatus.signalWarning)
    }

    /// Menu and floating panel always show the same state.
    private func show(_ display: MenuBarController.Display, signalWarning: Bool = false) {
        menuBar.update(display, signalWarning: signalWarning)
        panel.update(display, signalWarning: signalWarning)
    }

    private func showTranscription(_ status: TranscriptionCoordinator.Status) {
        let text: String?
        switch status {
        case .idle:
            text = nil
        case .transcribing(let name, let queued):
            text = queued > 0 ? "transkriberer \(name) · \(queued) i kø" : "transkriberer \(name)"
        case .failed(let name):
            text = "transkripsjonen feilet · \(name)"
        }
        menuBar.updateTranscription(text)
        panel.updateTranscription(text)
    }

    private func tick() {
        refreshMenu()
    }

    private func selectEngine(_ engine: String) {
        do {
            try Config.setTranscriptionEngine(engine)
        } catch {
            FileHandle.standardError.write(Data("engine switch failed: \(error)\n".utf8))
            notifyUser(title: "PartScribe — fikk ikke byttet språk", body: "\(error)")
        }
        // Re-read rather than trust the click, so the tick shows what the
        // next transcription will actually use.
        menuBar.updateEngine(Config.transcriptionEngine())
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    /// Session folders are named by start time, so the newest transcript is
    /// the last name in sort order that has one. Falls back to the folder.
    private func openLastTranscript() {
        let fm = FileManager.default
        let latest = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .map { $0.appendingPathComponent("transcript.md") }
            .filter { fm.fileExists(atPath: $0.path) }
            .max { $0.deletingLastPathComponent().lastPathComponent < $1.deletingLastPathComponent().lastPathComponent }
        if let latest {
            NSWorkspace.shared.open(latest)
        } else {
            openFolder()
        }
    }

    private func togglePanel() {
        let visible = !panel.isVisible
        panel.show(visible)
        menuBar.updatePanel(visible: visible)
        do {
            try Config.setFloatingWindow(visible)
        } catch {
            FileHandle.standardError.write(Data("panel setting not saved: \(error)\n".utf8))
        }
    }

    /// Track names for the Norwegian menu and notifications. `kind.label`
    /// stays English because it also goes to the stderr log.
    private static func spoken(_ kind: TrackKind) -> String {
        kind == .mic ? "mikrofonen" : "systemlyden"
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
