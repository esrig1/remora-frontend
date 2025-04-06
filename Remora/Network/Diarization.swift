//
//  Diarization.swift
//  Remora
//
//  Created by Joshua Esrig on 3/31/25.
//

import Foundation

struct Transcription: Codable {
    let start: Double
    let end: Double
    let speaker: String
    let text: String
}

struct DiarizationResponse: Codable {
    let transcription: [Transcription]
}

struct HelloResponse: Codable {
    let result: String
}

// Diarization class to interact with the local server API
class Diarization {
    
    static let shared = Diarization()  // Singleton instance for easy access
    private let baseURL = Constants.baseURL
    
    private init() {}
    
    // Perform POST request to start diarization
    func startDiarization(audioData: Data) async throws -> DiarizationResponse {
        let url = URL(string: "\(baseURL)/transcribe")!
        
        let boundary = UUID().uuidString
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Create multipart form data body
        var body = Data()
        
        // Add the file parameter as expected by FastAPI's File(...) parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Close the multipart form data
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Attach the body to the request
        request.httpBody = body
        
        // Execute the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for valid response
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "DiarizationError", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
        }
        
        // Parse response data
        let diarizationResponse = try JSONDecoder().decode(DiarizationResponse.self, from: data)
        print(diarizationResponse)
        return diarizationResponse
    }
    
    func testServerConnection() async throws -> HelloResponse {
        let url = URL(string: "\(baseURL)/hello")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for valid response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DiarizationError", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "DiarizationError", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"])
        }
        
        // Parse response data
        let helloResponse = try JSONDecoder().decode(HelloResponse.self, from: data)
        print("response: \(helloResponse)")
        return helloResponse
    }

    // Additional helper functions can be added here, for example:
    // - Method for downloading results
    // - Method to stop or cancel a diarization process
    // - Other networking tasks specific to your use case
}

