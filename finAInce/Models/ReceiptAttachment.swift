import Foundation
import SwiftData

enum ReceiptAttachmentKind: String, Codable {
    case image
    case pdf

    var iconName: String {
        switch self {
        case .image:
            return "photo"
        case .pdf:
            return "doc.richtext"
        }
    }
}

@Model
final class ReceiptAttachment {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var storedFileName: String
    var contentType: String
    var kind: ReceiptAttachmentKind
    var createdAt: Date

    var transaction: Transaction?

    init(
        fileName: String,
        storedFileName: String,
        contentType: String,
        kind: ReceiptAttachmentKind
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.storedFileName = storedFileName
        self.contentType = contentType
        self.kind = kind
        self.createdAt = Date()
    }
}
