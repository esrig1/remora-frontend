//
//  RecorderViewModel.swift
//  Remora
//
//  Created by Joshua Esrig on 3/8/25.
//

import Foundation
import AVFoundation

class RecorderViewModel: ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    @Published var isRecording = false
    @Published var recordings: [String] = [] // Stores recording file names
    
    private var segmentTimer: Timer?
    private let segmentDuration: TimeInterval = 30
    private var currentSegmentIndex = 0

    func startRecording(fileName: String? = nil) {
        let audioSession = AVAudioSession.sharedInstance()
        
        
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try audioSession.setActive(true)

            // Use custom name if provided, or generate a UUID-based one
            let url = generateAudioFileURL(fileName: fileName)
            print("Recording to URL: \(url.path)")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            
            if audioRecorder?.prepareToRecord() == true {
                audioRecorder?.record()
                DispatchQueue.main.async {
                    self.isRecording = true
                }
            } else {
                print("Failed to prepare recorder")
            }
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        DispatchQueue.main.async {
            self.isRecording = false
            self.loadRecordings() // Refresh list of recordings
        }
    }

    func loadRecordings() {
        let fileManager = FileManager.default
        let recordingsDirectory = getAudioFileURL().deletingLastPathComponent()

        do {
            let files = try fileManager.contentsOfDirectory(atPath: recordingsDirectory.path)
            DispatchQueue.main.async {
                self.recordings = files
            }
            print("Recordings found: \(files)")
        } catch {
            print("Failed to list recordings: \(error.localizedDescription)")
        }
    }

    func getAudioFileURL() -> URL {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDirectory = documentsPath.appendingPathComponent("Recordings")

        if !fileManager.fileExists(atPath: recordingsDirectory.path) {
            do {
                try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Created directory: \(recordingsDirectory.path)")
            } catch {
                print("Failed to create directory: \(error.localizedDescription)")
            }
        } else {
            print("Directory exists: \(recordingsDirectory.path)")
        }

        let fileName = "recording_\(UUID().uuidString).m4a"
        let fileURL = recordingsDirectory.appendingPathComponent(fileName)

        print("Saving recording at: \(fileURL.path)")
        return fileURL
    }
    
    
    private func generateAudioFileURL(fileName: String? = nil) -> URL {
        let name: String

        if let fileName = fileName {
            name = fileName
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            name = "recording_\(timestamp).m4a"
        }

        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDirectory = documentsPath.appendingPathComponent("Recordings")

        // Ensure the directory exists
        if !fileManager.fileExists(atPath: recordingsDirectory.path) {
            do {
                try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create Recordings directory: \(error.localizedDescription)")
            }
        }

        return recordingsDirectory.appendingPathComponent(name)
    }


}

