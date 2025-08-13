import UIKit
import UniformTypeIdentifiers
import Speech
import CoreML

final class ActionViewController: UIViewController {

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let dismissButton = UIButton(type: .system)

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        handleInput()
    }

    // MARK: - UI
    private func configureUI() {
        view.backgroundColor = .systemBackground

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 17, weight: .medium)
        statusLabel.text = "Analyzing…"

        spinner.startAnimating()

        dismissButton.setTitle("Done", for: .normal)
        dismissButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        dismissButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, dismissButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.widthAnchor)
        ])
    }

    @objc private func close() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func showResult(_ text: String) {
        spinner.stopAnimating()
        dismissButton.isHidden = false
        statusLabel.text = text
    }

    private func fail(_ message: String) {
        showResult("❌ \(message)")
    }

    // MARK: - Input handling
    private func handleInput() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments, !providers.isEmpty else {
            return fail("No shared content.")
        }

        // Try audio first, then plain text
        if !tryLoadAudio(from: providers) {
            tryLoadPlainText(from: providers)
        }
    }

    private func tryLoadAudio(from providers: [NSItemProvider]) -> Bool {
        // Common audio UTTypes
        let audioTypes: [UTType] = [
            .mpeg4Audio,        // m4a
            .wav,
            .aiff,
            .audio              // generic audio fallback
        ]

        for provider in providers {
            for t in audioTypes where provider.hasItemConformingToTypeIdentifier(t.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: t.identifier) { [weak self] url, error in
                    guard let self = self else { return }
                    if let url = url {
                        // Copy to a readable temp location (some sandbox URLs are ephemeral)
                        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension)
                        do {
                            try FileManager.default.copyItem(at: url, to: tmp)
                            self.transcribe(url: tmp)
                        } catch {
                            self.fail("Could not access audio file.")
                        }
                    } else {
                        self.fail("Failed to load audio: \(error?.localizedDescription ?? "unknown error")")
                    }
                }
                return true
            }
        }
        return false
    }

    private func tryLoadPlainText(from providers: [NSItemProvider]) {
        let textType = UTType.plainText.identifier
        for provider in providers where provider.hasItemConformingToTypeIdentifier(textType) {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { [weak self] item, _ in
                guard let self = self else { return }
                let text: String? = {
                    if let s = item as? String { return s }
                    if let d = item as? Data { return String(data: d, encoding: .utf8) }
                    return nil
                }()
                guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    return self.fail("Empty text.")
                }
                self.classify(text: text)
            }
            return
        }
        fail("No audio or text found.")
    }

    // MARK: - Speech (file-based) transcription
    private func transcribe(url: URL) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard status == .authorized else {
                    return self.fail("Speech recognition not authorized.")
                }
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
                let request = SFSpeechURLRecognitionRequest(url: url)
                request.shouldReportPartialResults = false

                recognizer?.recognitionTask(with: request) { [weak self] result, error in
                    guard let self = self else { return }
                    if let error = error {
                        return self.fail("Transcription failed: \(error.localizedDescription)")
                    }
                    if let result = result, result.isFinal {
                        let transcript = result.bestTranscription.formattedString
                        if transcript.isEmpty {
                            self.fail("Could not detect speech in file.")
                        } else {
                            self.classify(text: transcript)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Core ML classification
    private func classify(text: String) {
        // SpamClassifier is the auto-generated class from SpamClassifier.mlmodel
        guard let model = try? SpamClassifier(configuration: MLModelConfiguration()),
              let prediction = try? model.prediction(text: text) else {
            return fail("Model prediction failed.")
        }

        let verdict = (prediction.label == "spam") ? "⚠️ Spam" : "✅ Legitimate"
        let message = """
        \(verdict)

        “\(text)”
        """
        showResult(message)
    }
}
