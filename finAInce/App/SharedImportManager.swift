import Foundation
import UniformTypeIdentifiers

struct SharedImportFile: Identifiable {
    let id = UUID()
    let url: URL
}

@Observable final class SharedImportManager {
    static let shared = SharedImportManager()

    var pendingFile: SharedImportFile?
    var errorMessage: String?

    private let supportedExtensions = ["csv", "tsv", "txt", "xlsx", "xls"]

    private init() {}

    func handleSharedFile(_ url: URL) {
        guard isSupportedFile(url) else {
            errorMessage = "Formato não suportado. Escolha um arquivo CSV, TXT ou Excel."
            return
        }

        do {
            let localURL = try copyIntoImportInbox(url)
            pendingFile = SharedImportFile(url: localURL)
        } catch {
            errorMessage = "Não foi possível abrir o arquivo compartilhado."
        }
    }

    func clearPendingFile() {
        pendingFile = nil
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
            type.identifier == "com.microsoft.excel.xls"
    }

    private func copyIntoImportInbox(_ sourceURL: URL) throws -> URL {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let inboxURL = fileManager.temporaryDirectory.appendingPathComponent("SharedImports", isDirectory: true)
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let fileName = sourceURL.lastPathComponent.isEmpty ? "import.csv" : sourceURL.lastPathComponent
        let destinationURL = inboxURL.appendingPathComponent("\(UUID().uuidString)-\(fileName)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}
