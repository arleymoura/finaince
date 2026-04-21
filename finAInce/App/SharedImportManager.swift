import Foundation
import UIKit
import UniformTypeIdentifiers

struct SharedImportFile: Identifiable {
    let id = UUID()
    let url: URL
}

@Observable final class SharedImportManager {
    static let shared = SharedImportManager()

    var pendingFile: SharedImportFile?
    var errorMessage: String?

    /// Image shared from another app via the Share Extension.
    /// `ChatView` reads this on appear and pre-populates `attachedImage`.
    var pendingSharedImage: UIImage? = nil

    private let appGroupID    = "group.Moura.finaince"
    private let imageFileName = "shared_image.jpg"
    private let supportedExtensions = ["csv", "tsv", "txt", "xlsx", "xls"]

    private init() {}

    func handleSharedFile(_ url: URL) {
        guard isSupportedFile(url) else {
            errorMessage = "Formato não suportado. Escolha um arquivo CSV, TXT ou Excel."
            return
        }

        pendingFile = SharedImportFile(url: url)
    }

    func clearPendingFile() {
        pendingFile = nil
    }

    // MARK: - Shared Image (from Share Extension via App Group)

    /// Reads the image saved by the Share Extension from the App Group container.
    /// Stores it in `pendingSharedImage` and deletes the file (one-shot delivery).
    func handleSharedImage() {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID
            )
        else { return }

        let src = containerURL.appendingPathComponent(imageFileName)
        guard
            FileManager.default.fileExists(atPath: src.path),
            let data = try? Data(contentsOf: src),
            let image = UIImage(data: data)
        else { return }

        // Consume the file so it isn't re-delivered on next cold launch
        try? FileManager.default.removeItem(at: src)

        pendingSharedImage = image
    }

    func clearPendingSharedImage() {
        pendingSharedImage = nil
    }

    private func isSupportedFile(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if supportedExtensions.contains(fileExtension) { return true }

        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }

        return type.conforms(to: .commaSeparatedText) ||
            type.conforms(to: .tabSeparatedText) ||
            type.conforms(to: .plainText) ||
            type.conforms(to: .text) ||
            type.identifier == "org.openxmlformats.spreadsheetml.sheet" ||
            type.identifier == "com.microsoft.excel.xls" ||
            type.identifier == "com.microsoft.excel.xlsx"
    }
}
