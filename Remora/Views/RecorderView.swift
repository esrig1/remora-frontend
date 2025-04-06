import SwiftUI

struct RecorderView: View {
    @Binding var recordings: [String]  // Use Binding to share recordings with ContentView
    
    @StateObject private var recorder = RecorderViewModel()  // ViewModel to handle recording logic

    var body: some View {
        VStack {
            Text("Voice Recorder")
                .font(.largeTitle)
                .padding()

            Button(action: {
                if recorder.isRecording {
                    recorder.stopRecording()
                } else {
                    recorder.startRecording()
                }
            }) {
                Text(recorder.isRecording ? "Stop Recording" : "Start Recording")
                    .foregroundColor(.white)
                    .padding()
                    .background(recorder.isRecording ? Color.red : Color.blue)
                    .cornerRadius(10)
            }
            .padding()

            Divider()

            Text("Saved Recordings")
                .font(.headline)
                .padding(.top)

            List(recorder.recordings, id: \.self) { recording in
                Text(recording)
            }

            // Update the parent view's recordings when the recorder's recordings change
            .onChange(of: recorder.recordings) { newRecordings in
                recordings = newRecordings
            }
        }
        .onAppear {
            recorder.loadRecordings()  // Load recordings on launch
        }
    }
}

struct RecorderView_Previews: PreviewProvider {
    static var previews: some View {
        RecorderView(recordings: .constant(["Recording 1", "Recording 2"]))  // Pass some dummy data for previews
    }
}
