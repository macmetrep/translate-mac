import SwiftUI
import Translation
import UniformTypeIdentifiers

public struct ContentView: View {
  @State private var selectedImage: URL?
  @State private var translatedImage: URL?
  @State private var isTranslating = false
  @State private var error: Error?
  @State private var statusMessage = ""
  @State private var configuration: TranslationSession.Configuration?
  @State private var showBoxes = false
  @State private var showTranslations = true

  private let worker: TranslateWorker

  public init() {
    self.worker = TranslateWorker(config: .init(showBoxes: false, showTranslations: true))
  }

  public var body: some View {
    VStack(spacing: 20) {
      Text("Japanese Comic Translator")
        .font(.title)
        .padding(.bottom)

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

      VStack(spacing: 10) {
        HStack(spacing: 20) {
          Button(action: selectImage) {
            Label("Select Image", systemImage: "photo.on.rectangle")
          }
          .buttonStyle(.borderedProminent)

          if selectedImage != nil {
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
          ProgressView("Translating Japanese text...")
            .progressViewStyle(.linear)
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
      guard let selectedImage = selectedImage else { return }
      isTranslating = true
      error = nil
      statusMessage = "Detecting Japanese text..."

      do {
        statusMessage = "Translating detected text..."
        translatedImage = try await worker.translateImage(at: selectedImage, using: session)
        statusMessage = "Translation completed successfully"
      } catch {
        self.error = error
        statusMessage = "Translation failed"
      }

      isTranslating = false
      configuration?.invalidate()
      configuration = nil
    }
  }

  private func selectImage() {
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

  private func startTranslation() {
    worker.updateConfig(showBoxes: showBoxes, showTranslations: showTranslations)
    configuration = .init(
      source: Locale.Language(identifier: "ja"),
      target: Locale.Language(identifier: "en")
    )
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
