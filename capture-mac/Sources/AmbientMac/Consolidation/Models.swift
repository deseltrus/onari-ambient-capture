import Foundation

struct ConsolidationResponse: Codable, Identifiable, Equatable {
    struct Evidence: Codable, Identifiable, Equatable {
        let id: String
        let kind: String
        let label: String
        let detail: String
        let observedAt: String?
    }

    struct SuggestedAction: Codable, Identifiable, Equatable {
        let id: String
        let type: String
        let label: String
        let requiresApproval: Bool
    }

    let id: String
    let sessionId: String
    let createdAt: String
    let summary: String
    let evidence: [Evidence]
    let suggestedActions: [SuggestedAction]
}

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }

    let id: String
    let role: Role
    let text: String
    let createdAt: String
}

struct TimelineEntry: Codable, Identifiable, Equatable {
    let id: String
    let sequence: Int
    let timestamp: String
    let type: String
    let title: String
    let detail: String?
}

struct OnariSession: Codable, Equatable {
    let id: String
    let startedAt: String
    var endedAt: String?
    var guildSessionId: String?
    var nextSequence: Int
}

/// One line in the live execution pipeline the RocketRide dispatch runs. The UI
/// reveals these one at a time so a rehearsed dispatch reads as if it is
/// happening on stage.
struct ExecutionStep: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let status: String   // done | skipped | failed | running
    let detail: String?
    let t: String?
}

struct DispatchResult: Codable, Equatable {
    let dispatchId: String
    let status: String
    let artifact: String?
    let traceURL: String?
    let steps: [ExecutionStep]?
}

enum ISOTime {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func now() -> String { formatter.string(from: Date()) }
}
