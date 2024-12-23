#if os(iOS)
  #if canImport(UIKit)
    import UIKit
  #endif
  import Vision

  /// Warning, untested!
  public class IOSImageCreator: PlatformImageCreator {
    public init() {}

    public func createImage(
      size: CGSize, cgImage: CGImage, triplets: [(VNTextObservation, String, String)],
      config: TranslateWorker.Config
    ) throws -> CIImage {
      let renderer = UIGraphicsImageRenderer(size: size)

      let finalImage = renderer.image { context in
        // Draw original image
        UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))

        for (region, _, translatedText) in triplets {
          let boundingBox = region.boundingBox
          let rect = CGRect(
            x: boundingBox.origin.x * size.width,
            y: boundingBox.origin.y * size.height,
            width: boundingBox.width * size.width,
            height: boundingBox.height * size.height
          )

          if config.showBoxes {
            // Draw rectangle
            context.cgContext.setStrokeColor(UIColor.red.cgColor)
            context.cgContext.setLineWidth(2.0)
            context.cgContext.stroke(rect)
          }

          if config.showTranslations {
            // Draw translated text
            let attributes: [NSAttributedString.Key: Any] = [
              .foregroundColor: UIColor.white,
              .backgroundColor: UIColor.black.withAlphaComponent(0.7),
            ]

            // Find font size that fits
            var fontSize: CGFloat = 24
            var textSize: CGSize
            repeat {
              let font = UIFont.systemFont(ofSize: fontSize)
              textSize = translatedText.size(withAttributes: [.font: font])
              fontSize -= 1
            } while (textSize.width > rect.width || textSize.height > rect.height) && fontSize > 8

            let finalAttributes = attributes.merging([.font: UIFont.systemFont(ofSize: fontSize)]) {
              $1
            }
            let textRect = CGRect(
              x: rect.minX,
              y: rect.minY + (rect.height - textSize.height) / 2,
              width: rect.width,
              height: textSize.height
            )

            translatedText.draw(in: textRect, withAttributes: finalAttributes)
          }
        }
      }

      guard let cgImage = finalImage.cgImage else {
        throw TranslationError.imageGenerationFailed
      }
      return CIImage(cgImage: cgImage)
    }
  }
#endif
