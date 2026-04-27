import Foundation
import UIKit

final class ProfileCloudSyncStore {
    static let shared = ProfileCloudSyncStore()

    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let nameKey = "icloud.profile.name.v1"
    private let photoKey = "icloud.profile.photo.v1"
    private let defaultName = "Meu Perfil"

    private init() {}

    func syncFromCloud(localName: String, localPhotoData: Data, isConfiguredDevice: Bool) -> (name: String, photoData: Data) {
        guard isConfiguredDevice else {
            return (localName, localPhotoData)
        }

        ubiquitousStore.synchronize()

        let cloudName = sanitizedName(ubiquitousStore.string(forKey: nameKey))
        let resolvedName = cloudName ?? localName
        let resolvedPhotoData = ubiquitousStore.data(forKey: photoKey) ?? localPhotoData

        DebugLaunchLog.log("👤 [Profile] syncFromCloud localName=\(localName) cloudName=\(cloudName ?? "nil") localPhotoBytes=\(localPhotoData.count) cloudPhotoBytes=\((ubiquitousStore.data(forKey: photoKey) ?? Data()).count)")

        return (resolvedName, resolvedPhotoData)
    }

    func publish(name: String, photoData: Data, isConfiguredDevice: Bool) {
        guard isConfiguredDevice else {
            return
        }

        let sanitized = sanitizedName(name)
        if let sanitized {
            ubiquitousStore.set(sanitized, forKey: nameKey)
        }

        if photoData.isEmpty {
            ubiquitousStore.removeObject(forKey: photoKey)
        } else if let compactPhoto = compactAvatarData(from: photoData) {
            ubiquitousStore.set(compactPhoto, forKey: photoKey)
        }

        ubiquitousStore.synchronize()
        DebugLaunchLog.log("👤 [Profile] publish name=\(sanitized ?? "nil") photoBytes=\(photoData.count)")
    }

    private func sanitizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != defaultName else { return nil }
        return trimmed
    }

    private func compactAvatarData(from originalData: Data) -> Data? {
        guard let image = UIImage(data: originalData) else {
            return nil
        }

        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let scaledImage = renderer.image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (side - drawSize.width) / 2,
                y: (side - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }

        return scaledImage.jpegData(compressionQuality: 0.72)
    }
}
