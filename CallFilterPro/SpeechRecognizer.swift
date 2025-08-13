import Foundation
import AVFoundation
import Speech
import CoreML

class SpeechRecognizer: NSObject, ObservableObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var transcription: String = ""

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
                let granted = authStatus == .authorized && micGranted
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }

    func startTranscribing() {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let rawTranscript = result.bestTranscription.formattedString
                let isSpam = self.checkIfSpam(rawTranscript)

                DispatchQueue.main.async {
                    if isSpam {
                        self.transcription = rawTranscript + "\n⚠️ Potential Spam Detected"
                    } else {
                        self.transcription = rawTranscript + "\n✅ Legitimate Call"
                    }
                }
            }
        }
    }

    func stopTranscribing() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    private func checkIfSpam(_ text: String) -> Bool {
        do {
            let model = try SpamClassifier(configuration: MLModelConfiguration())
            let prediction = try model.prediction(text: text)
            return prediction.label == "spam"
        } catch {
            print("⚠️ Error running ML model: \(error)")
            return false
        }
    }
}
