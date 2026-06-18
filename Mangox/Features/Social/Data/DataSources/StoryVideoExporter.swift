// Features/Social/Data/DataSources/StoryVideoExporter.swift
import AVFoundation
import CoreVideo
import UIKit

/// Writes a short 1080×1920 MP4 from the rendered story card for sharing to Reels / Photos.
///
/// The Instagram Stories pasteboard API only accepts images, so video sharing routes through the system
/// share sheet (`UIActivityViewController`), which can hand an MP4 to Reels, Photos, or any video target.
///
/// The current animation is a polished baseline: fade-in over the first ~0.4s, a slow Ken-Burns zoom
/// (1.0 → 1.06) across the next ~2.0s, then a ~0.6s hold. Per-frame count-up stats and a drawing-in
/// power profile require renderer parameterization and are a follow-up enhancement.
@MainActor
enum StoryVideoExporter {

    struct Options: Sendable {
        var size: CGSize
        var fps: Int = 30
        var duration: TimeInterval = 3.0
    }

    enum ExportError: Error {
        case writerStart(Error?)
        case writerIncomplete(Error?)
    }

    /// Renders `card` into a fade + Ken-Burns reveal MP4 at `url`.
    /// `progress` reports 0–1 as frames are written. Runs on the main actor (frame rendering uses
    /// `UIGraphicsImageRenderer`); yields every few frames so the UI can update the progress overlay.
    @discardableResult
    static func exportReveal(
        card: UIImage,
        options: Options,
        to url: URL,
        progress: (Double) -> Void
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(options.size.width),
            AVVideoHeightKey: Int(options.size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)

        try writer.start()
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(options.duration * Double(options.fps)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        for i in 0..<frameCount {
            let t = frameCount == 1 ? 1.0 : Double(i) / Double(frameCount - 1)
            let frame = renderFrame(card: card, t: t, size: options.size, format: format)
            let pts = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(options.fps))
            try Self.appendFrame(frame, size: options.size, receiver: receiver, pts: pts)

            progress(Double(i + 1) / Double(frameCount))
            if i % 3 == 0 { await Task.yield() }
        }

        input.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw ExportError.writerIncomplete(writer.error)
        }
        return url
    }

    // MARK: - Frame composite

    private static func renderFrame(card: UIImage, t: Double, size: CGSize, format: UIGraphicsImageRendererFormat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let fadeInEnd = 0.133
            let zoomEnd = 0.8
            let fade = min(1.0, t / fadeInEnd)
            let zoom = 1.0 + 0.06 * max(0, min(1, (t - fadeInEnd) / (zoomEnd - fadeInEnd)))

            let w = size.width * zoom
            let h = size.height * zoom
            let rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)

            ctx.cgContext.saveGState()
            ctx.cgContext.setAlpha(fade)
            card.draw(in: rect)
            ctx.cgContext.restoreGState()
        }
    }

    /// Creates a CVPixelBuffer, renders `frame` into it, and appends it to the writer.
    /// `nonisolated` so the non-Sendable `CVPixelBuffer` never crosses an actor boundary — only the
    /// Sendable `UIImage` frame and `PixelBufferReceiver` are passed in from the main-actor orchestrator.
    nonisolated static func appendFrame(
        _ frame: UIImage,
        size: CGSize,
        receiver: AVAssetWriterInput.PixelBufferReceiver,
        pts: CMTime
    ) throws {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else {
            return
        }

        CVPixelBufferLockBaseAddress(buffer, [])

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer),
           let context = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
           ),
           let cgImage = frame.cgImage {
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }

        // Unlock before appending: the writer retains the buffer and encodes it asynchronously,
        // so the CPU draw lock must not be held across the hand-off.
        CVPixelBufferUnlockBaseAddress(buffer, [])

        _ = try receiver.appendImmediately(CVReadOnlyPixelBuffer(unsafeBuffer: buffer), with: pts)
    }
}
