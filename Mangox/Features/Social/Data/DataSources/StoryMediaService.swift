import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

enum StoryMediaService {
    enum MediaError: LocalizedError {
        case noPhotoData
        case invalidPreparedImage
        case photoAccessDenied
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .noPhotoData:
                "Mangox couldn’t load that photo. Try downloading it from iCloud or choosing another image."
            case .invalidPreparedImage:
                "Mangox couldn’t turn that photo into a Story background."
            case .photoAccessDenied:
                "Allow Mangox to add photos in Settings to save Story cards."
            case .saveFailed:
                "The Story card couldn’t be saved to Photos."
            }
        }
    }

    @MainActor
    static func loadStoryBackground(from item: PhotosPickerItem) async throws -> UIImage {
        guard let sourceData = try await item.loadTransferable(type: Data.self) else {
            throw MediaError.noPhotoData
        }
        try Task.checkCancellation()
        let preparedData = try await Task.detached(priority: .userInitiated) { () throws -> Data in
            try Task.checkCancellation()
            return try ImageProcessing.prepareStoryBackgroundData(from: sourceData)
        }.value
        try Task.checkCancellation()
        guard let image = UIImage(data: preparedData) else {
            throw MediaError.invalidPreparedImage
        }
        return image
    }

    @MainActor
    static func saveToPhotos(_ image: UIImage) async throws {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw MediaError.photoAccessDenied
        }

        guard let data = image.jpegData(compressionQuality: 0.95) else {
            throw MediaError.saveFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mangox-story-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
        } catch {
            throw MediaError.saveFailed
        }
    }
}
