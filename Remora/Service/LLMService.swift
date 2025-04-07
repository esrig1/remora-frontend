// LLMService.swift
import Foundation
import MLXLLM
import MLXLMCommon
import Combine
import SwiftUI

@MainActor
class LLMService: ObservableObject {

    // Published properties for UI feedback
    @Published var outputText: String = "Ready." // Initial state message
    @Published var isLoading: Bool = false
    @Published var downloadProgress: Double = 0.0

    private let modelConfiguration = ModelRegistry.llama3_2_1B_4bit

    /// Generates text based on a prompt using the configured LLM.
    /// Updates published properties for progress and loading state.
    ///
    /// - Parameter prompt: The input prompt for the language model.
    /// - Returns: The generated text as a `String` on success, or `nil` if an error occurred.
    func generate(prompt: String) async -> String? { // Changed return type to String?

        // Use defer to ensure loading state is reset when the function exits,
        // regardless of how it exits (return, throw, error).
        defer {
            Task { @MainActor in
                self.isLoading = false
                self.downloadProgress = 0.0
                // Optionally reset outputText to a default state here if needed,
                // or leave it showing the last status/error message.
                // self.outputText = "Ready."
            }
        }

        // --- Start Loading Process ---
        self.isLoading = true
        self.outputText = "Preparing model..."
        self.downloadProgress = 0.0

        do {
            // --- Load Model (with progress updates) ---
            let modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: modelConfiguration) { progress in
                // Update UI progress on the main thread
                Task { @MainActor in
                    self.downloadProgress = progress.fractionCompleted
                    let percentage = Int(self.downloadProgress * 100)
                    // Only update text if loading is still in progress to avoid overwriting error messages
                    if self.isLoading {
                        if self.downloadProgress > 0 && self.downloadProgress < 1 {
                             self.outputText = "Downloading model: \(percentage)%"
                        } else if self.downloadProgress == 0 {
                            self.outputText = "Preparing model files..."
                        }
                    }
                }
            }

            // --- Model Loaded, Prepare for Generation ---
            // Update status only if still loading (no error occurred during load)
            if self.isLoading {
                 self.outputText = "Model loaded. Generating text..."
            }

            // --- Perform Generation ---
            let fullGeneratedText = try await modelContainer.perform { [prompt] context in
                let input = try await context.processor.prepare(input: .init(prompt: prompt))

                let generateResult: GenerateResult = try MLXLMCommon.generate(
                    input: input, parameters: .init(), context: context
                ) { tokens in
                    // Handle streaming if needed, otherwise just .more for non-streaming
                    return .more
                }

                let decodedText = context.tokenizer.decode(tokens: generateResult.tokens)
                return decodedText
            }

            // --- Success ---
            // Update status text for UI feedback (optional)
            self.outputText = "Generation complete."
            // Return the successful result
            return fullGeneratedText

        } catch let error as NSError {
            // --- Handle Known Errors ---
            let errorMessage = "Error: \(error.localizedDescription)\nDomain: \(error.domain)\nCode: \(error.code)"
            self.outputText = errorMessage // Update UI text with error
            print("LLM Error: \(error)")
            return nil // Return nil to indicate failure

        } catch {
            // --- Handle Unexpected Errors ---
            let errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
            self.outputText = errorMessage // Update UI text with error
            print("LLM Error: \(error)")
            return nil // Return nil to indicate failure
        }
        // Note: The defer block handles setting isLoading = false and progress = 0.0
    }
}


// --- Example Usage ---

@MainActor
class MyViewModel: ObservableObject {
    @ObservedObject var llmService = LLMService() // Observe the service for UI updates
    @Published var finalResultText: String? = nil // Store the final returned result

    func runGeneration(prompt: String) {
        finalResultText = nil // Clear previous result

        Task {
            // Call the generate function and await its String? result
            let result = await llmService.generate(prompt: prompt)

            // Store the final result (could be nil on failure)
            self.finalResultText = result

            // You can check the result here if needed
            if let generated = result {
                print("ViewModel: Generation successful: \(generated.prefix(100))...")
            } else {
                print("ViewModel: Generation failed (check llmService.outputText for error details).")
            }
        }
    }

    // Your SwiftUI View would observe both `llmService` (for isLoading, outputText progress)
    // and `finalResultText` (to display the final outcome).
}
