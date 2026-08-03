import AppKit
import ApplicationServices

/// What the probe saw at one instant: the frontmost app and its focused window.
public struct SurfaceSample: Equatable {
    public var app: String
    public var title: String
    public var boardID: String

    public init(app: String, title: String) {
        self.app = app
        self.title = title
        self.boardID = BoardIdentity.boardID(app: app, title: title)
    }
}

/// Block B, half one: read the current surface.
///
/// `NSWorkspace` gives us the frontmost application for free and with no
/// permission. The *window title* needs the Accessibility API, which needs the
/// user to tick a box in System Settings. We degrade instead of dying: without
/// AX trust we still emit app-level switches, so the stream is never empty and
/// the demo never hard-fails on a permissions dialog.
@MainActor
public final class ActiveWindowProbe {
    public init() {}

    /// Has the user granted Accessibility? Never blocks.
    public var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask once, with the system prompt. Calling this repeatedly is harmless
    /// but only the first call in a session shows the dialog.
    @discardableResult
    public func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// The current surface, or nil if nothing is frontmost (rare: login window,
    /// fast user switch).
    public func sample() -> SurfaceSample? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = front.localizedName ?? front.bundleIdentifier ?? "Unknown"

        // Never probe ourselves: the menu-bar app is not a surface the user is
        // working in, and sampling it would inject phantom switches every time
        // the user opens our own window.
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return nil
        }

        let title = focusedWindowTitle(pid: front.processIdentifier) ?? appName
        return SurfaceSample(app: appName, title: title)
    }

    /// AX read of the focused window's title. Returns nil when untrusted, when
    /// the app has no focused window, or when the app refuses AX (some
    /// Electron builds do).
    public func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        )
        guard windowResult == .success, let windowRef else { return nil }

        // CFTypeRef -> AXUIElement. Checking the type id keeps this honest if
        // an app hands back something unexpected.
        guard CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        let window = windowRef as! AXUIElement

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            window, kAXTitleAttribute as CFString, &titleRef
        )
        guard titleResult == .success,
              let title = titleRef as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return title
    }

    /// The focused text field's identity, for pass-through dictation's
    /// `field` column. Best-effort: role + any label we can find.
    public func focusedFieldDescription(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var elementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &elementRef
        )
        guard result == .success, let elementRef,
              CFGetTypeID(elementRef) == AXUIElementGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        let element = elementRef as! AXUIElement

        func string(_ attribute: String) -> String? {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
                  let s = ref as? String,
                  !s.isEmpty
            else { return nil }
            return s
        }

        let role = string(kAXRoleAttribute as String) ?? "AXUnknown"
        let label = string(kAXDescriptionAttribute as String)
            ?? string(kAXTitleAttribute as String)
            ?? string(kAXPlaceholderValueAttribute as String)

        return label.map { "\(role):\($0)" } ?? role
    }
}
