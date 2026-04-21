import Foundation
import SwiftData
import UIKit

struct ReceiptDraftAttachment: Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let localURL: URL
    let contentType: String
    let kind: ReceiptAttachmentKind

    init(
        id: UUID = UUID(),
        fileName: String,
        localURL: URL,
        contentType: String,
        kind: ReceiptAttachmentKind
    ) {
        self.id = id
        self.fileName = fileName
        self.localURL = localURL
        self.contentType = contentType
        self.kind = kind
    }
}

enum ReceiptAttachmentStore {
    private static let receiptsDirectoryName = "Receipts"
    private static let draftsDirectoryName = "Drafts"

    static func createDraft(from image: UIImage) throws -> ReceiptDraftAttachment {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let fileName = "receipt-\(UUID().uuidString.prefix(8)).jpg"
        let url = try draftsDirectoryURL().appending(path: fileName, directoryHint: .notDirectory)
        try ensureDirectoryExists(at: draftsDirectoryURL())
        try data.write(to: url, options: .atomic)

        return ReceiptDraftAttachment(
            fileName: fileName,
            localURL: url,
            contentType: "image/jpeg",
            kind: .image
        )
    }

    static func createDraft(from fileURL: URL) throws -> ReceiptDraftAttachment {
        let ext = fileURL.pathExtension.lowercased()
        let kind: ReceiptAttachmentKind = ext == "pdf" ? .pdf : .image
        let contentType = ext == "pdf" ? "application/pdf" : "image/\(ext.isEmpty ? "jpeg" : ext)"
        let destinationName = "\(UUID().uuidString).\(ext.isEmpty ? (kind == .pdf ? "pdf" : "jpg") : ext)"
        let destinationURL = try draftsDirectoryURL().appending(path: destinationName, directoryHint: .notDirectory)

        try ensureDirectoryExists(at: draftsDirectoryURL())

        let didStartAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)

        return ReceiptDraftAttachment(
            fileName: fileURL.lastPathComponent,
            localURL: destinationURL,
            contentType: contentType,
            kind: kind
        )
    }

    @discardableResult
    static func persistDrafts(
        _ drafts: [ReceiptDraftAttachment],
        to transaction: Transaction,
        in modelContext: ModelContext
    ) throws -> [ReceiptAttachment] {
        try drafts.map { draft in
            try persistDraft(draft, to: transaction, in: modelContext)
        }
    }

    @discardableResult
    static func addImage(
        _ image: UIImage,
        to transaction: Transaction,
        in modelContext: ModelContext
    ) throws -> ReceiptAttachment {
        let draft = try createDraft(from: image)
        return try persistDraft(draft, to: transaction, in: modelContext)
    }

    @discardableResult
    static func addFile(
        from fileURL: URL,
        to transaction: Transaction,
        in modelContext: ModelContext
    ) throws -> ReceiptAttachment {
        let draft = try createDraft(from: fileURL)
        return try persistDraft(draft, to: transaction, in: modelContext)
    }

    static func persistDraft(
        _ draft: ReceiptDraftAttachment,
        to transaction: Transaction,
        in modelContext: ModelContext
    ) throws -> ReceiptAttachment {
        let txDirectory = try transactionDirectoryURL(for: transaction.id)
        try ensureDirectoryExists(at: txDirectory)

        let ext = draft.localURL.pathExtension.isEmpty
            ? (draft.kind == .pdf ? "pdf" : "jpg")
            : draft.localURL.pathExtension
        let storedFileName = "\(UUID().uuidString).\(ext)"
        let finalURL = txDirectory.appending(path: storedFileName, directoryHint: .notDirectory)

        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: draft.localURL, to: finalURL)

        let attachment = ReceiptAttachment(
            fileName: draft.fileName,
            storedFileName: storedFileName,
            contentType: draft.contentType,
            kind: draft.kind
        )
        attachment.transaction = transaction
        transaction.receiptAttachments.append(attachment)
        modelContext.insert(attachment)
        return attachment
    }

    static func remove(
        _ attachment: ReceiptAttachment,
        in modelContext: ModelContext
    ) {
        if let url = fileURL(for: attachment) {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(attachment)
    }

    @MainActor
    static func cleanupDraft(_ draft: ReceiptDraftAttachment) {
        try? FileManager.default.removeItem(at: draft.localURL)
    }

    @MainActor
    static func cleanupDrafts(_ drafts: [ReceiptDraftAttachment]) {
        drafts.forEach(cleanupDraft)
    }

    static func cleanupFiles(for transaction: Transaction) {
        transaction.receiptAttachments.forEach {
            if let url = fileURL(for: $0) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func fileURL(for attachment: ReceiptAttachment) -> URL? {
        try? transactionDirectoryURL(for: attachment.transaction?.id).appending(
            path: attachment.storedFileName,
            directoryHint: .notDirectory
        )
    }

    private static func transactionDirectoryURL(for transactionID: UUID?) throws -> URL {
        let id = transactionID?.uuidString ?? "unknown"
        let base = try receiptsDirectoryURL()
        return base.appending(path: id, directoryHint: .isDirectory)
    }

    private static func draftsDirectoryURL() throws -> URL {
        try receiptsDirectoryURL().appending(path: draftsDirectoryName, directoryHint: .isDirectory)
    }

    private static func receiptsDirectoryURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return appSupport.appending(path: receiptsDirectoryName, directoryHint: .isDirectory)
    }

    private static func ensureDirectoryExists(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
