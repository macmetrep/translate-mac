import CoreImage
import Foundation
import Translation
import Vision

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

public class TranslateWorker {
  public struct Config {
    let showBoxes: Bool
    let showTranslations: Bool

    public init(showBoxes: Bool = true, showTranslations: Bool = true) {
      self.showBoxes = showBoxes
      self.showTranslations = showTranslations
    }
  }

  private var config: Config

  public init(config: Config = Config()) {
    self.config = config
  }

  public func updateConfig(showBoxes: Bool, showTranslations: Bool) {
    config = Config(showBoxes: showBoxes, showTranslations: showTranslations)
  }

  public func translateImage(at url: URL, using session: TranslationSession) async throws -> URL {
    print("Starting translation of image at \(url)")

    // 1. Load the image
    guard let image = CIImage(contentsOf: url) else {
      print("Failed to load image at \(url)")
      throw TranslationError.invalidImage
    }
    print("Successfully loaded image")

    // 2. Detect text regions using Vision
    let textRegions = try await detectTextRegions(in: image)
    print("Detected \(textRegions.count) text regions")

    // 3. Recognize Japanese text
    let japaneseTexts = try await recognizeJapaneseText(in: image, regions: textRegions)
    print("Recognized \(japaneseTexts.count) Japanese text segments")

    // 4. Translate texts to English
    let translatedTexts = try await translateTexts(japaneseTexts, using: session)
    print("Translated \(translatedTexts.count) text segments")

    // 5. Create new image with translated text
    let triplets = createTranslationTriplet(
      regions: textRegions,
      japaneseTexts: japaneseTexts,
      translatedTexts: translatedTexts
    )
    print("Filtered out \(japaneseTexts.count - triplets.count) English text segments")

    let translatedImage = try await replaceText(
      in: image,
      triplets: triplets
    )
    print("Created translated image")

    // 6. Save image and translations
    let baseURL = url.deletingLastPathComponent()
    let imageName = url.deletingPathExtension().lastPathComponent

    let imageURL = baseURL.appendingPathComponent("translated_\(url.lastPathComponent)")
    let translationsURL = baseURL.appendingPathComponent("\(imageName)_translations.txt")

    // Save image
    try translatedImage.save(to: imageURL)
    print("Saved translated image to \(imageURL)")

    // Save translations
    var translationsText = "[translations]\n"
    for (japanese, english) in zip(japaneseTexts, translatedTexts) {
      translationsText += "\"\(japanese)\"=\"\(english)\"\n"
    }
    try translationsText.write(to: translationsURL, atomically: true, encoding: .utf8)
    print("Saved translations to \(translationsURL)")

    return imageURL
  }

  private func detectTextRegions(in image: CIImage) async throws -> [VNTextObservation] {
    var textObservations: [VNTextObservation] = []

    let request = VNRecognizeTextRequest { request, error in
      guard error == nil else {
        print("Text detection error: \(String(describing: error))")
        return
      }
      if let results = request.results as? [VNRecognizedTextObservation] {
        // Convert VNRecognizedTextObservation to VNTextObservation
        textObservations = results.map { observation in
          let textObservation = VNTextObservation(boundingBox: observation.boundingBox)
          return textObservation
        }
      }
    }

    request.recognitionLanguages = ["ja"]
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(ciImage: image)
    try handler.perform([request])

    print("Text detection results count: \(textObservations.count)")
    return textObservations
  }

  private func recognizeJapaneseText(
    in image: CIImage,
    regions: [VNTextObservation]
  ) async throws -> [String] {
    var recognizedTexts: [String] = []

    let request = VNRecognizeTextRequest { request, error in
      guard error == nil else { return }
      guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

      for observation in observations {
        if let topCandidate = observation.topCandidates(1).first {
          recognizedTexts.append(topCandidate.string)
        }
      }
    }

    request.recognitionLanguages = ["ja"]
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(ciImage: image)
    try handler.perform([request])

    return recognizedTexts
  }

  private func translateTexts(_ texts: [String], using session: TranslationSession) async throws
    -> [String]
  {
    var translatedTexts: [String] = []

    for text in texts {
      let response = try await session.translate(text)
      translatedTexts.append(response.targetText)
    }

    return translatedTexts
  }

  // Keep isEnglish helper function for future use
  private func isEnglish(_ text: String) -> Bool {
    let englishLetters = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    let englishCharCount = text.unicodeScalars.filter { englishLetters.contains($0) }.count
    let totalCharCount = text.unicodeScalars.count

    return totalCharCount > 0 && Double(englishCharCount) / Double(totalCharCount) > 0.7
  }

  private func replaceText(
    in image: CIImage,
    triplets: [(VNTextObservation, String, String)]
  ) async throws -> CIImage {
    let context = CIContext()
    guard let cgImage = context.createCGImage(image, from: image.extent) else {
      throw TranslationError.imageGenerationFailed
    }

    let size = CGSize(width: cgImage.width, height: cgImage.height)

    #if os(iOS)
      let finalImage = createImageiOS(
        size: size,
        cgImage: cgImage,
        triplets: triplets
      )
    #elseif os(macOS)
      let finalImage = try createImageMacOS(
        size: size,
        cgImage: cgImage,
        triplets: triplets
      )
    #endif

    #if os(iOS)
      guard let cgImage = finalImage.cgImage else {
        throw TranslationError.imageGenerationFailed
      }
      let outputCIImage = CIImage(cgImage: cgImage)
    #elseif os(macOS)
      var proposedRect: NSRect = .zero
      guard
        let cgImage = finalImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
      else {
        throw TranslationError.imageGenerationFailed
      }
      let outputCIImage = CIImage(cgImage: cgImage)
    #endif

    return outputCIImage
  }

  #if os(iOS)
    private func createImageiOS(
      size: CGSize,
      cgImage: CGImage,
      triplets: [(VNTextObservation, String, String)]
    ) -> UIImage {
      let renderer = UIGraphicsImageRenderer(size: size)

      return renderer.image { context in
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
    }
  #elseif os(macOS)
    private func createImageMacOS(
      size: CGSize,
      cgImage: CGImage,
      triplets: [(VNTextObservation, String, String)]
    ) throws -> NSImage {
      let image = NSImage(size: size)

      image.lockFocus()
      defer { image.unlockFocus() }

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

      return image
    }
  #endif

  private func createTranslationTriplet(
    regions: [VNTextObservation],
    japaneseTexts: [String],
    translatedTexts: [String]
  ) -> [(VNTextObservation, String, String)] {
    return zip(zip(regions, japaneseTexts), translatedTexts)
      .map { (($0.0, $0.1, $1)) }
      .filter { !isEnglish($0.1) }  // Filter based on Japanese text
  }
}

enum TranslationError: Error {
  case invalidImage
  case textRecognitionFailed
  case translationFailed
  case imageGenerationFailed
}

// Add this extension to CIImage for saving
extension CIImage {
  func save(to url: URL) throws {
    let context = CIContext()
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw TranslationError.imageGenerationFailed
    }

    try context.writePNGRepresentation(
      of: self,
      to: url,
      format: .RGBA8,
      colorSpace: colorSpace
    )
  }
}
