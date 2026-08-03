import CryptoKit
import Foundation

/// Boards are surfaces. The same window seen twice in a session must be the
/// SAME board — otherwise the wander chain looks like ten boards instead of
/// four and the consolidation view is nonsense.
///
/// So board_id is derived, not random: UUIDv5 over (app, normalized title).
/// Deterministic across restarts and across machines, which also means the
/// graph lane can join fixture boards to live boards without a lookup table.
public enum BoardIdentity {
    /// Namespace UUID for this project. Arbitrary but fixed forever.
    /// (Generated once; changing it re-keys every board in the graph.)
    public static let namespace = UUID(uuidString: "6f1c9a2e-3b7d-4c58-9f10-2d4a8e5b7c31")!

    /// Titles are noisy: browsers prepend unread counts, editors prepend a
    /// dirty marker, some apps append the app name. Strip the parts that
    /// change while the surface stays the same, so dwelling on one page does
    /// not spray a new board every few seconds.
    public static func normalize(title: String) -> String {
        var s = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Leading unread/notification counts: "(3) Inbox", "(12) LinkedIn"
        if let r = s.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        // Leading dirty markers used by editors: "• file.swift", "*file.swift"
        while let first = s.first, first == "•" || first == "*" {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        // Collapse internal whitespace runs.
        s = s.replacingOccurrences(
            of: #"\s+"#, with: " ", options: .regularExpression
        )
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// UUIDv5 (SHA-1, name-based) per RFC 4122 §4.3.
    public static func boardID(app: String, title: String) -> String {
        let name = "\(app)|\(normalize(title: title))"
        var bytes = [UInt8]()
        bytes.append(contentsOf: uuidBytes(namespace))
        bytes.append(contentsOf: Array(name.utf8))

        var digest = Array(Insecure.SHA1.hash(data: Data(bytes)).prefix(16))
        // version 5
        digest[6] = (digest[6] & 0x0F) | 0x50
        // RFC 4122 variant
        digest[8] = (digest[8] & 0x3F) | 0x80

        return format(digest)
    }

    private static func uuidBytes(_ uuid: UUID) -> [UInt8] {
        let u = uuid.uuid
        return [
            u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
            u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15,
        ]
    }

    private static func format(_ b: [UInt8]) -> String {
        func hex(_ range: Range<Int>) -> String {
            b[range].map { String(format: "%02x", $0) }.joined()
        }
        return [
            hex(0..<4), hex(4..<6), hex(6..<8), hex(8..<10), hex(10..<16),
        ].joined(separator: "-")
    }
}
