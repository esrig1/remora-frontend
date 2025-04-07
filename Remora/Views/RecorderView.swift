import SwiftUI

struct RecorderView: View {
    // Use Binding to receive and update recordings in the parent view
    @Binding var recordings: [String]

    // ViewModel to handle recording logic and data
    @StateObject private var recorder = RecorderViewModel()

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

            // Use ForEach inside List to enable .onDelete
            List {
                ForEach(recorder.recordings, id: \.self) { recording in
                    Text(recording)
                }
                // Add the .onDelete modifier here
                .onDelete(perform: deleteRecording) // Calls the helper function below
            }
            // This ensures the parent view's @Binding gets updated whenever
            // the recorder's list changes (including after deletions)
            .onChange(of: recorder.recordings) { newRecordings in
                recordings = newRecordings
            }
        }
        .onAppear {
            // Load recordings when the view appears
            recorder.loadRecordings()
            // Sync initial recordings to the binding
            recordings = recorder.recordings
        }
    }

    /// Helper function to call the ViewModel's delete method.
    private func deleteRecording(at offsets: IndexSet) {
        print("Swipe to delete action triggered for offsets: \(offsets)")
        recorder.deleteRecording(at: offsets)
    }
}

struct RecorderView_Previews: PreviewProvider {
    // Example binding for previews
    @State static var previewRecordings = ["Recording 1.m4a", "Recording 2.m4a", "rec_20231027_103000_part0.m4a"]

    static var previews: some View {
        RecorderView(recordings: $previewRecordings)
    }
}
