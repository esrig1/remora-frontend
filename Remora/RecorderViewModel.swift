import Foundation
import AVFoundation
import SwiftUI
import SoundAnalysis // Keep if needed for Pipelines or other analysis


/// ViewModel responsible for managing audio recording, segmentation, and file handling.
/// Records audio segments as WAV files.
/// Conforms to `ObservableObject` for SwiftUI integration and `AVAudioRecorderDelegate`
/// to handle recording events.
class RecorderViewModel: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    @Published var isRecording = false
    @Published var recordings: [String] = [] // Stores WAV filenames

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

    // Recommended sample rate for many speech processing tasks
    private let sampleRate: Double = 16000.0 // Changed from 12000, common for WAV/speech

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
            // .playAndRecord is still appropriate
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            // You might want to explicitly set preferred sample rate, though recorder settings often override
            // try audioSession.setPreferredSampleRate(self.sampleRate)
            print("Audio session category setup complete.")
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Recording Control

    /// Starts a new recording session, creating segmented WAV audio files.
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
        print("Starting recording session (WAV format)...")
        startNewSegment() // Will create a WAV file

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
        print("Timer fired: Rotating segment (WAV format)")
        isStoppingForSegmentRotation = true
        stopCurrentRecording()
    }

    /// Initializes and starts recording for a new audio segment file using a timestamped name and WAV format.
    private func startNewSegment() {
        let timestamp = filenameFormatter.string(from: Date())
        let segmentName = "\(timestamp).wav" // *** CHANGED EXTENSION ***
        guard let url = generateAudioFileURL(fileName: segmentName) else {
            print("Error: Could not generate URL for new WAV segment.")
            stopRecording() // Ensure recording stops fully
            return
        }
        print("Starting WAV segment recording: \(url.lastPathComponent)")

        // *** UPDATED SETTINGS FOR WAV (Linear PCM) ***
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),          // Core format ID for WAV
            AVSampleRateKey: sampleRate,                        // Use the defined sample rate (e.g., 16000 Hz)
            AVNumberOfChannelsKey: 1,                           // Mono recording
            AVLinearPCMBitDepthKey: 16,                         // Standard bit depth for PCM
            AVLinearPCMIsFloatKey: false,                       // Use integer samples
            AVLinearPCMIsBigEndianKey: false,                   // Standard endianness for iOS/macOS
            // AVEncoderAudioQualityKey is NOT used for Linear PCM
        ]

        do {
            // Ensure directory exists (good practice)
            _ = getRecordingsDirectory()

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true // Still useful for UI feedback if needed
            audioRecorder?.prepareToRecord()

            if audioRecorder?.record() == true {
                print("Segment recording started successfully for \(segmentName).")
            } else {
                print("Failed start recording segment \(segmentName). Cleaning up.")
                // Attempt to remove the potentially empty/corrupt file
                try? FileManager.default.removeItem(at: url)
                stopRecording() // Stop the process if a segment fails to start
            }
        } catch {
            print("Failed create recorder for segment \(segmentName): \(error.localizedDescription)")
            stopRecording() // Stop the process if recorder setup fails
        }
    }

    /// Initiates the stopping process for the currently active audio recorder instance.
    private func stopCurrentRecording() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            // If recorder is nil but we think we *should* be recording, maybe log warning.
            // If recorder exists but isn't recording, stop() does nothing, which is fine.
            print("Stop current recording requested, but recorder is not active or nil.")
            return
        }
        print("Requesting stop for current recording: \(recorder.url.lastPathComponent)")
        recorder.stop() // This will trigger audioRecorderDidFinishRecording
    }

    /// Manually stops the entire recording process, invalidates the timer, and cleans up.
    func stopRecording() {
        print("Manual stop requested.")
        // Check if we are in a recording state or if a recorder object exists (even if paused/stopped)
        guard isRecording || audioRecorder != nil else {
            print("Already stopped or not recording.")
            // Ensure UI state is correct if somehow out of sync
            if isRecording {
                 DispatchQueue.main.async { self.isRecording = false }
            }
            return
        }

        isManuallyStopping = true
        isStoppingForSegmentRotation = false // Ensure rotation flag is off

        segmentTimer?.invalidate()
        segmentTimer = nil
        print("Segment timer stopped.")

        // Stop the current recording if one is active
        stopCurrentRecording()

        // If stopCurrentRecording was called above, audioRecorderDidFinishRecording
        // will eventually set isRecording = false and deactivate session.
        // However, if there was no *active* recording (e.g., right between segments
        // or after a failure), we might need to force the state update and session deactivation.
        if audioRecorder == nil {
             print("Manual stop: No active recorder found, ensuring state is stopped and session is deactivated.")
             DispatchQueue.main.async {
                 self.isRecording = false
             }
             deactivateAudioSession()
        }
    }

    // MARK: - AVAudioRecorderDelegate

    /// Delegate method called when a recording segment finishes (either successfully or due to an error).
    /// Handles state transitions for segment rotation or final stop, and triggers processing for successful segments.
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let fileName = recorder.url.lastPathComponent
        let finishedUrl = recorder.url // Capture the URL before resetting audioRecorder
        print("Delegate: Finished recording \(fileName). Success: \(flag)")

        // Important: Reset the recorder instance *after* checking its URL
        // and before starting a new segment or fully stopping.
        self.audioRecorder = nil // Allow ARC to release the recorder

        if !flag {
            print("Segment \(fileName) failed to save properly.")
            // Attempt cleanup of potentially corrupt file
            try? FileManager.default.removeItem(at: finishedUrl)
            // Failure during recording usually means we should stop entirely.
            isStoppingForSegmentRotation = false // Don't try to rotate on failure
            isManuallyStopping = true // Treat as a stop scenario
        } else {
            print("Segment \(fileName) saved successfully to \(finishedUrl.path).")
            // Process the successfully saved WAV file
            Task { [weak self] in // Use weak self in async task
                // Pass the captured finishedUrl
                await self?.handleSuccessfulSegmentFinish(filename: fileName, fileURL: finishedUrl)
            }
            // Update the UI list of recordings
            DispatchQueue.main.async { [weak self] in
                 self?.loadRecordings()
            }
        }

        // --- State Transition Logic ---
        if isStoppingForSegmentRotation && flag {
            // We were rotating and the segment saved OK -> start the next one
            isStoppingForSegmentRotation = false
            print("Delegate: Rotation successful, starting next WAV segment.")
            startNewSegment()
            // Note: isRecording should remain true
        } else if isManuallyStopping || !flag {
            // We were manually stopping OR the segment failed -> Finalize the stop
            print("Delegate: Manual stop or failure detected. Finalizing stop process.")
            isManuallyStopping = false // Reset flag
            isStoppingForSegmentRotation = false // Reset flag

            // Ensure timer is definitely stopped
            segmentTimer?.invalidate()
            segmentTimer = nil

            // Update UI state
            DispatchQueue.main.async { [weak self] in
                self?.isRecording = false
            }

            // Deactivate the audio session
            deactivateAudioSession()
        }
        // If !isStoppingForSegmentRotation && !isManuallyStopping && flag,
        // it means something external stopped the recorder (e.g., interruption).
        // The current logic treats this like a manual stop via the 'else if isManuallyStopping || !flag' block.
    }


    /// Delegate method called if an encoding error occurs during recording.
    /// Treats this as a failure requiring a full stop. (Less common with uncompressed PCM, but still possible).
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let fileName = recorder.url.lastPathComponent
        print("Recorder encode error for \(fileName): \(error?.localizedDescription ?? "Unknown error")")

        isStoppingForSegmentRotation = false // Don't rotate on error
        // Attempt to clean up the file associated with the failed recorder
        try? FileManager.default.removeItem(at: recorder.url)

        // Trigger the full stop process
        // Setting isManuallyStopping ensures the logic in audioRecorderDidFinishRecording
        // (which might still be called after an error) performs the final cleanup.
        // Alternatively, call stopRecording() directly if preferred.
        isManuallyStopping = true
        stopCurrentRecording() // Ensure recorder is stopped if not already
        // If stopCurrentRecording doesn't trigger DidFinishRecording quickly,
        // consider adding the UI update + deactivate session here too for robustness.
        // stopRecording() // More direct approach
    }


    // MARK: - Segment Handling

    /// Processes a successfully recorded audio segment (WAV file) asynchronously.
    /// Reads the audio data and calls the transcription service.
    /// **Ensure `Pipelines.createTranscriptionFromAudioFile` can handle WAV data.**
    /// - Parameter filename: The name of the audio file segment.
    /// - Parameter fileURL: The `URL` of the audio file segment.
    private func handleSuccessfulSegmentFinish(filename: String, fileURL: URL) async {
        print("Processing successful WAV segment: \(filename)")

        // Check if file actually exists before trying to read (belt and suspenders)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
             print("handleSuccessfulSegmentFinish: Error - File does not exist at \(fileURL.path)")
             return
        }

        do {
            print("handleSuccessfulSegmentFinish: Reading data from \(fileURL.path)...")
            let audioData = try Data(contentsOf: fileURL)
            print("handleSuccessfulSegmentFinish: Read \(audioData.count) bytes from WAV file.")

            // *** IMPORTANT: Verify your TranscriptionService can process WAV data ***
            print("handleSuccessfulSegmentFinish: Calling TranscriptionService for \(filename)...")
            // Assuming the service can handle WAV data passed as Data
            let transcriptionResult = try await Pipelines.createTranscriptionFromAudioFile(audioData: audioData, fileUrl: fileURL)
            print("handleSuccessfulSegmentFinish: Transcription successful for \(filename): \"\(transcriptionResult)\"")

        } catch {
            print("handleSuccessfulSegmentFinish: Error processing \(filename): \(error.localizedDescription)")
            // Consider if you need error handling specific to transcription failure
        }
    }

    // MARK: - File Management

    /// Scans the recordings directory and updates the `recordings` published property (filtering for WAV).
    func loadRecordings() {
        let fileManager = FileManager.default
        guard let recordingsDirectory = getRecordingsDirectory() else {
            // Ensure recordings list is empty if directory fails
            DispatchQueue.main.async { if !self.recordings.isEmpty { self.recordings = [] } }
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(atPath: recordingsDirectory.path)
                .filter { $0.hasSuffix(".wav") && ($0.first?.isNumber ?? false) } // *** CHANGED SUFFIX FILTER ***
                .sorted(by: >) // Keep sorting logic (latest first)

            DispatchQueue.main.async {
                // Only update if the list content actually changed
                if self.recordings != files {
                    self.recordings = files
                    print("Loaded/Updated \(files.count) WAV recordings.")
                }
            }
        } catch {
            print("Failed to load recordings: \(error.localizedDescription)")
            DispatchQueue.main.async {
                // Clear recordings on error
                if !self.recordings.isEmpty { self.recordings = [] }
            }
        }
    }

    /// Returns the URL for the 'Recordings' subdirectory within the app's Documents directory.
    /// Creates the directory if it doesn't exist.
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
    private func generateAudioFileURL(fileName: String) -> URL? {
        guard let directory = getRecordingsDirectory() else {
             print("Error: Cannot get recordings directory to generate file URL for \(fileName).")
             return nil
        }
        // Appends the filename (which now includes .wav)
        return directory.appendingPathComponent(fileName)
    }

    /// Deletes recordings at specified offsets from the `recordings` (WAV) array and the file system.
    func deleteRecording(at offsets: IndexSet) {
        let fileManager = FileManager.default
        guard let recordingsDirectory = getRecordingsDirectory() else {
            print("Error: Could not get recordings directory for deletion.")
            return
        }

        // Capture filenames to delete based on current state of recordings array
        let filenamesToDelete = offsets.compactMap { index -> String? in
            guard index < self.recordings.count else { return nil }
            return self.recordings[index]
        }

        guard !filenamesToDelete.isEmpty else { return }

        // Perform file IO off the main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var deletedFilenamesOnWorker: [String] = []
            for filename in filenamesToDelete {
                // Reconstruct the URL on the worker thread
                let fileURL = recordingsDirectory.appendingPathComponent(filename)
                print("Attempting to delete WAV file: \(fileURL.path)")
                do {
                    try fileManager.removeItem(at: fileURL)
                    print("Successfully deleted file: \(filename)")
                    deletedFilenamesOnWorker.append(filename)
                } catch {
                    // Log error but continue trying to delete others
                    print("Error deleting file '\(filename)': \(error.localizedDescription)")
                }
            }

            // Update the published array back on the main thread
            DispatchQueue.main.async {
                guard let self = self else { return } // Ensure ViewModel still exists
                // Remove only the items that were successfully deleted from the filesystem
                self.recordings.removeAll { filename in
                    deletedFilenamesOnWorker.contains(filename)
                }
                 if !deletedFilenamesOnWorker.isEmpty {
                    print("Removed \(deletedFilenamesOnWorker.count) items from recordings array.")
                 }
            }
        }
    }

    /// Returns the full URL for a given filename (expected to be a WAV filename) within the recordings directory.
    func getURLForFilename(_ filename: String) -> URL? {
        // Ensure the filename has the correct extension if necessary, or rely on caller
        guard filename.hasSuffix(".wav") else {
             print("Warning: getURLForFilename called with non-WAV filename: \(filename)")
             // Decide if you want to return nil or proceed anyway
             // return nil
             return getRecordingsDirectory()?.appendingPathComponent(filename) // Current behaviour
        }
        return getRecordingsDirectory()?.appendingPathComponent(filename)
    }

    // MARK: - Session Deactivation

    /// Deactivates the shared audio session, notifying other apps.
    private func deactivateAudioSession() {
        print("Attempting to deactivate audio session...")
        let audioSession = AVAudioSession.sharedInstance()
        // Check if session is currently active before trying to deactivate
        // Note: Checking category might not be sufficient; isActive is better but not directly available.
        // We rely on our internal state (isRecording == false) implying session should be deactivated.
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("Audio session deactivated successfully.")
        } catch {
            // This can happen if the session was already inactive, often not a critical error.
            print("Failed to deactivate audio session (may already be inactive): \(error.localizedDescription)")
        }
    }

    /// Cleans up resources like the timer and audio recorder when the ViewModel is deallocated.
    deinit {
        print("RecorderViewModel deinit")
        segmentTimer?.invalidate()
        // Ensure any active recording is stopped on deinit
        if audioRecorder?.isRecording ?? false {
            print("Deinit: Stopping active recorder.")
            audioRecorder?.stop()
        }
        audioRecorder = nil // Break reference cycle if delegate points strongly
        // Consider deactivating session here too, although ideally it happens earlier
        // deactivateAudioSession()
    }
}
