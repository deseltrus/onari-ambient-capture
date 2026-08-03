import AppKit

/// The overlay carrier window. Transplanted contract from the proven Room
/// implementation (apps/room EmergenceOverlayWindow.swift:38-61) — only the
/// self-contained panel factory travels; the Room controller stays behind.
///
/// Window contract:
///   • styleMask: [.borderless, .nonactivatingPanel] — no chrome, never steals key
///   • level: .floating — sits over normal app windows
///   • collectionBehavior: all-Spaces · full-screen-aux · stationary — ambient
///   • transparent (isOpaque=false, clear background, no shadow)
///   • ignoresMouseEvents=true by DEFAULT — click-through until UI needs a tap
@MainActor
public enum SpotlightOverlayWindow {
    public static let panelIdentifier = NSUserInterfaceItemIdentifier("ai.onari.ambient.spotlight")

    public static func makeConfiguredPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = panelIdentifier
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        // Click-through by default: the transparent canvas must not eat events
        // that belong to whatever app is behind it.
        panel.ignoresMouseEvents = true
        return panel
    }
}
