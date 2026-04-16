// Core/Utilities/ImageProcessing.swift
import Accelerate
import UIKit

enum ImageProcessing {

    static let storySize = CGSize(width: 1080, height: 1920)
    static let storyAspectRatio: CGFloat = 9.0 / 16.0

    static func prepareStoryBackground(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        return cropAndResample(cgImage, to: storySize)
    }

    static func prepareStoryBackground(from imageData: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        return prepareStoryBackground(from: source)
    }

    static func prepareStoryBackground(from source: CGImageSource) -> UIImage? {
        let targetW = Int(storySize.width)
        let targetH = Int(storySize.height)
        let maxDim = max(targetW, targetH)

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return cropAndResample(thumbnail, to: storySize)
    }

    private static func cropAndResample(_ cgImage: CGImage, to targetSize: CGSize) -> UIImage {
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let srcAspect = srcW / srcH
        let targetAspect = targetSize.width / targetSize.height

        let cropRect: CGRect
        if srcAspect > targetAspect {
            let cropW = srcH * targetAspect
            let cropX = (srcW - cropW) / 2
            cropRect = CGRect(x: cropX, y: 0, width: cropW, height: srcH)
        } else {
            let cropH = srcW / targetAspect
            let cropY = (srcH - cropH) / 2
            cropRect = CGRect(x: 0, y: cropY, width: srcW, height: cropH)
        }

        guard let cropped = cgImage.cropping(to: cropRect) else {
            return UIImage(cgImage: cgImage)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { ctx in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}