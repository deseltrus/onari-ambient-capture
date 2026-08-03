import Foundation

/// Everything the app does, on stderr.
///
/// WHY STDERR AND NOT print()
/// `swift run AmbientMac | tee log` makes stdout a pipe, and C stdio switches
/// to full buffering on a pipe — 4KB of output would sit unflushed while the
/// user stares at an empty terminal wondering if anything works. stderr is
/// unbuffered, so every line lands the instant it is written.
///
/// WHY THIS EXISTS AT ALL
/// The menu-bar item is not a reliable indicator. On a MacBook Pro the menu bar
/// overflows under the notch, and macOS silently hides items that do not fit —
/// with no error, no warning, and no way for the app to know. The terminal is
/// the one surface that cannot disappear, so it carries the real feedback.
public enum Log {
    private static let started = Date()

    public static func line(_ message: String) {
        let elapsed = Date().timeIntervalSince(started)
        let stamp = String(format: "%02d:%05.2f", Int(elapsed) / 60, elapsed.truncatingRemainder(dividingBy: 60))
        FileHandle.standardError.write(Data("[\(stamp)] \(message)\n".utf8))
    }

    public static func banner(_ lines: [String]) {
        let rule = String(repeating: "─", count: 62)
        var out = "\n" + rule + "\n"
        for line in lines { out += line + "\n" }
        out += rule + "\n"
        FileHandle.standardError.write(Data(out.utf8))
    }
}
