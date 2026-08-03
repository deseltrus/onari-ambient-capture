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
        struct Note: Decodable { let text: String; let mode: String? }
        struct Delta: Decodable { let kind: String?; let preview: String? }
        let board_id: String
        let app: String
        let title: String
        let last_seen: String
        let topics: [Topic]
        let unspoken: Bool
        let notes: [Note]?
        let deltas: [Delta]?
    }

    struct HistoryJoin: Decodable {
        let topic: String
        let episode: String
        let body: String
        let t: String
    }

    struct Target: Decodable {
        let channel: String?
        let group: String?
    }

    let mission: String
    let boards: [Board]
    let history_joins: [HistoryJoin]
    let scenario: String?
    let target: Target?
    let hardcoded_message: String?

    var isWhatsApp: Bool { scenario == "three-docs-whatsapp" || target?.channel == "whatsapp" }
    var group: String { target?.group ?? "Hackathon 08/03 - TEAM O" }

    /// The documents the user read — Safari boards that are not question tabs.
    var documentBoards: [Board] {
        boards.filter { $0.app == "Safari" && !$0.board_id.hasPrefix("q") }
    }

    /// The answer the user got in a question tab for a topic, but never relayed.
    func answer(for topic: String) -> String? {
        boards
            .filter { $0.board_id.hasPrefix("q") && $0.topics.contains { $0.topic == topic } }
            .compactMap { $0.deltas?.compactMap(\.preview).first }
            .first
    }

    func history(for topic: String) -> HistoryJoin? {
        history_joins.first { $0.topic == topic }
    }
}

private final class FixtureLane3Client: Lane3Serving {
    static let topicLead = [
        "execution-pipeline": "RocketRide (execution)",
        "graph-memory": "FalkorDB (memory)",
        "context-capture": "Ambient-capture paper",
    ]
    static let topicNet = [
        "execution-pipeline": "build the dispatch/execution layer on RocketRide",
        "graph-memory": "keep memory in FalkorDB — no separate vector store",
        "context-capture": "on-device capture with a visible recording state is our sourced differentiator",
    ]

    func consolidate(sessionId: String) throws -> ConsolidationResponse {
        let frame = try loadFrame()
        if frame.isWhatsApp {
            return whatsappConsolidate(sessionId: sessionId, frame: frame)
        }
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
        if let frame = try? loadFrame(), frame.isWhatsApp {
            return whatsappDispatch(frame: frame)
        }
        let subject = response.evidence.first?.label ?? "the context-systems thread"
        let artifact = """
        Hey — I was revisiting our signal-pipeline work and came across \(subject). It connected back to our earlier conversation about context systems. I’d love to compare notes and show you what we’re building when you have a moment.
        """
        return DispatchResult(
            dispatchId: "dispatch_\(UUID().uuidString)",
            status: "done",
            artifact: artifact,
            traceURL: nil,
            steps: nil
        )
    }

    // MARK: - WhatsApp scenario (offline mirror of lane3/bridge.py)

    private func whatsappConsolidate(sessionId: String, frame: IntentFrame) -> ConsolidationResponse {
        let docs = frame.documentBoards.sorted { strongestScore($0) > strongestScore($1) }
        var evidence: [ConsolidationResponse.Evidence] = docs.map { board in
            let topic = board.topics.max { $0.score < $1.score }?.topic ?? ""
            let detail = frame.answer(for: topic)
                ?? board.notes?.first?.text
                ?? "Read this session; you never wrote down what it settled."
            return .init(
                id: board.board_id,
                kind: board.unspoken ? "unspoken_board" : "note",
                label: board.title,
                detail: detail,
                observedAt: board.last_seen
            )
        }
        if let topTopic = docs.flatMap(\.topics).max(by: { $0.score < $1.score })?.topic,
           let join = frame.history(for: topTopic) {
            evidence.append(.init(
                id: join.episode,
                kind: "history_join",
                label: "Open TEAM O thread",
                detail: join.body,
                observedAt: join.t
            ))
        }
        let openThreads = Set(frame.history_joins.map(\.topic)).count
        let summary = "You read \(docs.count) documents and answered \(openThreads) open TEAM O questions in your tabs — but none of those answers reached the team. Onari can post the synthesis to “\(frame.group)” for you."
        return ConsolidationResponse(
            id: "response_\(UUID().uuidString)",
            sessionId: sessionId,
            createdAt: ISOTime.now(),
            summary: summary,
            evidence: evidence,
            suggestedActions: [
                .init(
                    id: "action_\(UUID().uuidString)",
                    type: "send_whatsapp",
                    label: "Send update to \(frame.group)",
                    requiresApproval: true
                )
            ]
        )
    }

    private func whatsappDispatch(frame: IntentFrame) -> DispatchResult {
        let message = draftWhatsAppMessage(frame: frame)
        let group = frame.group
        let steps: [ExecutionStep] = [
            .init(id: "assemble", label: "Assemble context from the 3 documents", status: "done",
                  detail: "RocketRide pulled the read documents, tab answers, and open team threads.", t: ISOTime.now()),
            .init(id: "draft", label: "Draft the team update", status: "done",
                  detail: "\(message.split(separator: " ").count) words, grounded only in what you actually read.", t: ISOTime.now()),
            .init(id: "policy", label: "Policy check", status: "done",
                  detail: "artifactOnly + doNotSend honored (rehearsal): message prepared, delivery held.", t: ISOTime.now()),
            .init(id: "open", label: "Open WhatsApp → \(group)", status: "done", detail: "Located the group thread.", t: ISOTime.now()),
            .init(id: "send", label: "Send message", status: "skipped",
                  detail: "Rehearsal mode — not delivered. Run the bridge with ONARI_EXECUTOR=whatsapp_mac to send for real.", t: ISOTime.now()),
            .init(id: "confirm", label: "Confirm delivery", status: "skipped", detail: "Simulated delivery receipt.", t: ISOTime.now()),
        ]
        return DispatchResult(
            dispatchId: "dispatch_\(UUID().uuidString)",
            status: "done",
            artifact: message,
            traceURL: "https://cloud.rocketride.ai/runs/run_\(UUID().uuidString.prefix(12))",
            steps: steps
        )
    }

    private func draftWhatsAppMessage(frame: IntentFrame) -> String {
        if let hardcoded = frame.hardcoded_message, !hardcoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return hardcoded
        }
        var lines = ["Team — quick sync before the build call. I went deep on the docs:"]
        var nets: [String] = []
        let docs = frame.documentBoards.sorted { strongestScore($0) > strongestScore($1) }
        for (index, board) in docs.enumerated() {
            let topic = board.topics.max { $0.score < $1.score }?.topic ?? ""
            let lead = Self.topicLead[topic] ?? board.title
            let detail = frame.answer(for: topic) ?? board.notes?.first?.text ?? ""
            lines.append("\(index + 1)) \(lead): \(detail)".trimmingCharacters(in: .whitespaces))
            if let net = Self.topicNet[topic] { nets.append(net) }
        }
        if !nets.isEmpty {
            lines.append("Net: " + nets.joined(separator: "; ") + ". Pushing on this now.")
        }
        return lines.joined(separator: "\n")
    }

    private func strongestScore(_ board: IntentFrame.Board) -> Double {
        board.topics.map(\.score).max() ?? 0
    }

    private func loadFrame() throws -> IntentFrame {
        // Resolution mirrors lane3/bridge.py: explicit ONARI_INTENT_FRAME wins,
        // then the scenario frame under scenarios/ (default: the three-docs demo),
        // then the legacy intent-frame.json.
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let configured = environment["ONARI_INTENT_FRAME"] {
            candidates.append(URL(fileURLWithPath: configured))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roots = [cwd, cwd.deletingLastPathComponent()]
        let scenario = environment["ONARI_SCENARIO"] ?? "three-docs-whatsapp"
        for root in roots {
            candidates.append(root.appendingPathComponent("scenarios/\(scenario).json"))
        }
        for root in roots {
            candidates.append(root.appendingPathComponent("intent-frame.json"))
        }

        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw Lane3Error.noIntentFrame
        }
        return try JSONDecoder().decode(IntentFrame.self, from: Data(contentsOf: url))
    }
}
