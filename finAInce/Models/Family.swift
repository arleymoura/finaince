import Foundation
import SwiftData

@Model
final class Family {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Account.family)
    var accounts: [Account] = []

    @Relationship(deleteRule: .cascade, inverse: \Category.family)
    var categories: [Category] = []

    @Relationship(deleteRule: .cascade, inverse: \Transaction.family)
    var transactions: [Transaction] = []

    @Relationship(deleteRule: .cascade, inverse: \AISettings.family)
    var aiSettings: AISettings?

    @Relationship(deleteRule: .cascade, inverse: \AIAnalysis.family)
    var analyses: [AIAnalysis] = []

    @Relationship(deleteRule: .cascade, inverse: \ChatConversation.family)
    var conversations: [ChatConversation] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
