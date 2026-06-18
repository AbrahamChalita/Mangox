// Core/Utilities/ImageProcessing.swift
import Accelerate
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ImageProcessing {

    nonisolated static let storySize = CGSize(width: 1080, height: 1920)
    nonisolated static let storyAspectRatio: CGFloat = 9.0 / 16.0

    enum StoryBackgroundError: LocalizedError {
        case unreadableImage
        case imageProcessingFailed
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                "Mangox couldn’t read that photo. Try a different image."
            case .imageProcessingFailed:
                "Mangox couldn’t prepare that photo for a Story."
            case .imageEncodingFailed:
                "Mangox couldn’t finish preparing that photo."
            }
        }
    }

    /// True when an image is already cropped/resampled to the Story export size (avoids double JPEG passes).
    nonisolated static func isStoryPrepared(_ image: UIImage) -> Bool {
        abs(image.size.width - storySize.width) < 0.5
            && abs(image.size.height - storySize.height) < 0.5
            && image.scale == 1
    }

    static func prepareStoryBackground(from image: UIImage) -> UIImage {
        if isStoryPrepared(image) { return image }
        return cropAndResample(image, to: storySize)
    }

    static func prepareStoryBackground(from imageData: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        return prepareStoryBackground(from: source)
    }

    /// Prepares picker data away from UI state and returns an orientation-correct 1080×1920 JPEG.
    /// Returning `Data` keeps the concurrency boundary Sendable; the caller creates `UIImage` on the main actor.
    nonisolated static func prepareStoryBackgroundData(from imageData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw StoryBackgroundError.unreadableImage
        }
        guard let thumbnail = makeOrientedThumbnail(from: source) else {
            throw StoryBackgroundError.imageProcessingFailed
        }
        let prepared = cropAndResample(UIImage(cgImage: thumbnail), to: storySize)
        guard let data = prepared.jpegData(compressionQuality: 0.92) else {
            throw StoryBackgroundError.imageEncodingFailed
        }
        return data
    }

    static func prepareStoryBackground(from source: CGImageSource) -> UIImage? {
        guard let thumbnail = makeOrientedThumbnail(from: source) else {
            return nil
        }
        return cropAndResample(UIImage(cgImage: thumbnail), to: storySize)
    }

    nonisolated private static func makeOrientedThumbnail(from source: CGImageSource) -> CGImage? {
        let maxDim = max(Int(storySize.width), Int(storySize.height))
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Aspect-fills `image` into `targetSize` using UIKit drawing so EXIF orientation is respected.
    nonisolated private static func cropAndResample(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let srcSize = image.size
        guard srcSize.width > 0, srcSize.height > 0 else { return image }

        let scale = max(targetSize.width / srcSize.width, targetSize.height / srcSize.height)
        let scaledSize = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
        let origin = CGPoint(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }
}
