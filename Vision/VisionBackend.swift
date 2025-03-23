//
//  VisionBackend.swift
//  Vision
//
//  Created by CAIT on 3/12/25.
//

import Foundation
import AVFoundation

class VisionBackend {
    private let openAIService = OpenAIService.shared
    
    func processImage(_ imageData: Data, pastContext: String? = nil, language: String = "en") async throws -> String {
        return try await openAIService.describeImage(imageData, pastContext: pastContext, language: language)
    }
    
    func textToSpeech(_ text: String, voice: String = "nova") async throws -> Data {
        return try await openAIService.textToSpeech(
            text: text,
            model: "gpt-4o-mini-tts",
            voice: voice,
            responseFormat: "pcm"
        )
    }
}

