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

struct DispatchResult: Codable, Equatable {
    let dispatchId: String
    let status: String
    let artifact: String?
    let traceURL: String?
}

enum ISOTime {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func now() -> String { formatter.string(from: Date()) }
}
