import SwiftUI
import Translation
import UniformTypeIdentifiers

public struct TranslateImageView: View {
  @State private var selectedImage: URL?
  @State private var translatedImage: URL?
  @State private var isTranslating = false
  @State private var error: Error?
  @State private var statusMessage = ""
  @State private var configuration: TranslationSession.Configuration?
  @State private var showBoxes = false
  @State private var showTranslations = true
  @State private var isDirectoryMode = false
  @State private var selectedDirectory: URL?
  @State private var imageQueue: [URL] = []
  @State private var completedImages: [URL] = []
  @State private var currentProgress = 0.0

  private let worker: TranslateWorker

  public init() {
    self.worker = TranslateWorker(config: .init(showBoxes: false, showTranslations: true))
  }

  public var body: some View {
    VStack(spacing: 20) {
      Text("Japanese Comic Translator")
        .font(.title)
        .padding(.bottom)

      Picker("Mode", selection: $isDirectoryMode) {
        Text("Single Image").tag(false)
        Text("Directory").tag(true)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .onChange(of: isDirectoryMode) { oldValue, newValue in
        // Reset state when switching modes
        selectedImage = nil
        selectedDirectory = nil
        translatedImage = nil
        imageQueue = []
        completedImages = []
        error = nil
        statusMessage = ""
      }

      if !isDirectoryMode {
        singleImageView
      } else {
        directoryView
      }

      VStack(spacing: 10) {
        HStack(spacing: 20) {
          Button(action: isDirectoryMode ? selectDirectory : selectImage) {
            Label(
              isDirectoryMode ? "Select Directory" : "Select Image",
              systemImage: isDirectoryMode ? "folder" : "photo.on.rectangle")
          }
          .buttonStyle(.borderedProminent)

          if isDirectoryMode ? selectedDirectory != nil : selectedImage != nil {
            Button(action: startTranslation) {
              Label("Translate", systemImage: "text.bubble.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTranslating)
          }
        }

        HStack {
          Toggle("Show Detection Boxes", isOn: $showBoxes)
          Toggle("Show Translations", isOn: $showTranslations)
        }
        .padding(.vertical, 5)

        if isTranslating {
          VStack {
            ProgressView("Translating Japanese text...")
              .progressViewStyle(.linear)
            if isDirectoryMode {
              Text("\(completedImages.count)/\(imageQueue.count) images completed")
                .font(.caption)
            }
          }
        } else if !statusMessage.isEmpty {
          Text(statusMessage)
            .foregroundColor(.secondary)
        }

        if let error {
          Text(error.localizedDescription)
            .foregroundColor(.red)
            .padding()
            .background(
              RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
            )
        }
      }
    }
    .padding()
    .frame(minWidth: 800, minHeight: 600)
    .translationTask(configuration) { session in
      print("Starting translation task")

      if isDirectoryMode {
        await translateDirectory(session: session)
      } else {
        await translateSingleImage(session: session)
      }

      isTranslating = false
      configuration?.invalidate()
      configuration = nil
    }
  }

  private var singleImageView: some View {
    HStack(spacing: 20) {
      VStack {
        Text("Original")
          .font(.headline)

        if let selectedImage {
          AsyncImage(url: selectedImage) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fit)
          } placeholder: {
            ProgressView()
          }
          .frame(maxHeight: 400)
          .background(Color.gray.opacity(0.1))
          .cornerRadius(8)
        } else {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.1))
            .frame(maxHeight: 400)
            .overlay(
              Text("Select a Japanese comic page")
                .foregroundColor(.secondary)
            )
        }
      }

      if let translatedImage {
        VStack {
          Text("Translated")
            .font(.headline)

          AsyncImage(url: translatedImage) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fit)
          } placeholder: {
            ProgressView()
          }
          .frame(maxHeight: 400)
          .background(Color.gray.opacity(0.1))
          .cornerRadius(8)
        }
      }
    }
  }

  private var directoryView: some View {
    VStack {
      if selectedDirectory != nil {
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
            ForEach(completedImages, id: \.absoluteString) { imageUrl in
              AsyncImage(url: imageUrl) { image in
                image
                  .resizable()
                  .aspectRatio(contentMode: .fit)
              } placeholder: {
                ProgressView()
              }
              .frame(height: 200)
              .background(Color.gray.opacity(0.1))
              .cornerRadius(8)
            }
          }
          .padding()
        }
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.gray.opacity(0.1))
          .frame(maxHeight: 400)
          .overlay(
            Text("Select a directory containing Japanese comic pages")
              .foregroundColor(.secondary)
          )
      }
    }
  }

  private func selectImage() {
    print("Selecting image")
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    panel.message = "Select a Japanese comic page to translate"
    panel.prompt = "Select Image"

    if panel.runModal() == .OK {
      selectedImage = panel.url
      translatedImage = nil
      error = nil
      statusMessage = "Image selected successfully"
      configuration = nil
    }
  }

  private func selectDirectory() {
    print("Selecting directory")
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.folder]
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.message = "Select a directory containing Japanese comic pages"
    panel.prompt = "Select Directory"

    if panel.runModal() == .OK, let selectedUrl = panel.url {
      selectedDirectory = selectedUrl
      imageQueue = []
      completedImages = []
      error = nil

      loadImagesFromDirectory(selectedUrl)

      statusMessage = "Found \(imageQueue.count) images in directory"
      configuration = nil
    }
  }

  private func loadImagesFromDirectory(_ url: URL) {
    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )

      imageQueue = contents.filter { url in
        // Only include files (not directories) that are images
        guard let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
          !isDirectory
        else { return false }
        return url.pathExtension.lowercased().matches(of: /png|jpg|jpeg|gif|webp/).count > 0
      }

      statusMessage = "Found \(imageQueue.count) images in directory"
    } catch {
      self.error = error
      statusMessage = "Failed to load directory contents"
    }
  }

  private func startTranslation() {
    print(
      "Starting translation with showBoxes: \(showBoxes), showTranslations: \(showTranslations)")
    worker.updateConfig(showBoxes: showBoxes, showTranslations: showTranslations)
    DispatchQueue.main.async {
      configuration = .init(
        source: Locale.Language(identifier: "ja"),
        target: Locale.Language(identifier: "en")
      )
    }
  }

  private func translateSingleImage(session: TranslationSession) async {
    guard let selectedImage = selectedImage else { return }

    isTranslating = true
    error = nil
    statusMessage = "Detecting Japanese text..."

    do {
      // Create translated subdirectory
      let translatedDir = selectedImage.deletingLastPathComponent().appendingPathComponent(
        "translated", isDirectory: true)
      try FileManager.default.createDirectory(at: translatedDir, withIntermediateDirectories: true)

      statusMessage = "Translating detected text..."
      translatedImage = try await worker.translateImage(
        at: selectedImage,
        destinationDirectory: translatedDir, using: session
      )
      statusMessage = "Translation completed successfully"
    } catch {
      self.error = error
      statusMessage = "Translation failed"
    }
  }

  private func translateDirectory(session: TranslationSession) async {
    guard !imageQueue.isEmpty else { return }

    isTranslating = true
    error = nil
    completedImages = []
    currentProgress = 0.0

    // Create translated subdirectory
    let translatedDir = selectedDirectory?.appendingPathComponent("translated", isDirectory: true)
    do {
      if let dir = translatedDir {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      }
    } catch {
      self.error = error
      statusMessage = "Failed to create translated directory"
      return
    }

    for (index, imageUrl) in imageQueue.enumerated() {
      statusMessage = "Translating image \(index + 1) of \(imageQueue.count)"

      do {
        let translatedUrl = try await worker.translateImage(
          at: imageUrl,
          destinationDirectory: translatedDir,
          using: session
        )
        completedImages.append(translatedUrl)
        currentProgress = Double(index + 1) / Double(imageQueue.count)
      } catch {
        self.error = error
        statusMessage = "Failed to translate \(imageUrl.lastPathComponent)"
        // Continue with next image even if one fails
      }
    }

    statusMessage =
      error == nil ? "All translations completed" : "Translation completed with some errors"
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    TranslateImageView()
  }
}
