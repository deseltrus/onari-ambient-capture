import Foundation

protocol Lane3Serving {
    func consolidate(sessionId: String) async throws -> ConsolidationResponse
    func chat(sessionId: String, response: ConsolidationResponse?, message: String) async throws -> String
    func dispatch(
        sessionId: String,
        response: ConsolidationResponse,
        action: ConsolidationResponse.SuggestedAction
    ) async throws -> DispatchResult
}

enum Lane3Error: LocalizedError {
    case noIntentFrame
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .noIntentFrame: return "Could not find intent-frame.json. Set ONARI_INTENT_FRAME or run from the repository."
        case .invalidResponse: return "Lane 3 returned an invalid response."
        case .service(let message): return message
        }
    }
}

final class Lane3Client: Lane3Serving {
    private let remote: URL?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        remote = environment["ONARI_LANE3_URL"].flatMap(URL.init(string:))
    }

    func consolidate(sessionId: String) async throws -> ConsolidationResponse {
        if let remote {
            return try await post(
                remote.appendingPathComponent("consolidate"),
                body: ["sessionId": sessionId],
                as: ConsolidationResponse.self
            )
        }
        return try FixtureLane3Client().consolidate(sessionId: sessionId)
    }

    func chat(
        sessionId: String,
        response: ConsolidationResponse?,
        message: String
    ) async throws -> String {
        if let remote {
            struct Reply: Decodable { let text: String }
            let result = try await post(
                remote.appendingPathComponent("chat"),
                body: [
                    "sessionId": sessionId,
                    "responseId": response?.id ?? "",
                    "message": message,
                ],
                as: Reply.self
            )
            return result.text
        }
        return try await FixtureLane3Client().chat(
            sessionId: sessionId, response: response, message: message
        )
    }

    func dispatch(
        sessionId: String,
        response: ConsolidationResponse,
        action: ConsolidationResponse.SuggestedAction
    ) async throws -> DispatchResult {
        if let remote {
            return try await post(
                remote.appendingPathComponent("dispatch"),
                body: [
                    "sessionId": sessionId,
                    "responseId": response.id,
                    "actionId": action.id,
                    "approved": "true",
                ],
                as: DispatchResult.self
            )
        }
        return try await FixtureLane3Client().dispatch(
            sessionId: sessionId, response: response, action: action
        )
    }

    private func post<T: Decodable>(
        _ url: URL,
        body: [String: String],
        as type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw Lane3Error.service("Lane 3 service request failed.")
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

private struct IntentFrame: Decodable {
    struct Board: Decodable {
        struct Topic: Decodable { let topic: String; let score: Double }
        let board_id: String
        let app: String
        let title: String
        let last_seen: String
        let topics: [Topic]
        let unspoken: Bool
    }

    struct HistoryJoin: Decodable {
        let topic: String
        let episode: String
        let body: String
        let t: String
    }

    let mission: String
    let boards: [Board]
    let history_joins: [HistoryJoin]
}

private final class FixtureLane3Client: Lane3Serving {
    func consolidate(sessionId: String) throws -> ConsolidationResponse {
        let frame = try loadFrame()
        let unspoken = frame.boards
            .filter(\.unspoken)
            .max { strongestScore($0) < strongestScore($1) }
        let topic = unspoken?.topics.max(by: { $0.score < $1.score })?.topic
        let history = frame.history_joins.first { $0.topic == topic } ?? frame.history_joins.first

        var evidence: [ConsolidationResponse.Evidence] = []
        if let unspoken {
            evidence.append(.init(
                id: unspoken.board_id,
                kind: "unspoken_board",
                label: unspoken.title,
                detail: "Seen in \(unspoken.app), never written down, and ranked as a strong topic signal.",
                observedAt: unspoken.last_seen
            ))
        }
        if let history {
            evidence.append(.init(
                id: history.episode,
                kind: "history_join",
                label: "Earlier \(history.topic) thread",
                detail: history.body,
                observedAt: history.t
            ))
        }

        let subject = unspoken?.title ?? "an unspoken surface"
        return ConsolidationResponse(
            id: "response_\(UUID().uuidString)",
            sessionId: sessionId,
            createdAt: ISOTime.now(),
            summary: "\(subject) appears relevant to your \(frame.mission) mission and reconnects with an unfinished historical thread.",
            evidence: evidence,
            suggestedActions: [
                .init(
                    id: "action_\(UUID().uuidString)",
                    type: "draft_outreach",
                    label: "Create outreach draft",
                    requiresApproval: true
                )
            ]
        )
    }

    func chat(
        sessionId: String,
        response: ConsolidationResponse?,
        message: String
    ) async throws -> String {
        guard let response else { return "Open the session insight first so I can ground the answer in its evidence." }
        let evidence = response.evidence.map { $0.label }.joined(separator: " and ")
        return "Within this session, the relevant evidence is \(evidence). Your question was: “\(message)”. In connected mode, Guild will answer this turn while preserving the same session context."
    }

    func dispatch(
        sessionId: String,
        response: ConsolidationResponse,
        action: ConsolidationResponse.SuggestedAction
    ) async throws -> DispatchResult {
        let subject = response.evidence.first?.label ?? "the context-systems thread"
        let artifact = """
        Hey — I was revisiting our signal-pipeline work and came across \(subject). It connected back to our earlier conversation about context systems. I’d love to compare notes and show you what we’re building when you have a moment.
        """
        return DispatchResult(
            dispatchId: "dispatch_\(UUID().uuidString)",
            status: "done",
            artifact: artifact,
            traceURL: nil
        )
    }

    private func strongestScore(_ board: IntentFrame.Board) -> Double {
        board.topics.map(\.score).max() ?? 0
    }

    private func loadFrame() throws -> IntentFrame {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let configured = environment["ONARI_INTENT_FRAME"] {
            candidates.append(URL(fileURLWithPath: configured))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("intent-frame.json"))
        candidates.append(cwd.deletingLastPathComponent().appendingPathComponent("intent-frame.json"))

        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw Lane3Error.noIntentFrame
        }
        return try JSONDecoder().decode(IntentFrame.self, from: Data(contentsOf: url))
    }
}
