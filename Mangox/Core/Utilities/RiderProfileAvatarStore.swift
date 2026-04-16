// Core/Utilities/RiderProfileAvatarStore.swift
import Foundation
import UIKit

extension Notification.Name {
    /// Posted after the on-disk rider profile photo is saved or removed so UI can reload (same `file://` URL otherwise caches in `AsyncImage`).
    static let mangoxRiderProfileAvatarDidChange = Notification.Name("com.abchalita.Mangox.riderProfileAvatarDidChange")
}

/// On-device profile photo (Application Support). Used when the rider is not on Strava or prefers a local avatar.
enum RiderProfileAvatarStore {
    private static let subdirectory = "Mangox"
    private static let fileName = "rider_profile_avatar.jpg"
    private static let maxDimension: CGFloat = 512

    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(subdirectory, isDirectory: true)
    }

    static var localAvatarFileURL: URL {
        directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    static var hasLocalAvatar: Bool {
        FileManager.default.fileExists(atPath: localAvatarFileURL.path)
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    static func saveLocalAvatar(_ image: UIImage) throws {
        try ensureDirectory()
        let scaled = scaleDown(image, maxSide: maxDimension)
        guard let data = scaled.jpegData(compressionQuality: 0.88) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: localAvatarFileURL, options: .atomic)
        NotificationCenter.default.post(name: .mangoxRiderProfileAvatarDidChange, object: nil)
    }

    static func clearLocalAvatar() {
        try? FileManager.default.removeItem(at: localAvatarFileURL)
        NotificationCenter.default.post(name: .mangoxRiderProfileAvatarDidChange, object: nil)
    }

    static func loadLocalAvatar() -> UIImage? {
        guard hasLocalAvatar else { return nil }
        return UIImage(contentsOfFile: localAvatarFileURL.path)
    }

    private static func scaleDown(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
