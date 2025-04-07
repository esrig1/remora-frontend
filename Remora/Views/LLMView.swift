// LLMView.swift
import SwiftUI

struct LLMView: View {
    @StateObject private var llmService = LLMService()

    private let prompt = "I am going to ask you to summarize the following conversation between alice and bob. Alice: Hey, how's your day? Bob: Pretty good, just finished a project."

    var body: some View {
        VStack {
            Text("LLM Summary")
                .font(.largeTitle)
                .padding()

            ScrollView {
                Text(llmService.outputText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .border(Color.gray, width: 1)
            }
            .padding(.horizontal)

            if llmService.isLoading {
                 if llmService.downloadProgress > 0 && llmService.downloadProgress < 1 {
                     ProgressView(value: llmService.downloadProgress, total: 1.0) {
                         Text("Downloading Model...")
                     } currentValueLabel: {
                         Text("\(Int(llmService.downloadProgress * 100))%")
                     }
                     .padding(.horizontal)
                 } else {
                     ProgressView("Processing...")
                         .padding()
                 }
            }

            Button("Generate Summary") {
                Task {
                    await llmService.generate(prompt: prompt)
                }
            }
            .padding()
            .disabled(llmService.isLoading)
            .buttonStyle(.borderedProminent)
        }
    }
}

struct LLMView_Previews: PreviewProvider {
    static var previews: some View {
        LLMView()
    }
}
