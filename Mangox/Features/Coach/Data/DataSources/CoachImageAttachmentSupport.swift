import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// User-attached photo for a coach turn (head unit, bike fit, race profile, etc.).
struct CoachUserImageAttachment: Sendable {
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int

    var cgImage: CGImage? {
        #if canImport(UIKit)
        return UIImage(data: jpegData)?.cgImage
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    var uiImage: UIImage? { UIImage(data: jpegData) }

    static func fromUIImage(_ image: UIImage, maxDimension: CGFloat = 1536, compressionQuality: CGFloat = 0.82)
        -> CoachUserImageAttachment?
    {
        let scaled = image.mangoxCoachScaled(maxDimension: maxDimension)
        guard let data = scaled.jpegData(compressionQuality: compressionQuality) else { return nil }
        return CoachUserImageAttachment(
            jpegData: data,
            pixelWidth: Int(scaled.size.width * scaled.scale),
            pixelHeight: Int(scaled.size.height * scaled.scale)
        )
    }
    #endif
}

#if canImport(UIKit)
private extension UIImage {
    func mangoxCoachScaled(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
enum CoachFoundationModelsPromptSupport {
    /// Builds a coach turn prompt with optional vision input (`Attachment` / `Transcript.ImageAttachment`).
    @PromptBuilder
    static func coachTurnPrompt(
        trainingSnapshot: String,
        userMessage: String,
        image: CoachUserImageAttachment?
    ) -> Prompt {
        """
        Training snapshot (verified Mangox data):
        \(trainingSnapshot)

        User message:
        \(userMessage)
        """
        if let cgImage = image?.cgImage {
            Attachment(cgImage)
        }
    }
}
#endif
