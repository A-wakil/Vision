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
    
    static let shared = RecordAudioManager()
    private override init() {
        super.init()
    }
    
    // MARK: - Start audio recording
    func startRecordAudio() {
        if audioUnit != nil {
            RecordAudioManager.shared.count = 0
            RecordAudioManager.shared.local_record_Array = [[String: Any]]()
            AudioOutputUnitStart(audioUnit!)
            return
        }
        
        // Check microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                print("The user denied microphone permission.")
            } else {
                print("Microphone permission granted.")
            }
        }
        
        // Set up audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            print("Audio session setup successful")
        } catch {
            print("Audio session setup failed: \(error)")
        }
        
        // Initialize audio component
        var audioComponentDesc = AudioComponentDescription()
        audioComponentDesc.componentType = kAudioUnitType_Output
        audioComponentDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO // Echo cancellation mode
        audioComponentDesc.componentManufacturer = kAudioUnitManufacturer_Apple
        audioComponentDesc.componentFlags = 0
        audioComponentDesc.componentFlagsMask = 0
        
        // Create audio unit
        guard let audioComponent = AudioComponentFindNext(nil, &audioComponentDesc) else {
            print("Failed to find Audio Unit")
            return
        }
        
        AudioComponentInstanceNew(audioComponent, &audioUnit)
        guard let audioUnit = audioUnit else {
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
                             1, // Input bus
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
        
        // Initialize and start
        if AudioUnitUninitialize(audioUnit) == noErr {
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
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: inNumberFrames * 2,
                mData: UnsafeMutableRawPointer.allocate(byteCount: Int(inNumberFrames) * 2, alignment: MemoryLayout<Int16>.alignment)
            )
        )
        
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
            
            // Convert to PCM buffer for local storage if needed
            if let buffer = int16DataToPCMBuffer(int16Data: int16_array, sampleRate: Double(44100), channels: 1) {
                RecordAudioManager.shared.local_record_buffers.append(buffer)
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
            
            if RecordAudioManager.shared.count == 0 || RecordAudioManager.shared.local_record_Array.count == 1 {
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
            
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "showMonitorAudioDataView"), 
                                           object: ["rmsValue": Float(rmsValue)])
        } else {
            print("AudioUnitRender failed with status: \(status)")
        }
        
        return noErr
    }
    
    func sendMessageOneByOne() {
        if self.local_record_Array.count <= 0 {
            return
        }
        
        let firstEventInfo = self.local_record_Array[0]
        if let sequenceNumber = firstEventInfo["sequenceNumber"] as? Int,
           let audio = firstEventInfo["audio"] as? String,
           let type = firstEventInfo["type"] as? String {
            
            let event: [String: Any] = [
                "type": type,
                "audio": audio
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: event, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                
                WebSocketManager.shared.socket.write(string: jsonString) {
                    if self.local_record_Array.count > 0 {
                        self.local_record_Array.removeFirst()
                        self.sendMessageOneByOne()
                        print("Audio data sent successfully - sequence \(sequenceNumber)")
                    }
                }
            }
        }
    }
    
    // MARK: - Pause audio capture
    func pauseCaptureAudio() {
        DispatchQueue.main.async {
            guard let audioUnit = self.audioUnit else { return }
            
            if AudioOutputUnitStop(audioUnit) == noErr {
                print("Audio capture paused successfully")
            } else {
                print("Failed to pause audio capture")
            }
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
