// DiarizationService.swift
import Foundation


/// Directly uses the `Diarization.shared` singleton.
struct DiarizationService {

    // Note: No initializer needed as we directly use the singleton below.

    /// Starts the diarization process using `Diarization.shared` and returns the full parsed response object.
    /// - Parameter audioData: The raw audio data to be processed.
    /// - Returns: The complete `DiarizationResponse` object.
    /// - Throws: An error if the underlying diarization process fails.
    func getDiarizationResult(audioData: Data) async throws -> DiarizationResponse {
        print("DiarizationService: Requesting diarization via Diarization.shared...")
        // Directly call the shared instance
        let response = try await Diarization.shared.startDiarization(audioData: audioData)
        print("DiarizationService: Response received.")
        return response
    }

    /// Starts the diarization process using `Diarization.shared` and returns only the concatenated transcription text.
    /// - Parameter audioData: The raw audio data to be processed.
    /// - Returns: A single string containing the text from all transcription parts, joined by spaces.
    /// - Throws: An error if the underlying diarization process fails.
    func getTranscriptionText(audioData: Data) async throws -> String {
        var responseBuilder: String = ""
        let response = try await Diarization.shared.startDiarization(audioData: audioData)
        let segments: [Transcription] = response.transcription
        
        for segment in segments {
            responseBuilder += (segment.speaker + ": " + segment.text + "\n")
        }
        return responseBuilder
    }
    
    func formatTranscriptionText(response: DiarizationResponse) -> String {
        return ""
    }
}
