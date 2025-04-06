//
//  LLMView.swift
//  Remora
//
//  Created by Joshua Esrig on 3/30/25.
//

import SwiftUI
import MLXLLM
import MLXLMCommon

struct LLMView: View {
    let modelConfiguration = ModelRegistry.llama3_2_1B_4bit
    @State private var outputText: String = "Generated text will appear here..."
    @State private var isLoading: Bool = false
    
    var body: some View {
        VStack {
            Text("LLM View")
                .font(.largeTitle)
                .padding()
            
            Text(outputText)
                .padding()
                .border(Color.blue, width: 1)
            
            if isLoading {
                ProgressView()
                    .padding()
            }
            
            Button("Generate Text") {
                Task {
                    do {
                        isLoading = true
                        try await generateText()
                        isLoading = false
                    } catch let error as NSError {
                        outputText = "Error: \(error.localizedDescription)\nDomain: \(error.domain)\nCode: \(error.code)"
                        isLoading = false
                    }
                }
            }
            .padding()
            .disabled(isLoading)
        }
    }
}

extension LLMView {
    private func generateText() async throws {
        let modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: modelConfiguration) { progress in
            let percentage = Int(progress.fractionCompleted * 100)
            // Update UI on main thread
            Task { @MainActor in
                self.outputText = "Downloading model: \(percentage)%"
            }
        }
        
        let prompt = "Summarize this conversation: Alice: Hey, how's your day? Bob: Pretty good, just finished a project."
        
        Task { @MainActor in
            self.outputText = "Model loaded. Generating text..."
        }
        
        do {
            let _ = try await modelContainer.perform { [prompt] context in
                let input = try await context.processor.prepare(input: .init(prompt: prompt))
                
                return try MLXLMCommon.generate(
                    input: input, parameters: .init(), context: context
                ) { tokens in
                    let text = context.tokenizer.decode(tokens: tokens)
                    Task { @MainActor in
                        self.outputText = text
                    }
                    return .more
                }
            }
        } catch {
            throw error
        }
    }
}

struct LLMView_Previews: PreviewProvider {
    static var previews: some View {
        LLMView()
    }
}
