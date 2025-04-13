import Foundation
import AVFoundation
import SwiftUI
import SoundAnalysis

// Assume Pipelines struct/class with the static transcription function exists
// struct Pipelines {
//     static func createTranscriptionFromAudioFile(audioData: Data) async throws -> String { ... }
// }

/// ViewModel responsible for managing audio recording, segmentation, and file handling.
/// It conforms to `ObservableObject` for SwiftUI integration and `AVAudioRecorderDelegate`
/// to handle recording events.
class RecorderViewModel: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    @Published var isRecording = false
    @Published var recordings: [String] = []

    private var segmentTimer: Timer?
    private let segmentDuration: TimeInterval = 30

    private var isStoppingForSegmentRotation = false
    private var isManuallyStopping = false

    private let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Initializes the ViewModel, sets up the audio session, and loads existing recordings.
    override init() {
        super.init()
        setupAudioSession()
        loadRecordings()
    }

    // MARK: - Audio Session Setup

    /// Configures and prepares the shared `AVAudioSession` for recording.
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            print("Audio session category setup complete.")
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Recording Control

    /// Starts a new recording session, creating segmented audio files.
    /// Activates the audio session if not already active.
    func startRecording() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            print("Audio session activated for recording.")
        } catch {
            print("Failed to activate audio session for recording: \(error.localizedDescription)")
            return
        }
        isManuallyStopping = false
        isStoppingForSegmentRotation = false
        print("Starting recording session...")
        startNewSegment()

        segmentTimer?.invalidate()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            self?.rotateSegment()
        }
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }

    /// Called by the segment timer to initiate the rotation to a new segment file.
    private func rotateSegment() {
        guard audioRecorder != nil else {
            print("Rotate segment called but recorder is nil. Stopping timer.")
            segmentTimer?.invalidate()
            segmentTimer = nil
            return
        }
        print("Timer fired: Rotating segment")
        isStoppingForSegmentRotation = true
        stopCurrentRecording()
    }

    /// Initializes and starts recording for a new audio segment file using a timestamped name.
    private func startNewSegment() {
        let timestamp = filenameFormatter.string(from: Date())
        let segmentName = "\(timestamp).m4a"
        guard let url = generateAudioFileURL(fileName: segmentName) else {
            print("Error: Could not generate URL for new segment.")
            stopRecording()
            return
        }
        print("Starting segment recording: \(url.lastPathComponent)")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
             _ = getRecordingsDirectory()

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()

            if audioRecorder?.record() == true {
                 print("Segment recording started successfully for \(segmentName).")
            } else {
                 print("Failed start recording segment \(segmentName).")
                 try? FileManager.default.removeItem(at: url)
                 stopRecording()
            }
        } catch {
            print("Failed create recorder for segment \(segmentName): \(error.localizedDescription)")
            stopRecording()
        }
    }

    /// Initiates the stopping process for the currently active audio recorder instance.
    private func stopCurrentRecording() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            print("Stop current recording requested, but recorder is not active or nil.")
            return
        }
        print("Requesting stop for current recording: \(recorder.url.lastPathComponent)")
        recorder.stop()
    }

    /// Manually stops the entire recording process, invalidates the timer, and cleans up.
    func stopRecording() {
        print("Manual stop requested.")
        guard isRecording || audioRecorder != nil else {
            print("Already stopped or not recording.")
            return
        }

        isManuallyStopping = true
        isStoppingForSegmentRotation = false

        segmentTimer?.invalidate()
        segmentTimer = nil
        print("Segment timer stopped.")

        stopCurrentRecording()
    }

    // MARK: - AVAudioRecorderDelegate

    /// Delegate method called when a recording segment finishes (either successfully or due to an error).
    /// Handles state transitions for segment rotation or final stop, and triggers processing for successful segments.
    /// - Parameters:
    ///   - recorder: The `AVAudioRecorder` instance that finished.
    ///   - flag: `true` if the recording saved successfully, `false` otherwise.
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let fileName = recorder.url.lastPathComponent
        let finishedUrl = recorder.url
        print("Delegate: Finished recording \(fileName). Success: \(flag)")

        self.audioRecorder = nil

        if !flag {
            print("Segment \(fileName) failed to save.")
            try? FileManager.default.removeItem(at: finishedUrl)

        } else {
            print("Segment \(fileName) saved successfully.")

            Task {
                await handleSuccessfulSegmentFinish(filename: fileName, fileURL: finishedUrl)
            }

             DispatchQueue.main.async { self.loadRecordings() }
        }

        if isStoppingForSegmentRotation && flag {
            isStoppingForSegmentRotation = false
            print("Delegate: Rotation successful, starting next segment.")
            startNewSegment()
        } else if isManuallyStopping || !flag {
            print("Delegate: Manual stop or failure detected. Finalizing.")
            isManuallyStopping = false
            isStoppingForSegmentRotation = false

            segmentTimer?.invalidate()
            segmentTimer = nil

            DispatchQueue.main.async {
                self.isRecording = false
            }

            deactivateAudioSession()
        }
    }

    /// Delegate method called if an encoding error occurs during recording.
    /// Treats this as a failure requiring a full stop.
    /// - Parameters:
    ///   - recorder: The recorder instance where the error occurred.
    ///   - error: An optional `Error` object describing the encoding issue.
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let fileName = recorder.url.lastPathComponent
        print("Recorder encode error for \(fileName): \(error?.localizedDescription ?? "Unknown")")

        isStoppingForSegmentRotation = false
        try? FileManager.default.removeItem(at: recorder.url)
        stopRecording()
    }

    // MARK: - Segment Handling

    /// Processes a successfully recorded audio segment asynchronously.
    /// Reads the audio data and calls the transcription service.
    /// - Parameter filename: The name of the audio file segment.
    /// - Parameter fileURL: The `URL` of the audio file segment.
    private func handleSuccessfulSegmentFinish(filename: String, fileURL: URL) async {
        print("Hello World - Segment finished: \(filename)")

        do {
            print("handleSuccessfulSegmentFinish: Reading data from \(fileURL.path)...")
            let audioData = try Data(contentsOf: fileURL)
            print("handleSuccessfulSegmentFinish: Read \(audioData.count) bytes.")

            print("handleSuccessfulSegmentFinish: Calling TranscriptionService...")
            let transcriptionResult = try await Pipelines.createTranscriptionFromAudioFile(audioData: audioData, fileUrl: fileURL)
            print("handleSuccessfulSegmentFinish: Transcription successful for \(filename): \"\(transcriptionResult)\"")

        } catch {
            print("handleSuccessfulSegmentFinish: Error processing \(filename): \(error.localizedDescription)")
        }
    }

    // MARK: - File Management

    /// Scans the recordings directory and updates the `recordings` published property on the main thread.
    func loadRecordings() {
        let fileManager = FileManager.default
        guard let recordingsDirectory = getRecordingsDirectory() else { return }

        do {
            let files = try fileManager.contentsOfDirectory(atPath: recordingsDirectory.path)
                .filter { $0.hasSuffix(".m4a") && ($0.first?.isNumber ?? false) }
                .sorted(by: >)

            DispatchQueue.main.async {
                if self.recordings != files {
                    self.recordings = files
                    print("Loaded/Updated \(files.count) recordings.")
                }
            }
        } catch {
            print("Failed to load recordings: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.recordings = []
            }
        }
    }

    /// Returns the URL for the 'Recordings' subdirectory within the app's Documents directory.
    /// Creates the directory if it doesn't exist.
    /// - Returns: The `URL` of the recordings directory, or `nil` on failure.
    private func getRecordingsDirectory() -> URL? {
        let fileManager = FileManager.default
        do {
            let documentsPath = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let recordingsDirectory = documentsPath.appendingPathComponent("Recordings")

            if !fileManager.fileExists(atPath: recordingsDirectory.path) {
                print("Creating Recordings directory at: \(recordingsDirectory.path)")
                try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
            }
            return recordingsDirectory
        } catch {
            print("Could not get or create Recordings directory: \(error.localizedDescription)")
            return nil
        }
    }

    /// Constructs the full file URL for a given recording file name within the recordings directory.
    /// - Parameter fileName: The base name of the file (e.g., "timestamp.m4a").
    /// - Returns: The full `URL` for the file, or `nil` if the directory cannot be accessed.
    private func generateAudioFileURL(fileName: String) -> URL? {
        guard let directory = getRecordingsDirectory() else {
             print("Error: Cannot get recordings directory to generate file URL.")
             return nil
        }
        return directory.appendingPathComponent(fileName)
    }

    /// Deletes recordings at specified offsets from the `recordings` array and the file system.
    /// Performs file deletion on a background thread.
    /// - Parameter offsets: An `IndexSet` containing the indices of the recordings to delete.
    func deleteRecording(at offsets: IndexSet) {
        let fileManager = FileManager.default
        guard let recordingsDirectory = getRecordingsDirectory() else {
            print("Error: Could not get recordings directory for deletion.")
            return
        }

        let filenamesToDelete = offsets.compactMap { index -> String? in
            guard index < self.recordings.count else { return nil }
            return self.recordings[index]
        }

        guard !filenamesToDelete.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var deletedFilenamesOnWorker: [String] = []
            for filename in filenamesToDelete {
                let fileURL = recordingsDirectory.appendingPathComponent(filename)
                print("Attempting to delete file: \(fileURL.path)")
                do {
                    try fileManager.removeItem(at: fileURL)
                    print("Successfully deleted file: \(filename)")
                    deletedFilenamesOnWorker.append(filename)
                } catch {
                    print("Error deleting file '\(filename)': \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.recordings.removeAll { filename in
                    deletedFilenamesOnWorker.contains(filename)
                }
                 if !deletedFilenamesOnWorker.isEmpty {
                    print("Removed \(deletedFilenamesOnWorker.count) items from recordings array.")
                 }
            }
        }
    }

    /// Returns the full URL for a given filename within the recordings directory.
    /// - Parameter filename: The name of the recording file.
    /// - Returns: The full `URL` or `nil` if the directory cannot be accessed.
    func getURLForFilename(_ filename: String) -> URL? {
        return getRecordingsDirectory()?.appendingPathComponent(filename)
    }

    // MARK: - Session Deactivation

    /// Deactivates the shared audio session, notifying other apps.
    private func deactivateAudioSession() {
        print("Attempting to deactivate audio session...")
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.category == .playAndRecord else {
            print("Audio session category is not playAndRecord; skipping deactivation.")
            return
        }
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("Audio session deactivated successfully.")
        } catch {
            print("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }


    /// Cleans up resources like the timer and audio recorder when the ViewModel is deallocated.
    deinit {
        print("RecorderViewModel deinit")
        segmentTimer?.invalidate()
        if audioRecorder?.isRecording ?? false {
            audioRecorder?.stop()
        }
        audioRecorder = nil
    }
}
