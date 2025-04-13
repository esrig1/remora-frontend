//
//  AudioAnalysisService.swift
//  Remora
//
//  Created by Joshua Esrig on 4/13/25.
//

import SoundAnalysis
import Foundation

class AudioAnalysisService {
    
    init() {
        
    }
    
    public func isHumanSpeech(fileUrl: URL) async -> Bool {
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let analyzer = try SNAudioFileAnalyzer(url: fileUrl)
            
            let classification = try await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                let observer = AudioAnalysisObserver(continuation: continuation)
                do {
                    try analyzer.add(request, withObserver: observer)
                    analyzer.analyze()
                } catch {
                    print("Failed to add observer: \(error)")
                    continuation.resume(returning: "Unknown")
                }
            }
            
            return classification.lowercased().contains("speech")
            
        } catch {
            print("Failed to start analysis: \(error)")
            return false
        }
    }


    
    final class AudioAnalysisObserver: NSObject, SNResultsObserving {
        private var continuation: CheckedContinuation<String, Never>?
        private var highestConfidence: Double = 0.0
        private var mostLikelyClassification: String = "Unknown"
        
        init(continuation: CheckedContinuation<String, Never>) {
            self.continuation = continuation
        }
        
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            if let best = result.classifications.first, best.confidence > highestConfidence {
                highestConfidence = best.confidence
                mostLikelyClassification = best.identifier
            }
        }
        
        func requestDidComplete(_ request: SNRequest) {
            continuation?.resume(returning: mostLikelyClassification)
        }

        func request(_ request: SNRequest, didFailWithError error: Error) {
            print("Analysis failed with error: \(error)")
            continuation?.resume(returning: "Unknown")
        }
    }

    
}
