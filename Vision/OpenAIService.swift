//
//  OpenAIService.swift
//  Vision
//
//  Created by CAIT on 3/12/25.
//

import Foundation

enum OpenAIEndpoint {
    case vision
    case speech
    var path: String {
        switch self {
        case .vision:
            return "/chat/completions"
        case .speech:
            return "/audio/speech"
        }
    }
}

struct VisionRequest: Encodable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat
    let temperature: Double
    let maxTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case temperature
        case maxTokens = "max_tokens"
    }
    
    struct Message: Encodable {
        let role: String
        let content: [Content]
    }
    
    struct Content: Encodable {
        let type: String
        let text: String?
        let imageUrl: ImageURL?
        
        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageUrl = "image_url"
        }
    }
    
    struct ImageURL: Encodable {
        let url: String
    }
    
    struct ResponseFormat: Encodable {
        let type: String
    }
}

struct OpenAIVisionResponse: Decodable {
    let choices: [Choice]
    
    struct Choice: Decodable {
        let message: Message
    }
    
    struct Message: Decodable {
        let content: String
    }
}

struct SpeechRequest: Encodable {
    let model: String
    let input: String
    let voice: String
    let responseFormat: String
    let instructions: String?
    
    enum CodingKeys: String, CodingKey {
        case model
        case input
        case voice
        case responseFormat = "response_format"
        case instructions
    }
}

// Add this new response type for speech
struct SpeechResponse {
    let audioData: Data
}

class OpenAIService {
    static let shared = OpenAIService()
    
    private init() {}
    
    func describeImage(_ imageData: Data, pastContext: String? = nil, language: String = "en") async throws -> String {
        let base64Image = imageData.base64EncodedString()
        
        let systemPrompt = """
        You are an AI assistant designed to help visually impaired individuals by providing descriptions of images live from their camera. Your primary role is to describe the picture, focusing on key visual details such as objects, people, colors, actions, expressions, and context. If the image conveys an emotion, theme, or notable artistic style, include that as well. Since you're basically the impaired person's eyes, use present language. for example, 'You're looking at...'

        IMPORTANT:
        1. Provide your response in \(language) language.
        2. Return your response in JSON format with a 'description' field containing your detailed description.
        3. if there is a paper, poster, or letter in the image, put emphasis in reading/detailing out what is written in the poster, paper, or letter. whatever is written should also be read out in the language of \(language)
        """
        
        var messages: [VisionRequest.Message] = [
            .init(role: "system", content: [.init(type: "text", text: systemPrompt, imageUrl: nil)])
        ]
        
        if let context = pastContext {
            messages.append(.init(role: "system", content: [
                .init(type: "text", text: "Previous context: \(context)", imageUrl: nil)
            ]))
        }
        
        messages.append(.init(role: "user", content: [
            .init(type: "image_url", text: nil, imageUrl: .init(url: "data:image/jpeg;base64,\(base64Image)")),
            .init(type: "text", text: "Describe this image and return the response as JSON with a 'description' field.", imageUrl: nil)
        ]))
        
        let request = VisionRequest(
            model: "gpt-4o-mini",
            messages: messages,
            responseFormat: .init(type: "json_object"),
            temperature: 1,
            maxTokens: 2048
        )
        
        let response: OpenAIVisionResponse = try await performRequest(.vision, body: request)
        
        // Debug print the raw response
        print("Raw response content: \(response.choices.first?.message.content ?? "no content")")
        
        // Try parsing the JSON response
        if let content = response.choices.first?.message.content {
            do {
                if let jsonData = content.data(using: .utf8),
                   let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    // Debug print the parsed JSON
                    print("Parsed JSON: \(json)")
                    
                    if let description = json["description"] as? String {
                        return description
                    } else {
                        // If "description" field is not found, return the entire content
                        return content
                    }
                }
            } catch {
                print("JSON parsing error: \(error)")
                // If JSON parsing fails, return the raw content
                return content
            }
        }
        
        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid response content"])
    }
    
    func textToSpeech(
        text: String,
        model: String = "gpt-4o-mini-tts",
        voice: String = "nova",
        responseFormat: String = "pcm",
        instructions: String? = nil
    ) async throws -> Data {
        let request = SpeechRequest(
            model: model,
            input: text,
            voice: voice,
            responseFormat: responseFormat,
            instructions: instructions
        )
        
        return try await performRequestForAudio(.speech, body: request)
    }
    
    func textToSpeechStreaming(
        text: String,
        model: String = "gpt-4o-mini-tts",
        voice: String = "nova",
        responseFormat: String = "pcm",
        instructions: String? = nil,
        onChunk: @escaping (Data) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        let request = SpeechRequest(
            model: model,
            input: text,
            voice: voice,
            responseFormat: responseFormat,
            instructions: instructions
        )
        
        Task {
            do {
                try await performStreamingRequest(.speech, body: request, onChunk: onChunk)
                await MainActor.run {
                    onComplete(nil)
                }
            } catch {
                await MainActor.run {
                    onComplete(error)
                }
            }
        }
    }
    
    // Add a new method specifically for audio data
    private func performRequestForAudio<T: Encodable>(_ endpoint: OpenAIEndpoint, body: T) async throws -> Data {
        guard let url = URL(string: OpenAIConfig.baseURL + endpoint.path) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(OpenAIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("OpenAI API Error: \(message)")
                throw NSError(domain: "", code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: message])
            } else if let errorText = String(data: data, encoding: .utf8) {
                print("Response Error: \(errorText)")
                throw NSError(domain: "", code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Status \(httpResponse.statusCode): \(errorText)"])
            }
        }
        
        return data  // Return the raw audio data
    }
    
    // Add a new method for streaming audio data
    private func performStreamingRequest<T: Encodable>(_ endpoint: OpenAIEndpoint, body: T, onChunk: @escaping (Data) -> Void) async throws {
        guard let url = URL(string: OpenAIConfig.baseURL + endpoint.path) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(OpenAIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode != 200 {
            // Handle error response
            var errorData = Data()
            for try await byte in asyncBytes {
                errorData.append(byte)
            }
            
            if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("OpenAI API Error: \(message)")
                throw NSError(domain: "", code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: message])
            } else if let errorText = String(data: errorData, encoding: .utf8) {
                print("Response Error: \(errorText)")
                throw NSError(domain: "", code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Status \(httpResponse.statusCode): \(errorText)"])
            }
        }
        
        // Process the streaming response
        let bufferSize = 4096 // Adjust buffer size as needed
        var buffer = Data(capacity: bufferSize)
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            
            // When buffer reaches a certain size, send it to the callback
            if buffer.count >= bufferSize {
                let bufferCopy = buffer // Create a copy of the buffer
                await MainActor.run {
                    onChunk(bufferCopy)
                }
                buffer = Data(capacity: bufferSize)
            }
        }
        
        // Send any remaining data
        if !buffer.isEmpty {
            let finalBufferCopy = buffer // Create a copy of the final buffer
            await MainActor.run {
                onChunk(finalBufferCopy)
            }
        }
    }
    
    // Original performRequest remains for JSON responses
    private func performRequest<T: Encodable, R>(_ endpoint: OpenAIEndpoint, body: T) async throws -> R where R: Decodable {
        guard let url = URL(string: OpenAIConfig.baseURL + endpoint.path) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(OpenAIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        // Print response for debugging
        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("OpenAI API Error: \(message)")
                throw NSError(domain: "", code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: message])
            } else if let errorText = String(data: data, encoding: .utf8) {
                print("Response Error: \(errorText)")
                throw NSError(domain: "", code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Status \(httpResponse.statusCode): \(errorText)"])
            }
        }
        
        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            print("Decoding Error: \(error)")
            print("Response Data: \(String(data: data, encoding: .utf8) ?? "none")")
            throw error
        }
    }
}
