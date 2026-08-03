import Foundation

/// Wire types for `event-contract.json` v1. These are the ONLY shapes that go
/// on `ambient-events`. Field names and optionality are pinned by the contract;
/// if the team bumps the contract, bump `Contract.version` and these structs
/// together, never one without the other.
///
/// Encodable only, on purpose: the capture app writes events, it never reads
/// them back, and `let type = "switch"` cannot participate in decode synthesis.
public enum Contract {
    public static let version = 1
    public static let streamIn = "ambient-events"
    public static let streamOut = "dispatch-results"

    /// The contract's timestamps are plain internet date-time, no fractional
    /// seconds — matches `fixtures/events-sample.jsonl` byte for byte.
    public static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    public static func stamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }
}

// MARK: - Surface reference

/// One side of a switch: which app, which window, which board.
/// All three are null on the very first switch of a session (`from`).
public struct SurfaceRef: Codable, Equatable {
    public var app: String?
    public var title: String?
    public var boardID: String?

    public init(app: String?, title: String?, boardID: String?) {
        self.app = app
        self.title = title
        self.boardID = boardID
    }

    /// The contract's null-origin: `{"app":null,"title":null,"board_id":null}`.
    public static let origin = SurfaceRef(app: nil, title: nil, boardID: nil)

    enum CodingKeys: String, CodingKey {
        case app, title
        case boardID = "board_id"
    }

    /// Nulls must be present, not omitted: the contract declares the keys and
    /// the graph lane reads `from.board_id` unconditionally.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(app, forKey: .app)
        try c.encode(title, forKey: .title)
        try c.encode(boardID, forKey: .boardID)
    }
}

// MARK: - Events

public struct SwitchEvent: Encodable, Equatable {
    public let type = "switch"
    public let v = Contract.version
    public var t: String
    public var seq: Int
    public var from: SurfaceRef
    public var to: SurfaceRef
    public var dwellMsFrom: Int?

    public init(t: String, seq: Int, from: SurfaceRef, to: SurfaceRef, dwellMsFrom: Int?) {
        self.t = t
        self.seq = seq
        self.from = from
        self.to = to
        self.dwellMsFrom = dwellMsFrom
    }

    enum CodingKeys: String, CodingKey {
        case type, v, t, seq, from, to
        case dwellMsFrom = "dwell_ms_from"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(v, forKey: .v)
        try c.encode(t, forKey: .t)
        try c.encode(seq, forKey: .seq)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encode(dwellMsFrom, forKey: .dwellMsFrom)
    }
}

/// `note` — a raw spoken fragment bound to a board and a moment.
/// `passthrough` mode additionally records which field received the text.
public struct NoteEvent: Encodable, Equatable {
    public enum Mode: String, Encodable {
        case note
        case passthrough
    }

    public let type = "note"
    public let v = Contract.version
    public var t: String
    public var boardID: String
    public var app: String
    public var title: String
    public var text: String
    public var mode: Mode
    public var field: String?

    public init(
        t: String, boardID: String, app: String, title: String,
        text: String, mode: Mode, field: String?
    ) {
        self.t = t
        self.boardID = boardID
        self.app = app
        self.title = title
        self.text = text
        self.mode = mode
        self.field = field
    }

    enum CodingKeys: String, CodingKey {
        case type, v, t, app, title, text, mode, field
        case boardID = "board_id"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(v, forKey: .v)
        try c.encode(t, forKey: .t)
        try c.encode(boardID, forKey: .boardID)
        try c.encode(app, forKey: .app)
        try c.encode(title, forKey: .title)
        try c.encode(text, forKey: .text)
        try c.encode(mode, forKey: .mode)
        try c.encode(field, forKey: .field)
    }
}

/// `delta` — something changed on a board while you were elsewhere
/// (block G: an assistant answer landed).
public struct DeltaEvent: Encodable, Equatable {
    public let type = "delta"
    public let v = Contract.version
    public var t: String
    public var boardID: String
    public var kind = "assistant_answer"
    public var source: String
    public var preview: String

    public init(t: String, boardID: String, source: String, preview: String) {
        self.t = t
        self.boardID = boardID
        self.source = source
        self.preview = preview
    }

    enum CodingKeys: String, CodingKey {
        case type, v, t, kind, source, preview
        case boardID = "board_id"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(v, forKey: .v)
        try c.encode(t, forKey: .t)
        try c.encode(boardID, forKey: .boardID)
        try c.encode(kind, forKey: .kind)
        try c.encode(source, forKey: .source)
        try c.encode(preview, forKey: .preview)
    }
}

// MARK: - Envelope

/// One JSON object per event, so the publisher can carry any of the shapes
/// without generics leaking into every call site.
public enum AmbientEvent: Equatable {
    case switchEvent(SwitchEvent)
    case note(NoteEvent)
    case delta(DeltaEvent)

    public var kind: String {
        switch self {
        case .switchEvent: return "switch"
        case .note: return "note"
        case .delta: return "delta"
        }
    }

    /// Compact, key-sorted JSON. Sorted keys make fixture diffing sane and
    /// make the publisher's output reproducible in tests.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        switch self {
        case .switchEvent(let e): return try encoder.encode(e)
        case .note(let e): return try encoder.encode(e)
        case .delta(let e): return try encoder.encode(e)
        }
    }

    public func encodedString() throws -> String {
        String(decoding: try encoded(), as: UTF8.self)
    }
}
