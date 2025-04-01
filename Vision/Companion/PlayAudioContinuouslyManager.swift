//
//  PlayAudioContinuouslyManager.swift
//  Vision
//
//  Created by CAIT on 3/27/25.
//

import Foundation
import AVFoundation

class PlayAudioContinuouslyManager: NSObject {
    
    static let shared = PlayAudioContinuouslyManager()
    private override init() {
        super.init()
        initParam()
    }
    
    func initParam() {
        print("PlayAudioContinuouslyManager: Initializing audio playback system")
        
        // Clean up existing resources first
        cleanup()
        
        // Create new engine and nodes
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        let timePitchNode = AVAudioUnitTimePitch()
        timePitchNode.rate = 1
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitchNode)
        
        // Must use 24000 sample rate for OpenAI
        let customSampleRate = Double(24000)
        audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: customSampleRate, channels: 1, interleaved: false)
        audioEngine.connect(playerNode, to: timePitchNode, format: audioFormat)
        audioEngine.connect(timePitchNode, to: audioEngine.mainMixerNode, format: audioFormat)
        
        // Reset state
        isPauseAudio = false
        isCurrentlyPlaying = false
        audio_event_Queue.removeAll()
        
        do {
            try audioEngine.start()
            playerNode.play()
            print("PlayAudioContinuouslyManager: Audio engine started successfully")
        } catch {
            print("PlayAudioContinuouslyManager: Failed to start audio engine: \(error)")
        }
    }
    
    var isPauseAudio = false
    var audioEngine: AVAudioEngine!
    var playerNode: AVAudioPlayerNode!
    var audioFormat: AVAudioFormat!
    var audio_event_Queue = [[String: Any]]()
    private var isCurrentlyPlaying = false
    private var audioMonitorTimer: Timer?
    
    // Add a maximum queue size to prevent memory issues
    private let maximumQueueSize = 200
    
    func playAudio(eventInfo: [String: Any]) {
        // Limit the queue size to prevent memory issues
        if audio_event_Queue.count >= maximumQueueSize {
            print("Warning: Audio queue exceeded maximum size, removing oldest items")
            // Remove oldest items to make room
            let itemsToRemove = min(20, audio_event_Queue.count)
            audio_event_Queue.removeFirst(itemsToRemove)
        }
        
        audio_event_Queue.append(eventInfo)
        if audio_event_Queue.count == 1 {
            startAudioMonitoring()
            playNextAudio()
        }
    }
    
    private func startAudioMonitoring() {
        // Stop existing timer if any
        audioMonitorTimer?.invalidate()
        
        // Create a timer to check for playback completion
        audioMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isCurrentlyPlaying && self.audio_event_Queue.isEmpty {
                // We were playing but queue is now empty - playback is complete
                self.isCurrentlyPlaying = false
                self.audioMonitorTimer?.invalidate()
                
                // Post notification that playback is complete
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name(rawValue: "AudioPlaybackFinished"), object: nil)
                    
                    // Resume audio recording after a short delay to prevent immediate feedback
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if WebSocketManager.shared.connected_status == "connected" {
                            RecordAudioManager.shared.startRecordAudio()
                        }
                    }
                }
            }
        }
    }
    
    private func playNextAudio() {
        if isPauseAudio {
            return
        }
        
        if audio_event_Queue.count <= 0 {
            return
        }
        
        isCurrentlyPlaying = true
        
        // Use autoreleasepool to help with memory management
        autoreleasepool {
            let firstAudioInfo = audio_event_Queue[0]
            let base64String = firstAudioInfo["delta"] as? String ?? ""
            
            guard let pcmData = Data(base64Encoded: base64String) else {
                audio_event_Queue.removeFirst()
                playNextAudio()
                return
            }
            
            let int16Count = pcmData.count / MemoryLayout<Int16>.size
            let frameCapacity = int16Count
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(frameCapacity)) else {
                audio_event_Queue.removeFirst()
                playNextAudio()
                return
            }
            
            buffer.frameLength = AVAudioFrameCount(frameCapacity)
            
            pcmData.withUnsafeBytes { rawBufferPointer in
                guard let int16Pointer = rawBufferPointer.baseAddress?.assumingMemoryBound(to: Int16.self) else {
                    return
                }
                
                // Increase volume by 2x instead of 3x to reduce potential distortion
                var audioSamples: [Int16] = Array(UnsafeBufferPointer(start: int16Pointer, count: frameCapacity))
                let amplificationFactor: Float = 2.0
                let maxAmplitude: Int16 = Int16.max
                let minAmplitude: Int16 = Int16.min
                
                for i in 0..<audioSamples.count {
                    let amplifiedSample = Float(audioSamples[i]) * amplificationFactor
                    if amplifiedSample > Float(maxAmplitude) {
                        audioSamples[i] = maxAmplitude
                    } else if amplifiedSample < Float(minAmplitude) {
                        audioSamples[i] = minAmplitude
                    } else {
                        audioSamples[i] = Int16(amplifiedSample)
                    }
                }
                
                // Convert to float32 for the buffer
                let floatPointer = buffer.floatChannelData?[0]
                for i in 0..<int16Count {
                    floatPointer?[i] = Float(audioSamples[i]) / 32768.0
                }
            }
            
            playerNode.scheduleBuffer(buffer) { [weak self] in
                guard let self = self else { return }
                if self.audio_event_Queue.count > 0 {
                    self.audio_event_Queue.removeFirst()
                }
                self.playNextAudio()
            }
        }
    }
    
    // Add a complete stop function that clears the queue
    func stopAudio() {
        isPauseAudio = true
        playerNode.pause()
        audio_event_Queue.removeAll()
        isCurrentlyPlaying = false
        
        // Post notification that audio has been stopped
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "AudioPlaybackStopped"), object: nil)
        }
    }
    
    func pauseAudio() {
        isPauseAudio = true
        playerNode.pause()
        
        // This is the key fix - we need to reset the player node's state when pausing
        if !audio_event_Queue.isEmpty {
            // Keep the queue items but ensure we're in a fully stopped state
            isCurrentlyPlaying = false
        }
    }
    
    func resumeAudio() {
        isPauseAudio = false
        playerNode.play()
        if audio_event_Queue.count > 0 {
            playNextAudio()
        }
    }
    
    // Improved cleanup method to release all resources
    func cleanup() {
        print("PlayAudioContinuouslyManager: Cleaning up resources")
        
        // Stop timer
        audioMonitorTimer?.invalidate()
        audioMonitorTimer = nil
        
        // Reset state variables
        isPauseAudio = false
        isCurrentlyPlaying = false
        
        // Clear the audio queue
        audio_event_Queue.removeAll()
        
        // Check if engine and node exist before stopping
        if let playerNode = playerNode {
            playerNode.stop()
        }
        
        if let engine = audioEngine {
            engine.stop()
            
            // Remove all attached nodes
            if let playerNode = playerNode {
                engine.detach(playerNode)
            }
            
            // Ensure engine is reset
            engine.reset()
        }
        
        print("PlayAudioContinuouslyManager: Cleanup completed")
    }
}
