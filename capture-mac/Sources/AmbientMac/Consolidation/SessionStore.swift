import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var session: OnariSession
    @Published private(set) var timeline: [TimelineEntry] = []
    @Published private(set) var chat: [ChatMessage] = []

    private let root: URL
    private var sessionDirectory: URL { root.appendingPathComponent(session.id, isDirectory: true) }
    private var timelineURL: URL { sessionDirectory.appendingPathComponent("timeline.jsonl") }
    private var sessionURL: URL { sessionDirectory.appendingPathComponent("session.json") }

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        root = applicationSupport
            .appendingPathComponent("Onari", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)

        let stamp = ISOTime.now()
        session = OnariSession(
            id: "session_\(stamp.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: ""))",
            startedAt: stamp,
            endedAt: nil,
            guildSessionId: nil,
            nextSequence: 1
        )

        do {
            try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try persistSession()
            append(type: "session.started", title: "Session started")
        } catch {
            Log.line("session store: \(error.localizedDescription)")
        }
    }

    func append(type: String, title: String, detail: String? = nil) {
        let entry = TimelineEntry(
            id: UUID().uuidString,
            sequence: session.nextSequence,
            timestamp: ISOTime.now(),
            type: type,
            title: title,
            detail: detail
        )
        session.nextSequence += 1
        timeline.append(entry)

        do {
            let data = try JSONEncoder().encode(entry)
            if !FileManager.default.fileExists(atPath: timelineURL.path) {
                FileManager.default.createFile(atPath: timelineURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: timelineURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
            try handle.close()
            try persistSession()
        } catch {
            Log.line("timeline write: \(error.localizedDescription)")
        }
    }

    func addChat(role: ChatMessage.Role, text: String) {
        let message = ChatMessage(id: UUID().uuidString, role: role, text: text, createdAt: ISOTime.now())
        chat.append(message)
        append(type: "chat.\(role.rawValue)", title: role == .user ? "You" : "Onari", detail: text)
    }

    func save(response: ConsolidationResponse) {
        append(type: "response.saved", title: "Insight saved", detail: response.summary)
    }

    func ignore(response: ConsolidationResponse) {
        append(type: "response.ignored", title: "Suggestion ignored", detail: response.id)
    }

    func recordDispatch(_ result: DispatchResult) {
        append(
            type: "dispatch.\(result.status)",
            title: result.status == "done" ? "Artifact created" : "Dispatch \(result.status)",
            detail: result.artifact
        )
        guard let artifact = result.artifact else { return }
        let artifacts = sessionDirectory.appendingPathComponent("artifacts", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
            try artifact.write(
                to: artifacts.appendingPathComponent("\(result.dispatchId).md"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            Log.line("artifact write: \(error.localizedDescription)")
        }
    }

    func end() {
        guard session.endedAt == nil else { return }
        session.endedAt = ISOTime.now()
        append(type: "session.ended", title: "Session ended")
    }

    private func persistSession() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: sessionURL, options: .atomic)
    }
}
