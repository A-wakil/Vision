//
//  VisionService.swift
//  Vision
//
//  Created by CAIT on 3/12/25.
//

import Foundation
import AVFoundation
import UIKit

// Add the response models at the top
struct VisionResponse: Codable {
    let description: String
    let read_out: String?
}

class VisionService: ObservableObject {
    private let backend = VisionBackend()
    
    @Published var isProcessing = false
    @Published var audioPlayer: AVAudioPlayer?
    
    init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // Main function with retry logic
    func processImage(_ imageData: Data, pastContext: String? = nil, language: String = "en") async throws -> String {
        await MainActor.run { isProcessing = true }
        defer {
            Task { @MainActor in isProcessing = false }
        }
        
        let result = try await backend.processImage(imageData, pastContext: pastContext, language: language)
        
        // Parse JSON response
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let description = json["description"] as? String {
            
            // Convert description to speech
            try await convertToSpeechWithRetry(description)
            return description
        } else {
            // If JSON parsing fails, try to use the result directly
            try await convertToSpeechWithRetry(result)
            return result
        }
    }
    
    // Helper function for TTS with retry
    private func convertToSpeechWithRetry(_ text: String, voice: String = "nova") async throws {
        let maxRetries = 3
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                try await convertToSpeech(text, voice: voice)
                return
            } catch {
                lastError = error
                print("⚠️ TTS attempt \(attempt) failed: \(error)")
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
            }
        }
        
        throw lastError ?? NSError(domain: "", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: "Text-to-speech failed"])
    }
    
    // Base TTS function
    private func convertToSpeech(_ text: String, voice: String = "nova") async throws {
        print("Starting text-to-speech conversion...")
        
        let audioData = try await backend.textToSpeech(text, voice: voice)
        print("Received audio data size: \(audioData.count) bytes")
        
        await MainActor.run {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                let player = try AVAudioPlayer(data: audioData)
                player.prepareToPlay()
                
                self.audioPlayer = player
                
                print("Audio duration: \(player.duration) seconds")
                
                if player.play() {
                    print("✅ Started playing audio")
                } else {
                    print("❌ Failed to start audio playback")
                }
            } catch {
                print("❌ Error setting up audio: \(error)")
            }
        }
    }
    
    // Add this function to VisionService class
    func replayLastAudio() {
        Task { @MainActor in
            guard let player = audioPlayer else { return }
            
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                player.currentTime = 0
                if player.play() {
                    print("✅ Replaying audio")
                } else {
                    print("❌ Failed to replay audio")
                }
            } catch {
                print("❌ Error replaying audio: \(error)")
            }
        }
    }
}

