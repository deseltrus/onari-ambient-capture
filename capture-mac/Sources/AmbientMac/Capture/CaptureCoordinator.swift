import AppKit
import Foundation

/// Wires blocks A–C together: probe → chain → publisher, plus the note path.
/// Everything else in the app is UI around this object.
@MainActor
public final class CaptureCoordinator {
    public struct Status {
        public var trusted = false
        public var micGranted = false
        public var publishing = true
        public var switchCount = 0
        public var noteCount = 0
        public var currentBoard: String?
        public var recording = false
        public var transcribing = false
        /// Seconds the current recording has been running, for the menu-bar clock.
        public var recordingElapsed: TimeInterval = 0
        /// e.g. "⌃⌥⌘N" — shown everywhere so the binding is never a mystery.
        public var hotKeyDisplay = HotKey.Combo.default.display
        public var hotKeyRegistered = true
        /// Set when a note is captured, so the UI can confirm what it heard.
        public var lastNoteText: String?
    }

    private let probe = ActiveWindowProbe()
    private let chain: SwitchChain
    private let publisher: EventPublisher
    private let hotKey = HotKey()
    private let recorder = MicNoteRecorder()

    private var pollTimer: Timer?
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?

    /// The board and moment the note STARTED on. A thought belongs to the
    /// surface you were looking at when you began speaking, not the one you
    /// drifted to mid-sentence — and people do drift, which is the whole
    /// premise of the product. Captured at begin, used at end.
    private var pendingNoteTarget: SurfaceSample?
    private var pendingNoteStamp: String?

    /// A recording nobody stopped is a recording that eats the demo. Cap it.
    private let maximumNoteDuration: TimeInterval = 90

    public private(set) var status = Status()
    public var onStatusChange: ((Status) -> Void)?

    /// 400 ms: fast enough that a two-second glance is captured with a
    /// believable dwell, slow enough to be invisible on the CPU graph.
    private let pollInterval: TimeInterval

    public init(
        pollInterval: TimeInterval = 0.4,
        minimumDwell: TimeInterval = 0.75,
        publisher: EventPublisher = EventPublisher()
    ) {
        self.pollInterval = pollInterval
        self.chain = SwitchChain(minimumDwell: minimumDwell)
        self.publisher = publisher
    }

    // MARK: - Lifecycle

    public func start() {
        publisher.onStatusChange = { [weak self] ok, _ in
            Task { @MainActor in
                guard let self else { return }
                if self.status.publishing != ok {
                    Log.line(ok ? "bridge: reconnected" : "bridge: UNREACHABLE — events are spooling to disk")
                }
                self.status.publishing = ok
                self.emit()
            }
        }

        status.trusted = probe.isTrusted
        if !status.trusted {
            // Prompts once. The app keeps running either way — app-level
            // switches still flow, only window titles are missing.
            probe.requestTrust()
        }

        MicNoteRecorder.requestPermissions { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.status.micGranted = granted
                Log.line(granted
                    ? "microphone + speech: granted"
                    : "microphone or speech: DENIED — voice notes will not work")
                self.emit()
            }
        }

        recorder.onStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.status.recording = (state == .recording)
                self.status.transcribing = (state == .transcribing)
                self.emit()
            }
        }

        hotKey.onPress = { [weak self] in
            Task { @MainActor in self?.toggleNote() }
        }
        let registered = hotKey.register()
        status.hotKeyDisplay = hotKey.combo.display
        status.hotKeyRegistered = registered
        if !registered {
            let message = "capture: could not register \(hotKey.combo.display) — "
                + "another app owns it. Set ONARI_HOTKEY, e.g. ONARI_HOTKEY=ctrl+opt+cmd+j"
            Log.line(message)
        }

        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Keep sampling while menus are open; otherwise the chain goes blind
        // exactly when the user is switching apps.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        Log.banner([
            "  ONARI ambient capture — running",
            "",
            "  Voice note:   press \(status.hotKeyDisplay)  (press again to stop)",
            "  Accessibility: \(status.trusted ? "granted" : "MISSING — window titles will be app names")",
            "  Hotkey:        \(registered ? "registered" : "NOT REGISTERED — another app owns it")",
            "",
            "  Everything below is live. This terminal is the indicator —",
            "  the menu-bar icon can be hidden under the notch on a MacBook Pro.",
        ])

        tick()
        emit()
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        hotKey.unregister()
        publisher.drain()
        Log.line("stopped · \(status.switchCount) switches · \(status.noteCount) notes")
    }

    // MARK: - Switch chain

    private func tick() {
        let wasTrusted = status.trusted
        status.trusted = probe.isTrusted
        if !wasTrusted && status.trusted {
            Log.line("accessibility: granted — window titles are live now")
        }

        let sample = probe.sample()
        if let event = chain.observe(sample, at: Date()) {
            publisher.publish(.switchEvent(event))
            status.switchCount += 1
            status.currentBoard = "\(event.to.app ?? "?") — \(event.to.title ?? "?")"

            let dwell = event.dwellMsFrom.map { String(format: " (held %.1fs)", Double($0) / 1000) } ?? ""
            let origin = event.from.app ?? "∅"
            Log.line("switch #\(event.seq)  \(origin) → \(event.to.app ?? "?") · \(event.to.title ?? "?")\(dwell)")

            emit()
        }
    }

    // MARK: - Notes

    /// Press once to start, press again to stop. Toggle beats hold-to-speak:
    /// a three-modifier chord is uncomfortable to hold, and holding gives no
    /// way to tell whether the thing is actually armed.
    public func toggleNote() {
        if status.recording {
            endNote()
        } else {
            beginNote()
        }
    }

    public func beginNote() {
        guard !status.recording, !status.transcribing else { return }
        guard let target = chain.noteTarget else {
            Log.line("note: no board yet — switch to a window first")
            return
        }

        recorder.start()
        recordingStartedAt = Date()
        pendingNoteTarget = target
        pendingNoteStamp = Contract.stamp(Date())

        // Audible confirmation. With no visible overlay, sound is the only cue
        // that reliably reaches the user mid-sentence.
        NSSound(named: "Tink")?.play()
        Log.line("● RECORDING — speak now, press \(status.hotKeyDisplay) again to stop  [\(target.app)]")

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let started = self.recordingStartedAt else { return }
                let elapsed = Date().timeIntervalSince(started)
                self.status.recordingElapsed = elapsed

                // Echo the running transcript. "Is it hearing me?" has to be
                // answerable WHILE speaking, not after stopping — a silent
                // counter proves the timer works, not the microphone.
                let heard = self.recorder.liveHypothesis
                if let heard, !heard.isEmpty {
                    Log.line("  ● \(Int(elapsed))s  \"\(heard)\"")
                } else {
                    Log.line("  ● \(Int(elapsed))s  (no speech detected yet)")
                }
                self.emit()

                if elapsed >= self.maximumNoteDuration {
                    Log.line("  ● hit the \(Int(self.maximumNoteDuration))s cap — stopping automatically")
                    self.endNote()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        recordingTimer = timer
    }

    public func endNote() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        let held = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil
        status.recordingElapsed = 0
        NSSound(named: "Pop")?.play()
        Log.line(String(format: "■ stopped after %.1fs — transcribing…", held))

        // The board captured at BEGIN, not the one we are on now. Between
        // starting and stopping a note the user may have switched surfaces
        // several times; binding to the current board would file the thought
        // under whatever window happened to be frontmost when they stopped.
        let target = pendingNoteTarget ?? chain.noteTarget
        let stamp = pendingNoteStamp ?? Contract.stamp(Date())
        pendingNoteTarget = nil
        pendingNoteStamp = nil

        recorder.stop { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                guard let text, !text.isEmpty, let target else {
                    self.status.lastNoteText = "(nothing heard)"
                    Log.line("note: nothing intelligible — no event published")
                    self.emit()
                    return
                }

                let note = NoteEvent(
                    t: stamp,
                    boardID: target.boardID,
                    app: target.app,
                    title: target.title,
                    text: text,
                    mode: .note,
                    field: nil
                )
                self.publisher.publish(.note(note))
                self.status.noteCount += 1
                self.status.lastNoteText = text
                Log.line("🎙 note on [\(target.app) · \(target.title)]: \"\(text)\"")
                self.emit()
            }
        }
    }

    // MARK: - Manual injection (demo safety net)

    /// Publish a note without speaking it. If the mic misbehaves on stage, the
    /// demo still runs: the wander script's note texts fire from the menu.
    /// Not a hack — a rehearsed fallback.
    public func injectNote(_ text: String) {
        guard let target = chain.noteTarget else { return }
        let note = NoteEvent(
            t: Contract.stamp(Date()),
            boardID: target.boardID,
            app: target.app,
            title: target.title,
            text: text,
            mode: .note,
            field: nil
        )
        publisher.publish(.note(note))
        status.noteCount += 1
        status.lastNoteText = text
        Log.line("⌨ injected note on [\(target.app)]: \"\(text)\"")
        emit()
    }

    private func emit() { onStatusChange?(status) }
}
