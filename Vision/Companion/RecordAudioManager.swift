//
//  RecordAudioManager.swift
//  Vision
//
//  Created by CAIT on 3/27/25.
//

import Foundation
import AVFoundation

class RecordAudioManager: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    var audioUnit: AudioUnit?
    var local_record_buffers = [AVAudioPCMBuffer]()
    var local_record_Array = [[String: Any]]()
    
    // Add memory management properties
    private let maxBufferSize = 1024 * 1024 // 1MB per buffer
    private let maxTotalBuffersSize = 10 * 1024 * 1024 // 10MB total
    private var totalBuffersSize: Int = 0
    
    static let shared = RecordAudioManager()
    private override init() {
        super.init()
        self.audioProcessingQueue = DispatchQueue(label: "com.vision.audioprocessing", qos: .userInteractive)
    }
    
    private var audioProcessingQueue = DispatchQueue(label: "com.vision.audioprocessing", qos: .userInteractive)
    
    // MARK: - Start audio recording
    func startRecordAudio() {
        // If already recording, clean up first
        if audioUnit != nil {
            pauseCaptureAudio()
            // Small delay to ensure previous recording is properly stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self._startRecordAudio()
            }
            return
        }
        
        _startRecordAudio()
    }
    
    // When starting recording, clean any previous buffers
    private func cleanupBuffers() {
        // Clear local buffers to prevent memory growth
        local_record_buffers.removeAll()
        local_record_Array.removeAll()
        totalBuffersSize = 0
    }
    
    private func _startRecordAudio() {
        RecordAudioManager.shared.count = 0
        RecordAudioManager.shared.local_record_Array = [[String: Any]]()
        
        // If we already have an audio unit, just start it
        if audioUnit != nil {
            if AudioOutputUnitStart(audioUnit!) == noErr {
                print("Audio recording resumed")
                return
            } else {
                // If failed to restart, release and recreate
                if let au = audioUnit {
                    AudioComponentInstanceDispose(au)
                    audioUnit = nil
                }
            }
        }
        
        // Check microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                print("The user denied microphone permission.")
            } else {
                print("Microphone permission granted.")
            }
        }
        
        // Set up audio session on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try audioSession.setActive(true)
                print("Audio session setup successful")
                
                // Initialize audio component
                var audioComponentDesc = AudioComponentDescription()
                audioComponentDesc.componentType = kAudioUnitType_Output
                audioComponentDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO
                audioComponentDesc.componentManufacturer = kAudioUnitManufacturer_Apple
                audioComponentDesc.componentFlags = 0
                audioComponentDesc.componentFlagsMask = 0
                
                // Create audio unit
                guard let audioComponent = AudioComponentFindNext(nil, &audioComponentDesc) else {
                    print("Failed to find Audio Unit")
                    return
                }
                
                AudioComponentInstanceNew(audioComponent, &self.audioUnit)
                guard let audioUnit = self.audioUnit else {
                    print("Failed to create Audio Unit instance")
                    return
                }
                
                // Set up input pipeline
                var enableIO: UInt32 = 1
                let _ = AudioUnitSetProperty(audioUnit,
                                           kAudioOutputUnitProperty_EnableIO,
                                           kAudioUnitScope_Input,
                                           1,
                                           &enableIO,
                                           UInt32(MemoryLayout.size(ofValue: enableIO)))
                
                // MUST use 24000 sample rate for OpenAI
                var audioFormat = AudioStreamBasicDescription(
                    mSampleRate: 24000,
                    mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                    mBytesPerPacket: 2,
                    mFramesPerPacket: 1,
                    mBytesPerFrame: 2,
                    mChannelsPerFrame: 1,
                    mBitsPerChannel: 16,
                    mReserved: 0
                )
                
                AudioUnitSetProperty(audioUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Output,
                                   1,
                                   &audioFormat,
                                   UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
                
                // Enable input callback
                var inputCallbackStruct = AURenderCallbackStruct(
                    inputProc: inputRenderCallback,
                    inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
                )
                
                AudioUnitSetProperty(audioUnit,
                                   kAudioOutputUnitProperty_SetInputCallback,
                                   kAudioUnitScope_Global,
                                   1,
                                   &inputCallbackStruct,
                                   UInt32(MemoryLayout<AURenderCallbackStruct>.size))
                
                // Set up output pipeline
                var enable_out: UInt32 = 0
                let _ = AudioUnitSetProperty(audioUnit,
                                           kAudioOutputUnitProperty_EnableIO,
                                           kAudioUnitScope_Output,
                                           0,
                                           &enable_out,
                                           UInt32(MemoryLayout.size(ofValue: enable_out)))
                
                // Initialize and start on the audio processing queue
                self.audioProcessingQueue.async {
                    if AudioUnitInitialize(audioUnit) == noErr {
                        print("Audio Unit initialized successfully")
                        if AudioOutputUnitStart(audioUnit) == noErr {
                            print("Audio Unit started successfully")
                        } else {
                            print("Failed to start Audio Unit")
                        }
                    } else {
                        print("Failed to initialize Audio Unit")
                    }
                }
            } catch {
                print("Audio session setup failed: \(error)")
            }
        }
    }
    
    // MARK: - Process audio data
    var count = 0
    let inputRenderCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData
    ) -> OSStatus in
        // Use autoreleasepool to help with memory management
        autoreleasepool {
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: inNumberFrames * 2,
                    mData: UnsafeMutableRawPointer.allocate(byteCount: Int(inNumberFrames) * 2, alignment: MemoryLayout<Int16>.alignment)
                )
            )
            
            defer {
                // Free the allocated memory to prevent leaks
                bufferList.mBuffers.mData?.deallocate()
            }
            
            let status = AudioUnitRender(RecordAudioManager.shared.audioUnit!,
                                         ioActionFlags,
                                         inTimeStamp,
                                         inBusNumber,
                                         inNumberFrames,
                                         &bufferList)
            
            if status == noErr {
                let inputData = bufferList.mBuffers.mData?.assumingMemoryBound(to: Int16.self)
                let frameCount = Int(inNumberFrames)
                var int16_array: [Int16] = []
                
                for frame in 0..<frameCount {
                    let sample = inputData?[frame] ?? 0
                    int16_array.append(sample)
                }
                
                // Check memory limits before adding new buffer
                let newBufferSize = int16_array.count * MemoryLayout<Int16>.size
                if newBufferSize > RecordAudioManager.shared.maxBufferSize {
                    print("Warning: Buffer size exceeds maximum allowed size")
                    return status
                }
                
                if RecordAudioManager.shared.totalBuffersSize + newBufferSize > RecordAudioManager.shared.maxTotalBuffersSize {
                    // Remove oldest buffers until we have enough space
                    while !RecordAudioManager.shared.local_record_buffers.isEmpty &&
                          RecordAudioManager.shared.totalBuffersSize + newBufferSize > RecordAudioManager.shared.maxTotalBuffersSize {
                        if let removedBuffer = RecordAudioManager.shared.local_record_buffers.first {
                            let removedSize = Int(removedBuffer.frameLength) * MemoryLayout<Int16>.size
                            RecordAudioManager.shared.totalBuffersSize -= removedSize
                            RecordAudioManager.shared.local_record_buffers.removeFirst()
                        }
                    }
                }
                
                // Convert to PCM buffer for local storage if needed
                if let buffer = int16DataToPCMBuffer(int16Data: int16_array, sampleRate: Double(24000), channels: 1) {
                    RecordAudioManager.shared.local_record_buffers.append(buffer)
                    RecordAudioManager.shared.totalBuffersSize += newBufferSize
                }
                
                // Convert to Base64 for websocket
                let pcmData = Data(bytes: int16_array, count: int16_array.count * MemoryLayout<Int16>.size)
                let data_base64 = pcmData.base64EncodedString()
                
                // Prepare message
                var current_audio_data = [String: Any]()
                current_audio_data["type"] = "input_audio_buffer.append"
                current_audio_data["audio"] = data_base64
                current_audio_data["sequenceNumber"] = Int(RecordAudioManager.shared.count)
                RecordAudioManager.shared.local_record_Array.append(current_audio_data)
                
                // Process messages in batches to prevent memory buildup
                if RecordAudioManager.shared.count % 5 == 0 {
                    RecordAudioManager.shared.sendMessageOneByOne()
                }
                
                RecordAudioManager.shared.count += 1
                
                // Calculate audio volume for visualization
                var rmsValue: Float = 0.0
                for frame in 0..<frameCount {
                    let sample = inputData?[frame] ?? 0
                    let normalizedSample = Float(sample) / Float(Int16.max)
                    rmsValue += normalizedSample * normalizedSample
                }
                rmsValue = sqrt(rmsValue / Float(frameCount))
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name(rawValue: "showMonitorAudioDataView"), 
                                                   object: ["rmsValue": Float(rmsValue)])
                }
            } else {
                print("AudioUnitRender failed with status: \(status)")
            }
            
            return status
        }
    }
    
    func sendMessageOneByOne() {
        if self.local_record_Array.isEmpty {
            return
        }
        
        // Process messages in batches of 5
        let batchSize = 5
        let endIndex = min(batchSize, self.local_record_Array.count)
        let batch = Array(self.local_record_Array[0..<endIndex])
        
        // Remove processed messages
        self.local_record_Array.removeFirst(endIndex)
        
        // Process each message in the batch
        for (index, eventInfo) in batch.enumerated() {
            if let sequenceNumber = eventInfo["sequenceNumber"] as? Int,
               let audio = eventInfo["audio"] as? String,
               let type = eventInfo["type"] as? String {
                
                let event: [String: Any] = [
                    "type": type,
                    "audio": audio
                ]
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: event, options: []),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    
                    WebSocketManager.shared.socket.write(string: jsonString) {
                        print("Audio data sent successfully - sequence \(sequenceNumber)")
                    }
                }
            }
        }
    }
    
    // MARK: - Pause audio capture
    func pauseCaptureAudio() {
        if let audioUnit = audioUnit {
            // Stop recording
            let _ = AudioOutputUnitStop(audioUnit)
            
            // Clean up the audio unit
            AudioComponentInstanceDispose(audioUnit)
            self.audioUnit = nil
            
            // Clean buffers
            cleanupBuffers()
            
            print("Audio recording stopped and cleaned up")
        }
    }
}

// Helper function to convert Int16 data to PCM buffer
func int16DataToPCMBuffer(int16Data: [Int16], sampleRate: Double, channels: Int) -> AVAudioPCMBuffer? {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))
    
    guard let format = format,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(int16Data.count)) else {
        return nil
    }
    
    buffer.frameLength = AVAudioFrameCount(int16Data.count)
    
    // Use proper optional binding for float channel data
    guard let floatChannelData = buffer.floatChannelData else {
        return buffer
    }
    
    // floatChannelData[0] is not optional, it's a direct pointer
    let floatArray = floatChannelData[0]
    for i in 0..<int16Data.count {
        floatArray[i] = Float(int16Data[i]) / Float(Int16.max)
    }
    
    return buffer
}
