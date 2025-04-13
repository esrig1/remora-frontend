import Foundation


enum Pipelines {

    /// Creates a transcription string from audio data using the DiarizationService.
    /// Handles errors internally by returning nil.
    ///
    /// - Parameter audioData: The audio data to transcribe.
    /// - Returns: The transcribed text as a String, or nil if an error occurred.
    static func createTranscriptionFromAudioFile(audioData: Data, fileUrl: URL) async throws -> String {
        let diarizationService = DiarizationService()
        let llmService = await LLMService()
        let conversationStorageService = ConversationStorageService()
        let audioAnalysisService = AudioAnalysisService()
        
        if(await audioAnalysisService.isHumanSpeech(fileUrl: <#T##URL#>)) {
            print("speech found")
        } else {
            return ""
        }

        let transcription = try await diarizationService.getTranscriptionText(audioData: audioData)
        
        let prompt = "Summarize the following conversation:\n\n" + transcription
                
        conversationStorageService.addConversationToFile(
            conversationText: transcription,
            for: ConversationStorageService.FileUrlType.conversation
        )
                
        return transcription
    }
    
    static func createSummaryFromTranscription(transcription: String) async throws -> String {
        let llmService = await LLMService()
        let conversationStorageService = ConversationStorageService()
        
        let prompt = "Summarize the following conversation:\n\n" + transcription
        
        let summary: String? = await llmService.generate(prompt: prompt)
        
        conversationStorageService.addConversationToFile(
            conversationText: transcription,
            for: ConversationStorageService.FileUrlType.summary
        )
        
        return summary ?? "failed"
        
    }
    
}

