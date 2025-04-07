import Foundation


enum Pipelines {

    /// Creates a transcription string from audio data using the DiarizationService.
    /// Handles errors internally by returning nil.
    ///
    /// - Parameter audioData: The audio data to transcribe.
    /// - Returns: The transcribed text as a String, or nil if an error occurred.
    static func createSummaryFromAudioFile(audioData: Data) async throws -> String {
        let diarizationService = DiarizationService()
        let llmService = await LLMService()

        let transcription = try await diarizationService.getTranscriptionText(audioData: audioData)
        
        let prompt = "Summarize the following conversation:\n\n" + transcription
        
        let summary: String? = await llmService.generate(prompt: prompt)

        print("Summary: " + (summary ?? "Generation failed or returned nil"))
        
        return transcription
    }
}

