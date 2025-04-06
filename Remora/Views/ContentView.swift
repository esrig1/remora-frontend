import SwiftUI

struct ContentView: View {
    @StateObject private var recorder = RecorderViewModel()  // State object to manage the recorder and recordings

    var body: some View {
        TabView {
            // RecorderView with access to the shared recorder
            RecorderView(recordings: $recorder.recordings)
                .tabItem {
                    Label("Recorder", systemImage: "mic.fill")
                }

            // LLMView (Example Tab 2)
            LLMView()
                .tabItem {
                    Label("LLM", systemImage: "gearshape.fill")
                }

            // TranscriptionView with access to the shared recordings list
            TranscriptionView(recordings: recorder.recordings)
                .tabItem {
                    Label("Transcription", systemImage: "person.fill")
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
