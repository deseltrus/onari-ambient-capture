import AppKit
import SwiftUI

/// Menu-bar capture shell. No Dock icon, no standing overlay — per the doc the
/// only permanent pixel is the state dot, which doubles as the honesty
/// indicator: if it is not green, we are not capturing, and the room sees that.
///
///   ◉          capturing, publishing, accessibility granted
///   ◎          capturing but degraded (no AX trust, or the bridge is down)
///   ● REC 0:04 recording a note, with a running clock
///   ⋯          transcribing
@main
struct AmbientMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// @MainActor on the whole delegate, not on individual methods: `CaptureCoordinator`
/// is main-actor isolated, and every `@objc` selector target here reaches into it.
/// Without this the selector methods are nonisolated and the calls are errors even
/// in Swift 5 language mode — actor-isolation violations were never downgraded to
/// warnings, only Sendable checking was.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var coordinator: CaptureCoordinator?

    private enum Tag {
        static let record = 99
        static let counts = 100
        static let board = 101
        static let health = 102
        static let lastNote = 103
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Text, not a bare glyph. A single "◎" is nearly impossible to find in
        // a crowded menu bar, and macOS gives no signal when an item is pushed
        // under the notch and hidden. The word makes it findable when visible;
        // the terminal log covers the case where it is not.
        item.button?.title = "◎ onari"
        item.menu = buildMenu()
        statusItem = item

        if item.button == nil {
            Log.line("menu bar: could not create a status item — use the terminal log instead")
        }

        let coordinator = CaptureCoordinator()
        coordinator.onStatusChange = { [weak self] status in
            self?.render(status)
        }
        coordinator.start()
        self.coordinator = coordinator
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    // MARK: - UI

    private func render(_ status: CaptureCoordinator.Status) {
        guard let button = statusItem?.button else { return }

        if status.recording {
            // Loud on purpose. A single glyph is not enough feedback for
            // "am I being recorded right now" — the clock proves it is live.
            let seconds = Int(status.recordingElapsed)
            button.title = String(format: "● REC %d:%02d", seconds / 60, seconds % 60)
        } else if status.transcribing {
            button.title = "⋯ onari"
        } else if status.trusted && status.publishing {
            button.title = "◉ onari"
        } else {
            button.title = "◎ onari"
        }

        let board = status.currentBoard ?? "—"
        button.toolTip = """
        Onari ambient capture
        board: \(board)
        switches: \(status.switchCount)  notes: \(status.noteCount)
        note hotkey: \(status.hotKeyDisplay)\(status.hotKeyRegistered ? "" : " (NOT REGISTERED)")
        accessibility: \(status.trusted ? "granted" : "MISSING")
        microphone: \(status.micGranted ? "granted" : "MISSING")
        bridge: \(status.publishing ? "connected" : "UNREACHABLE (spooling)")
        """

        if let record = statusItem?.menu?.item(withTag: Tag.record) {
            if status.recording {
                let seconds = Int(status.recordingElapsed)
                record.title = String(format: "■ Stop recording  (%d:%02d)", seconds / 60, seconds % 60)
            } else if status.transcribing {
                record.title = "⋯ Transcribing…"
            } else {
                record.title = "● Start voice note      \(status.hotKeyDisplay)"
            }
            record.isEnabled = !status.transcribing
        }
        if let counts = statusItem?.menu?.item(withTag: Tag.counts) {
            counts.title = "\(status.switchCount) switches · \(status.noteCount) notes"
        }
        if let boardItem = statusItem?.menu?.item(withTag: Tag.board) {
            boardItem.title = board
        }
        if let lastNote = statusItem?.menu?.item(withTag: Tag.lastNote) {
            lastNote.title = status.lastNoteText.map { "heard: \"\($0)\"" } ?? "no notes yet"
        }
        if let health = statusItem?.menu?.item(withTag: Tag.health) {
            var problems: [String] = []
            if !status.trusted { problems.append("no accessibility") }
            if !status.micGranted { problems.append("no microphone") }
            if !status.publishing { problems.append("bridge down") }
            if !status.hotKeyRegistered { problems.append("hotkey taken") }
            health.title = problems.isEmpty ? "all green" : problems.joined(separator: " · ")
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // First item, and clickable: the hotkey should be the fast path, never
        // the only path. If the binding is wrong you can still record.
        let record = NSMenuItem(
            title: "● Start voice note", action: #selector(toggleRecording), keyEquivalent: ""
        )
        record.tag = Tag.record
        record.target = self
        menu.addItem(record)

        let lastNote = NSMenuItem(title: "no notes yet", action: nil, keyEquivalent: "")
        lastNote.tag = Tag.lastNote
        lastNote.isEnabled = false
        menu.addItem(lastNote)

        menu.addItem(.separator())

        let counts = NSMenuItem(title: "0 switches · 0 notes", action: nil, keyEquivalent: "")
        counts.tag = Tag.counts
        counts.isEnabled = false
        menu.addItem(counts)

        let board = NSMenuItem(title: "—", action: nil, keyEquivalent: "")
        board.tag = Tag.board
        board.isEnabled = false
        menu.addItem(board)

        let health = NSMenuItem(title: "starting…", action: nil, keyEquivalent: "")
        health.tag = Tag.health
        health.isEnabled = false
        menu.addItem(health)

        menu.addItem(.separator())

        // The rehearsed fallback: fire the wander script's notes by hand if the
        // mic misbehaves on stage.
        let scripted = NSMenu()
        for text in AppDelegate.scriptedNotes {
            let entry = NSMenuItem(
                title: text, action: #selector(injectScriptedNote(_:)), keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = text
            scripted.addItem(entry)
        }
        let scriptedItem = NSMenuItem(title: "Inject scripted note", action: nil, keyEquivalent: "")
        menu.addItem(scriptedItem)
        menu.setSubmenu(scripted, for: scriptedItem)

        let accessibility = NSMenuItem(
            title: "Open Accessibility settings…",
            action: #selector(openAccessibilitySettings), keyEquivalent: ""
        )
        accessibility.target = self
        menu.addItem(accessibility)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    /// Straight from `seed/demo-scenario.md`. Keep these in sync with the script.
    static let scriptedNotes = [
        "interesting, ties into the signal thing",
        "this section three argument supports our capture approach",
        "compare this with the pipeline latency issue",
        "that point at minute twelve about context loss, exactly our case",
    ]

    @objc private func toggleRecording() {
        coordinator?.toggleNote()
    }

    @objc private func injectScriptedNote(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        coordinator?.injectNote(text)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        coordinator?.stop()
        NSApp.terminate(nil)
    }
}
