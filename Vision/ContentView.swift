//
//  ContentView.swift
//  Vision
//
//  Created by CAIT on 3/12/25.
//

import SwiftUI
import AVFoundation
import CoreImage
import Accelerate

struct ContentView: View {
    @StateObject private var frameHandler = FrameHandler()
    private let openAIService = OpenAIService.shared
    @State private var isSpeaking = false
    @State private var isProcessingFrame = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var currentLanguage = "en" // Default to English
    @State private var showLanguageSelector = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioUpdateCounter = 0
    @State private var lastAudioUpdateTime = Date()
    
    // Add this to store the delegate
    @State private var audioPlayerDelegate: AudioPlayerDelegate?
    
    // Add this to track if audio is currently playing
    @State private var isAudioPlaying = false
    
    // Audio engine components
    @State private var audioEngine: AVAudioEngine?
    @State private var audioPlayerNode: AVAudioPlayerNode?
    @State private var audioFile: AVAudioFile?
    @State private var audioBuffer = [Float]()
    @State private var audioFormat: AVAudioFormat?
    
    // Add this state variable to store complete audio data
    @State private var completeAudioData: Data?
    
    let supportedLanguages = [
        "en": "English", "es": "Spanish", "fr": "French",
        "de": "German", "it": "Italian", "pt": "Portuguese",
        "nl": "Dutch", "pl": "Polish", "ru": "Russian",
        "ja": "Japanese", "ko": "Korean", "zh": "Chinese",
        "ar": "Arabic", "hi": "Hindi", "tr": "Turkish"
    ]
    
    var body: some View {
        ZStack {
            // Camera View
            FrameView(image: frameHandler.frame)
                .ignoresSafeArea()
            
            // Error Banner
            if showingError {
                VStack {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Error: \(errorMessage)")
                    }
                    .padding()
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.top)
                    Spacer()
                }
            }
            
            // Bottom Button Controls
            VStack {
                Spacer()
                HStack(spacing: 40) {
                    // Replay/Stop Button
                    Button(action: {
                        if isAudioPlaying {
                            // Stop audio if playing
                            if audioEngine != nil {
                                // Stop streaming audio
                                stopAudioEngine()
                            } else if let player = audioPlayer {
                                // Stop replay audio
                                player.stop()
                                audioPlayer = nil
                                isAudioPlaying = false
                                isSpeaking = false
                            }
                            print("Audio manually stopped by user")
                        } else if let audioData = completeAudioData {
                            // Replay the complete audio
                            do {
                                // Setup audio session
                                try AVAudioSession.sharedInstance().setCategory(.playback)
                                try AVAudioSession.sharedInstance().setActive(true)
                                
                                // Create audio player
                                let player = try AVAudioPlayer(data: audioData)
                                audioPlayer = player
                                
                                // Create and store the delegate
                                audioPlayerDelegate = AudioPlayerDelegate(
                                    onPlay: { 
                                        isSpeaking = true 
                                        isAudioPlaying = true
                                        print("Replay started")
                                    },
                                    onStop: { 
                                        isSpeaking = false 
                                        isAudioPlaying = false
                                        print("Replay stopped")
                                    }
                                )
                                
                                // Set the delegate
                                player.delegate = audioPlayerDelegate
                                
                                // Play the audio
                                player.prepareToPlay()
                                if player.play() {
                                    isAudioPlaying = true
                                    isSpeaking = true
                                    print("Audio replay started")
                                } else {
                                    print("Failed to start audio replay")
                                }
                            } catch {
                                print("Error replaying audio: \(error)")
                            }
                        }
                    }) {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: isAudioPlaying ? "stop.fill" : "arrow.clockwise")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            )
                    }
                    .disabled(isAudioPlaying == false && completeAudioData == nil) // Enable only when audio is playing or we have data to replay
                    
                    // Speaker Button
                    Button(action: {
                        // First, stop any currently playing audio
                        if isAudioPlaying {
                            if audioEngine != nil {
                                // Stop streaming audio
                                stopAudioEngine()
                            } else if let player = audioPlayer {
                                // Stop replay audio
                                player.stop()
                                audioPlayer = nil
                                isAudioPlaying = false
                                isSpeaking = false
                            }
                        }
                        
                        guard !isProcessingFrame else { return }
                        isProcessingFrame = true
                        isSpeaking = false
                        
                        // Start timing
                        let startTime = Date()
                        print("⏱️ [0ms] Starting image processing")
                        
                        if let frame = frameHandler.frame {
                            let ciImage = CIImage(cgImage: frame)
                            let context = CIContext()
                            if let imageData = context.jpegRepresentation(of: ciImage, colorSpace: CGColorSpaceCreateDeviceRGB()) {
                                Task {
                                    do {
                                        print("⏱️ [\(Int(-startTime.timeIntervalSinceNow * 1000))ms] Image converted to JPEG, sending to OpenAI")
                                        
                                        let description = try await openAIService.describeImage(imageData, language: currentLanguage)
                                        print("⏱️ [\(Int(-startTime.timeIntervalSinceNow * 1000))ms] Got description (\(description.count) chars), starting TTS streaming")
                                        
                                        // Setup audio engine
                                        await setupAudioEngine()
                                        
                                        // Start streaming
                                        openAIService.textToSpeechStreaming(
                                            text: description,
                                            model: "gpt-4o-mini-tts",
                                            voice: "nova",
                                            responseFormat: "pcm",
                                            onChunk: { pcmChunk in
                                                Task {
                                                    await processAudioChunk(pcmChunk, startTime: startTime)
                                                }
                                            },
                                            onComplete: { error in
                                                Task {
                                                    await handleStreamingComplete(error, startTime: startTime)
                                                }
                                            }
                                        )
                                    } catch {
                                        print("⏱️ [\(Int(-startTime.timeIntervalSinceNow * 1000))ms] Error: \(error)")
                                        showingError = true
                                        errorMessage = error.localizedDescription
                                        isProcessingFrame = false
                                        isSpeaking = false
                                    }
                                }
                            }
                        }
                    }) {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Group {
                                    if isProcessingFrame {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(1.5)
                                    } else if isSpeaking {
                                        AnimatedSpeakerView()
                                    } else {
                                        Image(systemName: "speaker.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(.white)
                                    }
                                }
                            )
                    }
                    .disabled(isProcessingFrame)
                    
                    // Language Button
                    Button(action: {
                        showLanguageSelector = true
                    }) {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 60, height: 60)
                            .overlay(
                                VStack(spacing: 2) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 16))
                                    Text(currentLanguage.uppercased())
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundColor(.white)
                            )
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showLanguageSelector) {
            NavigationView {
                List(supportedLanguages.sorted(by: { $0.value < $1.value }), id: \.key) { code, name in
                    Button(action: {
                        currentLanguage = code
                        showLanguageSelector = false
                    }) {
                        HStack {
                            Text(name)
                            Spacer()
                            if code == currentLanguage {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .navigationTitle("Select Language")
                .navigationBarItems(trailing: Button("Done") {
                    showLanguageSelector = false
                })
            }
        }
    }
    
    // Add these methods to handle audio streaming
    
    func setupAudioEngine() async {
        await MainActor.run {
            // Stop any existing audio
            stopAudioEngine()
            
            // Create new audio engine components
            audioEngine = AVAudioEngine()
            audioPlayerNode = AVAudioPlayerNode()
            audioBuffer = []
            
            // Configure audio session
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
                
                // Setup audio format (24kHz, mono, 16-bit PCM)
                audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                           sampleRate: 24000, 
                                           channels: 1, 
                                           interleaved: false)
                
                if let engine = audioEngine, let playerNode = audioPlayerNode, let format = audioFormat {
                    // Connect nodes
                    engine.attach(playerNode)
                    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
                    
                    // Start engine
                    try engine.start()
                    print("Audio engine started successfully")
                    
                    isAudioPlaying = true
                }
            } catch {
                print("Error setting up audio engine: \(error)")
                isAudioPlaying = false
            }
        }
    }
    
    func processAudioChunk(_ pcmChunk: Data, startTime: Date) async {
        // Convert PCM data to float array
        let pcmSamples = pcmChunk.withUnsafeBytes { pointer -> [Int16] in
            let int16Pointer = pointer.bindMemory(to: Int16.self)
            return Array(int16Pointer)
        }
        
        // Convert Int16 samples to Float
        var floatSamples = [Float](repeating: 0, count: pcmSamples.count)
        vDSP_vflt16(pcmSamples, 1, &floatSamples, 1, vDSP_Length(pcmSamples.count))
        
        // Normalize to -1.0 to 1.0 range
        var normalizedSamples = [Float](repeating: 0, count: floatSamples.count)
        var divisor = Float(Int16.max)
        vDSP_vsdiv(floatSamples, 1, &divisor, &normalizedSamples, 1, vDSP_Length(floatSamples.count))
        
        await MainActor.run {
            // Add to buffer
            audioBuffer.append(contentsOf: normalizedSamples)
            
            // Create buffer from samples
            if let format = audioFormat, let playerNode = audioPlayerNode {
                let bufferSize = normalizedSamples.count
                let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferSize))
                
                if let channelData = audioBuffer?.floatChannelData {
                    for i in 0..<bufferSize {
                        channelData[0][i] = normalizedSamples[i]
                    }
                    audioBuffer?.frameLength = AVAudioFrameCount(bufferSize)
                    
                    // Schedule buffer for playback
                    playerNode.scheduleBuffer(audioBuffer!, completionHandler: nil)
                    
                    // Start playback if not already playing
                    if !playerNode.isPlaying {
                        playerNode.play()
                        isSpeaking = true
                        print("⏱️ [\(Int(-startTime.timeIntervalSinceNow * 1000))ms] Audio streaming started")
                    }
                }
            }
        }
    }
    
    func handleStreamingComplete(_ error: Error?, startTime: Date) async {
        await MainActor.run {
            if let error = error {
                print("⏱️ [\(Int(-startTime.timeIntervalSinceNow * 1000))ms] Streaming error: \(error)")
                showingError = true
                errorMessage = error.localizedDescription
                completeAudioData = nil
            } else {
                print("⏱️ [\(Int(-startTime.timeIntervalSinceNow * 1000))ms] Streaming completed successfully")
                
                // Save the complete audio buffer for replay
                if !audioBuffer.isEmpty, let format = audioFormat {
                    // Convert float buffer to PCM data
                    let bufferSize = audioBuffer.count
                    var int16Samples = [Int16](repeating: 0, count: bufferSize)
                    
                    // Scale back to Int16 range
                    var scaleFactor = Float(Int16.max)
                    vDSP_vsmul(audioBuffer, 1, &scaleFactor, &audioBuffer, 1, vDSP_Length(bufferSize))
                    
                    // Convert to Int16
                    vDSP_vfix16(audioBuffer, 1, &int16Samples, 1, vDSP_Length(bufferSize))
                    
                    // Create PCM data
                    let pcmData = Data(bytes: int16Samples, count: int16Samples.count * 2)
                    
                    // Create WAV data
                    completeAudioData = try? createWaveFile(pcmData: pcmData)
                    print("⏱️ [\(Int(-startTime.timeIntervalSinceNow * 1000))ms] Saved complete audio for replay (\(completeAudioData?.count ?? 0) bytes)")
                    
                    // Schedule a final silent buffer to detect when all audio has finished playing
                    if let playerNode = audioPlayerNode {
                        // Create a tiny silent buffer (1 frame)
                        let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)
                        silentBuffer?.frameLength = 1
                        
                        // Schedule it to play after all other buffers with a completion handler
                        playerNode.scheduleBuffer(silentBuffer!) {
                            // This will be called when all audio has finished playing
                            DispatchQueue.main.async {
                                self.isSpeaking = false
                                self.isAudioPlaying = false
                                print("⏱️ [\(Int(-startTime.timeIntervalSinceNow * 1000))ms] All audio playback completed")
                            }
                        }
                    }
                }
            }
            isProcessingFrame = false
        }
    }
    
    func stopAudioEngine() {
        // Stop and clean up audio engine
        audioPlayerNode?.stop()
        audioEngine?.stop()
        audioPlayerNode = nil
        audioEngine = nil
        isSpeaking = false
        isAudioPlaying = false
        print("Audio engine stopped")
    }
}

struct AnimatedSpeakerView: View {
    // Discrete opacities for each wave
    @State private var waveOpacity1 = 0.0
    @State private var waveOpacity2 = 0.0
    @State private var waveOpacity3 = 0.0
    
    // We'll cycle through steps 0..6:
    //  0 -> all waves off
    //  1 -> wave 1 on
    //  2 -> wave 1 & 2 on
    //  3 -> wave 1, 2 & 3 on
    //  4 -> wave 1 & 2 on
    //  5 -> wave 1 on
    //  6 -> all waves off (then back to 0)
    @State private var step = 0
    
    var body: some View {
        ZStack {
            // Static base speaker icon
            Image(systemName: "speaker.fill")
                .font(.system(size: 50))
                .foregroundColor(.white)
            
            // "Waves" to the right
            HStack(spacing: 4) {
                // Wave 1
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 3, height: 20)
                    .opacity(waveOpacity1)
                
                // Wave 2
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 3, height: 30)
                    .opacity(waveOpacity2)
                
                // Wave 3
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 3, height: 40)
                    .opacity(waveOpacity3)
            }
            .offset(x: 25) // Move waves next to speaker
        }
        .onAppear {
            // Fire the timer every 0.6s (adjust as desired)
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                step = (step + 1) % 7
                
                // Wrap each step's opacity changes in an animation block
                withAnimation(.easeInOut(duration: 0.5)) {
                    switch step {
                    case 1:
                        waveOpacity1 = 1;   waveOpacity2 = 0;   waveOpacity3 = 0
                    case 2:
                        waveOpacity1 = 1;   waveOpacity2 = 1;   waveOpacity3 = 0
                    case 3:
                        waveOpacity1 = 1;   waveOpacity2 = 1;   waveOpacity3 = 1
                    case 4:
                        waveOpacity1 = 1;   waveOpacity2 = 1;   waveOpacity3 = 0
                    case 5:
                        waveOpacity1 = 1;   waveOpacity2 = 0;   waveOpacity3 = 0
                    default:
                        // steps 0 & 6: all waves off
                        waveOpacity1 = 0;   waveOpacity2 = 0;   waveOpacity3 = 0
                    }
                }
            }
        }
    }
}

// Add this helper function to convert PCM to WAV
private func createWaveFile(pcmData: Data) throws -> Data {
    let wavHeader = createWavHeader(pcmDataSize: UInt32(pcmData.count))
    var wavData = Data()
    wavData.append(wavHeader)
    wavData.append(pcmData)
    return wavData
}

private func createWavHeader(pcmDataSize: UInt32) -> Data {
    var header = Data()
    
    // RIFF chunk descriptor
    header.append("RIFF".data(using: .utf8)!)
    header.append(UInt32(pcmDataSize + 36).littleEndian.data)
    header.append("WAVE".data(using: .utf8)!)
    
    // "fmt " sub-chunk
    header.append("fmt ".data(using: .utf8)!)
    header.append(UInt32(16).littleEndian.data)  // Subchunk1Size (16 for PCM)
    header.append(UInt16(1).littleEndian.data)   // AudioFormat (1 for PCM)
    header.append(UInt16(1).littleEndian.data)   // NumChannels (1 for mono)
    header.append(UInt32(24000).littleEndian.data) // SampleRate (24kHz)
    header.append(UInt32(48000).littleEndian.data) // ByteRate (SampleRate * NumChannels * BitsPerSample/8)
    header.append(UInt16(2).littleEndian.data)   // BlockAlign (NumChannels * BitsPerSample/8)
    header.append(UInt16(16).littleEndian.data)  // BitsPerSample (16 bits)
    
    // "data" sub-chunk
    header.append("data".data(using: .utf8)!)
    header.append(UInt32(pcmDataSize).littleEndian.data)
    
    return header
}

// Add extension to help with binary data conversion
extension FixedWidthInteger {
    var data: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

// Update the AudioPlayerDelegate to track isAudioPlaying
class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onPlay: () -> Void
    private let onStop: () -> Void
    
    init(onPlay: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onPlay = onPlay
        self.onStop = onStop
        super.init()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.onStop()
        }
    }
    
    func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        DispatchQueue.main.async {
            self.onStop()
        }
    }
    
    func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        if player.play() {
            DispatchQueue.main.async {
                self.onPlay()
            }
        }
    }
}

#Preview {
    ContentView()
}
