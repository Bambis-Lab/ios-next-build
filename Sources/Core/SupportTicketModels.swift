import Foundation

enum ChatAccessRole: String, Codable, Equatable, Sendable {
    case owner
    case member
}

struct ChatSession: Codable, Equatable, Sendable {
    let userID: String
    let role: ChatAccessRole

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case role
    }
}

struct SupportTicketMessage: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let authorUserID: String
    let authorRole: ChatAccessRole
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorUserID = "author_user_id"
        case authorRole = "author_role"
        case body
        case createdAt = "created_at"
    }
}

struct SupportTicket: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let requesterUserID: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let lastMessage: String?
    let messages: [SupportTicketMessage]?
    let suggestedProjectID: String?
    let dispatchedProjectID: String?
    let dispatchState: String?

    enum CodingKeys: String, CodingKey {
        case id
        case requesterUserID = "requester_user_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessage = "last_message"
        case messages
        case suggestedProjectID = "suggested_project_id"
        case dispatchedProjectID = "dispatched_project_id"
        case dispatchState = "dispatch_state"
    }
}

struct ProjectRoute: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let repository: String?
}

struct ProjectDispatch: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let ticketID: String
    let projectID: String
    let state: String
    let approvedBy: String
    let approvedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case ticketID = "ticket_id"
        case projectID = "project_id"
        case state
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
    }
}

struct SupportTicketApprovalRequest: Codable, Sendable {
    let projectID: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
    }
}

struct SupportTicketMessageRequest: Codable, Sendable {
    let message: String
}

struct SupportTicketStatusRequest: Codable, Sendable {
    let status: String
}
