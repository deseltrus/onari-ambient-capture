import AppKit
import SwiftUI

/// Hackathon scaffold entry point. Menu-bar app, no Dock icon. Each block of
/// the 4.5h cut fills one module:
///   Block A: Spotlight/ (overlay window is transplanted + tested; frame view is yours)
///   Block B: Capture/ActiveWindowProbe.swift + Capture/SwitchChain.swift
///   Block C: Notiz/MicNoteRecorder.swift
///   Block D: Ansicht/BoardListView.swift
///   Block E: Capture/ChatLogReader.swift (fixtures under Fixtures/)
@main
struct AmbientMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◎"
        statusItem = item
    }
}
