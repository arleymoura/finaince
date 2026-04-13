import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user      = "user"
    case assistant = "assistant"
}

// MARK: - ChatConversation

@Model
final class ChatConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var monthRef: String?
    var createdAt: Date

    var family: Family?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(title: String, monthRef: String? = nil) {
        self.id = UUID()
        self.title = title
        self.monthRef = monthRef
        self.createdAt = Date()
    }
}

// MARK: - ChatMessage

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date

    var conversation: ChatConversation?

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
