#if os(macOS)
  #if canImport(AppKit)
    import AppKit
  #endif
  import Vision

  public class MacOSImageCreator: PlatformImageCreator {
    public init() {}

    public func createImage(
      size: CGSize, cgImage: CGImage, triplets: [(VNTextObservation, String, String)],
      config: TranslateWorker.Config
    ) throws -> CIImage {
      // Create bitmap representation
      guard
        let bitmapRep = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: Int(size.width),
          pixelsHigh: Int(size.height),
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        )
      else {
        print("Failed to create bitmap representation")
        throw TranslationError.imageGenerationFailed
      }

      // Set up graphics context
      NSGraphicsContext.saveGraphicsState()
      defer { NSGraphicsContext.restoreGraphicsState() }

      guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
        print("Failed to create graphics context")
        throw TranslationError.imageGenerationFailed
      }
      NSGraphicsContext.current = context

      // Draw original image
      let imageRect = CGRect(origin: .zero, size: size)
      NSImage(cgImage: cgImage, size: size).draw(in: imageRect)

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
          NSColor.red.setStroke()
          let path = NSBezierPath()
          path.lineWidth = 2.0
          path.appendRect(rect)
          path.stroke()
        }

        if config.showTranslations {
          // Draw translated text
          let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7),
          ]

          // Find font size that fits
          var fontSize: CGFloat = 24
          var textSize: CGSize
          repeat {
            let font = NSFont.systemFont(ofSize: fontSize)
            textSize = translatedText.size(withAttributes: [.font: font])
            fontSize -= 1
          } while (textSize.width > rect.width || textSize.height > rect.height) && fontSize > 8

          let finalAttributes = attributes.merging([.font: NSFont.systemFont(ofSize: fontSize)]) {
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

      // Convert to CGImage
      guard let outputCGImage = bitmapRep.cgImage else {
        print("Failed to convert bitmap representation to CGImage")
        throw TranslationError.imageGenerationFailed
      }

      print("Successfully converted to CGImage")
      return CIImage(cgImage: outputCGImage)
    }
  }
#endif
