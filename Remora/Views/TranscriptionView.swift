import SwiftUI

struct TranscriptionView: View {
    let recordings: [String]  // Pass recordings as a parameter
    @State private var selectedRecording: String? = nil
    @State private var isTranscribing: Bool = false
    @State private var transcriptionResult: String? = nil
    @State private var errorMessage: String? = nil
    @State private var isTestingConnection: Bool = false
    @State private var connectionStatus: String? = nil
    
    var body: some View {
        VStack {
            Text("Transcriptions")
                .font(.largeTitle)
                .padding()
            
            // Server connection test section
            HStack {
                Button(action: testServerConnection) {
                    HStack {
                        Text("Test Server Connection")
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }
                .disabled(isTestingConnection)
                .padding(.horizontal)
                
                if let connectionStatus = connectionStatus {
                    Text(connectionStatus)
                        .foregroundColor(connectionStatus.contains("Success") ? .green : .red)
                        .font(.callout)
                }
            }
            .padding(.bottom)
            
            // Show the transcription result or error
            if isTranscribing {
                ProgressView("Transcribing...")
                    .padding()
            }
            
            if let transcriptionResult = transcriptionResult {
                Text("Transcription Result: \(transcriptionResult)")
                    .padding()
            }
            
            if let errorMessage = errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            List(recordings, id: \.self) { recording in
                HStack {
                    Text(recording)
                        .font(.body)
                        .foregroundColor(.blue)
                    Spacer()
                    Button(action: {
                        self.selectedRecording = recording
                        transcribeRecording(recording: recording)
                    }) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 5)
            }
            .listStyle(PlainListStyle())
        }
        .padding()
    }
    
    private func testServerConnection() {
        print("testing recording")
        isTestingConnection = true
        connectionStatus = nil
        
        Task {
            do {
                print("before test connection")

                let response = try await Diarization.shared.testServerConnection()
                connectionStatus = "Success: \(response.result)"
                print("test connection success")
            } catch {
                connectionStatus = "Failed: \(error.localizedDescription)"
                print("failed")

            }
            isTestingConnection = false
        }
    }
    
    private func transcribeRecording(recording: String) {
        // Assuming the recordings are file paths or identifiers to audio data
        guard let selectedRecording = selectedRecording else { return }
        

        guard let audioData = fetchAudioData(for: selectedRecording) else {
            errorMessage = "Failed to load audio data."
            return
        }
        
        // Start transcription using Diarization class
        isTranscribing = true
        errorMessage = nil
        transcriptionResult = nil
        
        Task {
            do {
                let response = try await Pipelines.createDiarizationFromAudioFile(audioData: audioData)
                transcriptionResult = response
            } catch {
                errorMessage = error.localizedDescription
            }
            
            // Update the UI state after transcription completes
            isTranscribing = false
        }
    }
    
    // Simulate fetching audio data (replace this with your actual method)
    func fetchAudioData(for path: String) -> Data? {
        let fileURL: URL = getAudioFileURL(for: path)
        return try? Data(contentsOf: fileURL)
    }
    
    
    func getAudioFileURL(for fileName: String) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDirectory = documentsPath.appendingPathComponent("Recordings")
        return recordingsDirectory.appendingPathComponent(fileName)
    }
}

struct TranscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        TranscriptionView(recordings: ["Recording 1", "Recording 2"])
    }
}
