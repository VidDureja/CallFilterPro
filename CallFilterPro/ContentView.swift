import SwiftUI

struct ContentView: View {
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isListening = false
    @State private var permissionGranted = false

    var body: some View {
        VStack(spacing: 30) {
            Text("Call Filter Pro")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            Text(speechRecognizer.transcription.isEmpty ? "Press the button to filter the caller..." : speechRecognizer.transcription)
                .padding()
                .frame(height: 150)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            Button(action: {
                toggleListening()
            }) {
                Text(isListening ? "Stop Listening" : "Filter Call")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isListening ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!permissionGranted)
            .padding(.horizontal)

            // ✅ FIXED: This if block is now in proper ViewBuilder scope
            if !permissionGranted {
                Text("Microphone and Speech access is required.")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .onAppear {
            speechRecognizer.requestPermissions { granted in
                self.permissionGranted = granted
            }
        }
    }

    func toggleListening() {
        isListening.toggle()
        if isListening {
            speechRecognizer.startTranscribing()
        } else {
            speechRecognizer.stopTranscribing()
        }
    }
}

