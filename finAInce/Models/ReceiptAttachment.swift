import Foundation
import SwiftData

enum ReceiptAttachmentKind: String, Codable {
    case image
    case pdf

    var iconName: String {
        switch self {
        case .image: return "photo"
        case .pdf:   return "doc.richtext"
        }
    }
}

@Model
final class ReceiptAttachment {
    var id: UUID = UUID()
    var fileName: String = ""
    var storedFileName: String = ""
    var contentType: String = ""
    var kind: ReceiptAttachmentKind = ReceiptAttachmentKind.image
    var createdAt: Date = Date()

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
