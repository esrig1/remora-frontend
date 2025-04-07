import Foundation
import AVFoundation
import SwiftUI

// Inherit from NSObject to use AVAudioRecorderDelegate
class RecorderViewModel: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    @Published var isRecording = false
    @Published var recordings: [String] = [] // Stores the filenames

    private var segmentTimer: Timer?
    private let segmentDuration: TimeInterval = 15 // Duration of each segment

    // Flags to manage state transitions
    private var isStoppingForSegmentRotation = false
    private var isManuallyStopping = false

    // Date Formatter for precise filenames including milliseconds
    private let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Format: YearMonthDay_HourMinuteSecond_Millisecond
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        // Using POSIX locale prevents unexpected changes based on user's region
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Using UTC can be helpful for consistency if files are shared across timezones
        // formatter.timeZone = TimeZone(secondsFromGMT: 0) // Optional: Uncomment for UTC
        return formatter
    }()

    /// Initializes the ViewModel, sets up the audio session, and loads existing recordings.
    override init() {
        super.init()
        setupAudioSession()
        loadRecordings()
    }

    // MARK: - Audio Session Setup
    /// Configures the audio session for recording and playback.
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            print("Audio session setup complete.")
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Recording Control
    /// Starts the recording process, creating segmented audio files.
    func startRecording() { // Removed fileName parameter as it's no longer used for base name
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session: \(error.localizedDescription)")
            return
        }

        // Reset state flags
        isManuallyStopping = false
        isStoppingForSegmentRotation = false
        // baseFileName and currentSegmentIndex are no longer needed for naming

        print("Starting recording session...")
        startNewSegment() // Start the first segment

        // Invalidate old timer and start new one
        segmentTimer?.invalidate()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            self?.rotateSegment()
        }

        // Update UI
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }

    /// Called by the timer to stop the current segment and start the next.
    private func rotateSegment() {
        guard audioRecorder != nil else { return } // Only rotate if currently recording
        print("Timer fired: Rotating segment")
        isStoppingForSegmentRotation = true
        stopCurrentRecording() // Delegate will handle starting the next segment
    }

    /// Initializes and starts recording for a new audio segment file with a precise timestamp name.
    private func startNewSegment() {
        // Generate filename based on the *exact* current time
        let timestamp = filenameFormatter.string(from: Date())
        let segmentName = "\(timestamp).m4a" // Use timestamp directly as filename

        let url = generateAudioFileURL(fileName: segmentName)
        print("Starting segment recording: \(url.lastPathComponent)")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            // Ensure previous recorder is stopped and released
            // audioRecorder?.stop() // Should be handled by stopCurrentRecording + delegate
            // audioRecorder = nil // Delegate sets this to nil

            // Create and configure the new recorder instance
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self // Set delegate *before* recording
            audioRecorder?.prepareToRecord()

            // Start recording
            if audioRecorder?.record() == true {
                 print("Segment recording started successfully for \(segmentName).")
                 // No need to increment segment index anymore
            } else {
                 print("Failed start recording segment \(segmentName).")
                 stopRecording() // Stop the whole process if a segment fails to start
            }

        } catch {
            print("Failed create recorder for segment \(segmentName): \(error.localizedDescription)")
            stopRecording() // Stop the whole process on error
        }
    }

    /// Initiates the stopping process for the currently active recorder.
    private func stopCurrentRecording() {
        print("Requesting stop for current recording (if active).")
        audioRecorder?.stop() // Tell the recorder to stop; delegate handles completion
    }

    /// Manually stops the entire recording process and invalidates the timer.
    func stopRecording() {
        print("Manual stop requested.")
        // Check if we are actually recording or in the process of stopping
        guard isRecording || audioRecorder != nil else {
            print("Already stopped or not recording.")
            return
        }

        isManuallyStopping = true // Signal that this is a final stop requested by user
        isStoppingForSegmentRotation = false // Ensure rotation flag is off

        // Invalidate timer first so delegate knows it's not a rotation
        segmentTimer?.invalidate()
        segmentTimer = nil
        print("Segment timer stopped.")

        // Initiate the stop of the current recording file
        stopCurrentRecording()
        // The delegate method will handle the final state updates (isRecording = false, loadRecordings)
    }

    // MARK: - AVAudioRecorderDelegate

    /// Called by the system when the audio recorder finishes recording a file.
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let fileName = recorder.url.lastPathComponent
        print("Delegate: Finished recording \(fileName). Success: \(flag)")

        // Release the finished recorder instance
        self.audioRecorder = nil

        if !flag {
            print("Segment \(fileName) failed to save.")
            // Consider how to handle segment save failure - maybe stop entire recording?
        } else {
            print("Segment \(fileName) saved successfully.")
            // Reload recordings immediately after a successful save if you want the list
            // to update during recording (optional, might have performance impact)
            // DispatchQueue.main.async { self.loadRecordings() }
        }

        // --- State transition logic ---

        // Case 1: We stopped to rotate segments, and it was successful
        if isStoppingForSegmentRotation && flag {
            isStoppingForSegmentRotation = false // Reset flag
            print("Delegate: Rotation successful, starting next segment.")
            startNewSegment() // Start the next part
        }
        // Case 2: We stopped manually, OR a segment failed saving, OR rotation failed
        else if isManuallyStopping || !flag {
            print("Delegate: Manual stop or failure detected. Finalizing.")
            isManuallyStopping = false // Reset flags
            isStoppingForSegmentRotation = false

            // Ensure timer is definitely stopped
            segmentTimer?.invalidate()
            segmentTimer = nil

            // Update UI state and reload the final list
            DispatchQueue.main.async {
                self.isRecording = false
                self.loadRecordings() // Load the complete list now
            }
        }
        // Note: If isStoppingForSegmentRotation is true but flag is false, it falls into the second case.
    }

    /// Called by the system if an encoding error occurs during recording.
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("Recorder encode error: \(error?.localizedDescription ?? "Unknown")")
        isStoppingForSegmentRotation = false // Reset flag
        stopRecording() // Treat encoding errors as needing a full stop
    }


    // MARK: - File Management

    /// Scans the recordings directory and updates the `recordings` published property.
    func loadRecordings() {
        let fileManager = FileManager.default
        guard let recordingsDirectory = getRecordingsDirectory() else { return }

        do {
            // Get filenames, filter, and sort (descending for most recent first)
            let files = try fileManager.contentsOfDirectory(atPath: recordingsDirectory.path)
                .filter { $0.hasSuffix(".m4a") && $0.first?.isNumber ?? false } // Filter for .m4a starting with a digit (our timestamp format)
                .sorted(by: >) // Sort descending by name (time)

            // Update the UI
            DispatchQueue.main.async {
                self.recordings = files
            }
            print("Loaded \(files.count) recordings.")
        } catch {
            print("Failed to load recordings: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.recordings = [] // Clear list on error
            }
        }
    }

    // Removed generateTimestampedBaseName() as it's no longer used

    /// Returns the URL for the 'Recordings' directory in Documents, creating it if necessary.
    private func getRecordingsDirectory() -> URL? {
        let fileManager = FileManager.default
        do {
            let documentsPath = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let recordingsDirectory = documentsPath.appendingPathComponent("Recordings")

            if !fileManager.fileExists(atPath: recordingsDirectory.path) {
                try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Created Recordings directory.")
            }
            return recordingsDirectory
        } catch {
            print("Could not get/create Recordings directory: \(error.localizedDescription)")
            return nil
        }
    }

    /// Constructs the full file URL for a given recording file name within the recordings directory.
    private func generateAudioFileURL(fileName: String) -> URL {
        // Use guard let or force unwrap if certain directory exists
        guard let directory = getRecordingsDirectory() else {
             fatalError("Could not access recordings directory") // Or handle more gracefully
        }
        return directory.appendingPathComponent(fileName)
    }

    /// Deletes recordings at specified offsets from the list and file system.
    func deleteRecording(at offsets: IndexSet) {
        let fileManager = FileManager.default
        guard let recordingsDirectory = getRecordingsDirectory() else {
            print("Error: Could not get recordings directory for deletion.")
            return
        }

        let filenamesToDelete = offsets.map { self.recordings[$0] }

        for filename in filenamesToDelete {
            let fileURL = recordingsDirectory.appendingPathComponent(filename)
            print("Attempting to delete file: \(fileURL.path)")
            do {
                try fileManager.removeItem(at: fileURL)
                print("Successfully deleted file: \(filename)")

                // Remove from the @Published array AFTER successful file deletion
                DispatchQueue.main.async {
                    // Find index again in case array was mutated elsewhere (safer)
                    if let indexToRemove = self.recordings.firstIndex(of: filename) {
                        self.recordings.remove(at: indexToRemove)
                        print("Removed '\(filename)' from recordings array.")
                    }
                }
            } catch {
                print("Error deleting file '\(filename)': \(error.localizedDescription)")
                // Maybe add user feedback here if deletion fails
            }
        }
    }
}
