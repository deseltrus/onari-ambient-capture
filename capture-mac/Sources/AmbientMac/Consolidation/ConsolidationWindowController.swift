import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class ConsolidationWindowController: NSWindowController {
    let model: ConsolidationViewModel

    /// A distinct global hotkey from the capture note key: this one accepts and
    /// performs the suggested action. Demo beat — press it to send.
    private let acceptHotKey = HotKey()
    static let acceptCombo = HotKey.Combo(
        keyCode: UInt32(kVK_Return),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⌃⌥⌘↩"
    )
    private var permissionsRequested = false

    init(store: SessionStore? = nil) {
        let store = store ?? SessionStore()
        model = ConsolidationViewModel(store: store)
        let hosting = NSHostingController(rootView: ConsolidationView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Onari — Session Intelligence"
        window.setContentSize(NSSize(width: 1000, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        acceptHotKey.onPress = { [weak self] in self?.model.acceptSuggestedAction() }
        if !acceptHotKey.register(Self.acceptCombo) {
            Log.line("consolidation: accept hotkey \(Self.acceptCombo.display) not registered (already taken)")
        }
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        // Voice in the session window needs mic + speech; ask once, up front.
        if !permissionsRequested {
            permissionsRequested = true
            MicNoteRecorder.requestPermissions { granted in
                if !granted { Log.line("consolidation: mic/speech not granted — voice chat disabled") }
            }
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if model.response == nil { model.consolidate() }
    }
}
