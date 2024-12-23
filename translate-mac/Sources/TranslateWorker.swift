import CoreImage
import Foundation
import Translation
import Vision

public protocol PlatformImageCreator {
  func createImage(
    size: CGSize, cgImage: CGImage, triplets: [(VNTextObservation, String, String)],
    config: TranslateWorker.Config
  ) throws -> CIImage
}

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
  private let imageCreator: PlatformImageCreator

  public init(config: Config = Config()) {
    self.config = config
    #if os(macOS)
      self.imageCreator = MacOSImageCreator()
    #elseif os(iOS)
      self.imageCreator = IOSImageCreator()
    #endif
  }

  public func updateConfig(showBoxes: Bool, showTranslations: Bool) {
    config = Config(showBoxes: showBoxes, showTranslations: showTranslations)
  }

  public func translateImage(
    at url: URL, destinationDirectory: URL?, using session: TranslationSession
  ) async throws -> URL {
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
    let imageName = url.deletingPathExtension().lastPathComponent
    let saveDirectory = destinationDirectory ?? url.deletingLastPathComponent()

    // Create translatedText directory
    let textDirectory = saveDirectory.appendingPathComponent("translatedText", isDirectory: true)
    try FileManager.default.createDirectory(at: textDirectory, withIntermediateDirectories: true)

    let imageURL = saveDirectory.appendingPathComponent("\(imageName).png")
    let translationsURL = textDirectory.appendingPathComponent("\(imageName).txt")

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
    var detectionError: Error?

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        detectionError = error
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

    if let error = detectionError {
      throw TranslationError.textRecognitionFailed
    }

    print("Text detection results count: \(textObservations.count)")
    if textObservations.isEmpty {
      throw TranslationError.textRecognitionFailed
    }
    return textObservations
  }

  private func recognizeJapaneseText(
    in image: CIImage,
    regions: [VNTextObservation]
  ) async throws -> [String] {
    var recognizedTexts: [String] = []
    var recognitionError: Error?

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        recognitionError = error
        return
      }
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

    if recognitionError != nil {
      throw TranslationError.textRecognitionFailed
    }

    if recognizedTexts.isEmpty {
      throw TranslationError.textRecognitionFailed
    }

    return recognizedTexts
  }

  private func translateTexts(_ texts: [String], using session: TranslationSession) async throws
    -> [String]
  {
    var translatedTexts: [String] = []
    var translationErrors: [Error] = []

    for text in texts {
      do {
        let response = try await session.translate(text)
        translatedTexts.append(response.targetText)
      } catch {
        translationErrors.append(error)
      }
    }

    // If we have some translations but not all, we can still proceed
    if !translatedTexts.isEmpty {
      return translatedTexts
    }

    // If we have no translations at all, throw an error
    if !translationErrors.isEmpty {
      throw TranslationError.translationFailed
    }

    return translatedTexts
  }

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
    return try imageCreator.createImage(
      size: size, cgImage: cgImage, triplets: triplets, config: config)
  }

  private func createTranslationTriplet(
    regions: [VNTextObservation],
    japaneseTexts: [String],
    translatedTexts: [String]
  ) -> [(VNTextObservation, String, String)] {
    return zip(zip(regions, japaneseTexts), translatedTexts)
      .map { (($0.0, $0.1, $1)) }
      .filter { !isEnglish($0.1) }  // Filter out english text
  }
}

enum TranslationError: LocalizedError {
  case invalidImage
  case textRecognitionFailed
  case translationFailed
  case imageGenerationFailed

  public var errorDescription: String? {
    switch self {
    case .invalidImage:
      return "Unable to load the image. Please make sure it's a valid image file."
    case .textRecognitionFailed:
      return
        "Failed to recognize text in the image. Please ensure the image is clear and contains readable text."
    case .translationFailed:
      return "Failed to translate the text. Please check your internet connection and try again."
    case .imageGenerationFailed:
      return "Failed to generate the translated image. Please try again with a different image."
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .invalidImage:
      return
        "Try using a different image file format (like PNG or JPEG) or selecting a different image."
    case .textRecognitionFailed:
      return
        "Try using an image with better lighting and contrast, or make sure the text is not too small or blurry."
    case .translationFailed:
      return
        "Check your internet connection and try again. If the problem persists, the translation service might be temporarily unavailable."
    case .imageGenerationFailed:
      return
        "Try using a smaller image or one with less text. If the problem persists, try restarting the application."
    }
  }
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
