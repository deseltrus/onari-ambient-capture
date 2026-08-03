import AppKit
import SwiftUI

@MainActor
final class ConsolidationWindowController: NSWindowController {
    let model: ConsolidationViewModel

    init(store: SessionStore? = nil) {
        let store = store ?? SessionStore()
        model = ConsolidationViewModel(store: store)
        let hosting = NSHostingController(rootView: ConsolidationView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Onari — Session Intelligence"
        window.setContentSize(NSSize(width: 980, height: 700))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if model.response == nil { model.consolidate() }
    }
}
