import Foundation
import SwiftData

// MARK: - CostCenterFile (attachment linked to a project)

@Model
final class CostCenterFile {
    var id: UUID = UUID()
    var costCenterId: UUID = UUID()
    /// Display name (original filename for documents, UUID-based for captured photos).
    var fileName: String = ""
    /// Lowercase file extension: "jpg", "pdf", "docx", "xlsx", etc.
    var fileType: String = "jpg"
    /// Path relative to the app's Documents directory.
    var localPath: String?
    var createdAt: Date = Date()

    init(
        costCenterId: UUID,
        fileName: String,
        fileType: String,
        localPath: String? = nil
    ) {
        self.id = UUID()
        self.costCenterId = costCenterId
        self.fileName = fileName
        self.fileType = fileType
        self.localPath = localPath
        self.createdAt = Date()
    }
}

extension CostCenterFile {
    var localURL: URL? {
        guard let localPath else { return nil }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(localPath)
    }

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp",
        // legacy value stored before this refactor
        "image"
    ]

    var isImage: Bool { Self.imageExtensions.contains(fileType.lowercased()) }
    var isPDF:   Bool { fileType.lowercased() == "pdf" }

    /// SF Symbol name that best represents this file type.
    var fileIcon: String {
        switch fileType.lowercased() {
        case "image", "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp":
            return "photo.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx", "csv":
            return "tablecells.fill"
        case "ppt", "pptx":
            return "rectangle.stack.fill"
        case "txt", "md", "rtf":
            return "doc.plaintext.fill"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox.fill"
        case "mp4", "mov", "avi", "mkv", "m4v":
            return "video.fill"
        case "mp3", "m4a", "wav", "aac", "flac":
            return "music.note"
        default:
            return "doc.fill"
        }
    }

    /// Accent color name for `fileIcon` — kept as a string so the model layer stays UI-free.
    var fileIconColorName: String {
        switch fileType.lowercased() {
        case "image", "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp":
            return "blue"
        case "pdf":
            return "red"
        case "doc", "docx":
            return "blue"
        case "xls", "xlsx", "csv":
            return "green"
        case "ppt", "pptx":
            return "orange"
        case "zip", "rar", "7z", "tar", "gz":
            return "yellow"
        case "mp4", "mov", "avi", "mkv", "m4v":
            return "purple"
        case "mp3", "m4a", "wav", "aac", "flac":
            return "pink"
        default:
            return "gray"
        }
    }

    /// Saves raw `Data` to disk (used for camera/gallery captures).
    /// - Parameters:
    ///   - originalName: Display name override; defaults to a UUID-based name.
    static func create(
        forProject projectId: UUID,
        data: Data,
        fileType: String,
        ext: String,
        originalName: String? = nil
    ) throws -> CostCenterFile {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProjectFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let safeExt   = ext.isEmpty ? "bin" : ext
        let storedName = "\(UUID().uuidString).\(safeExt)"
        let fileURL    = dir.appendingPathComponent(storedName)
        try data.write(to: fileURL)

        return CostCenterFile(
            costCenterId: projectId,
            fileName: originalName ?? storedName,
            fileType: fileType.lowercased(),
            localPath: "ProjectFiles/\(storedName)"
        )
    }

    /// Copies an already-accessible file URL into the app's ProjectFiles directory.
    /// Use this for document picker results (opened with `asCopy: true`).
    static func create(
        forProject projectId: UUID,
        copyingFrom sourceURL: URL
    ) throws -> CostCenterFile {
        let ext  = sourceURL.pathExtension.lowercased()
        let data = try Data(contentsOf: sourceURL)
        return try create(
            forProject: projectId,
            data: data,
            fileType: ext.isEmpty ? "file" : ext,
            ext: ext.isEmpty ? "bin" : ext,
            originalName: sourceURL.lastPathComponent
        )
    }

    func deleteFromDisk() {
        guard let url = localURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
