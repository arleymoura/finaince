import Foundation

struct ImportedStatementSummary: Codable, Equatable {
    let fileName: String
    let storedAt: Date
    let totalCount: Int
    let newCount: Int
    let reconciledCount: Int
    let accountId: UUID?
}

enum ImportStatementStore {
    private static let directoryName = "Imports"
    private static let statementFileName = "latest-import"
    private static let metadataFileName = "latest-import.json"

    static func currentSummary() -> ImportedStatementSummary? {
        guard let metadataURL = try? metadataURL(),
              let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }
        return try? JSONDecoder().decode(ImportedStatementSummary.self, from: data)
    }

    static func currentFileURL() -> URL? {
        guard let fileURL = try? statementURL(),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return fileURL
    }

    static func replaceCurrentFile(
        with sourceURL: URL,
        accountId: UUID? = nil
    ) throws -> ImportedStatementSummary {
        try ensureDirectoryExists()

        let ext = sourceURL.pathExtension.isEmpty ? "csv" : sourceURL.pathExtension
        let targetURL = try importsDirectoryURL()
            .appending(path: "\(statementFileName).\(ext)", directoryHint: .notDirectory)

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fm = FileManager.default
        if let existing = currentFileURL(), fm.fileExists(atPath: existing.path) {
            try? fm.removeItem(at: existing)
        }
        if fm.fileExists(atPath: targetURL.path) {
            try fm.removeItem(at: targetURL)
        }
        try fm.copyItem(at: sourceURL, to: targetURL)

        let summary = ImportedStatementSummary(
            fileName: sourceURL.lastPathComponent,
            storedAt: Date(),
            totalCount: 0,
            newCount: 0,
            reconciledCount: 0,
            accountId: accountId
        )
        try saveSummary(summary)
        return summary
    }

    static func updateSummary(
        fileName: String,
        accountId: UUID?,
        totalCount: Int,
        newCount: Int,
        reconciledCount: Int
    ) throws {
        let summary = ImportedStatementSummary(
            fileName: fileName,
            storedAt: Date(),
            totalCount: totalCount,
            newCount: newCount,
            reconciledCount: reconciledCount,
            accountId: accountId
        )
        try saveSummary(summary)
    }

    private static func saveSummary(_ summary: ImportedStatementSummary) throws {
        let data = try JSONEncoder().encode(summary)
        try data.write(to: try metadataURL(), options: .atomic)
    }

    private static func importsDirectoryURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return appSupport.appending(path: directoryName, directoryHint: .isDirectory)
    }

    private static func metadataURL() throws -> URL {
        try importsDirectoryURL().appending(path: metadataFileName, directoryHint: .notDirectory)
    }

    private static func statementURL() throws -> URL {
        let dir = try importsDirectoryURL()
        let candidates = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        if let match = candidates.first(where: { $0.deletingPathExtension().lastPathComponent == statementFileName }) {
            return match
        }
        return dir.appending(path: "\(statementFileName).csv", directoryHint: .notDirectory)
    }

    private static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: try importsDirectoryURL(),
            withIntermediateDirectories: true
        )
    }
}
