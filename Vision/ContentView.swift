//
//  ContentView.swift
//  Vision
//
//  Created by CAIT on 3/12/25.
//

import SwiftUI
import AVFoundation
import CoreImage

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
                    // Replay Button
                    Button(action: {
                        audioPlayer?.play()
                    }) {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            )
                    }
                    .disabled(audioPlayer == nil)
                    
                    // Speaker Button
                    Button(action: {
                        guard !isProcessingFrame else { return }
                        Task {
                            do {
                                isProcessingFrame = true
                                if let frame = frameHandler.frame {
                                    let ciImage = CIImage(cgImage: frame)
                                    let context = CIContext()
                                    if let imageData = context.jpegRepresentation(of: ciImage, colorSpace: CGColorSpaceCreateDeviceRGB()) {
                                        // Get image description from OpenAI Vision
                                        let description = try await openAIService.describeImage(imageData, language: currentLanguage)
                                        print("Got description, attempting TTS...")
                                        
                                        // Convert description to speech
                                        let audioData = try await openAIService.textToSpeech(description)
                                        print("Received audio data size: \(audioData.count) bytes")
                                        
                                        // Play the audio
                                        do {
                                            audioPlayer = try AVAudioPlayer(data: audioData)
                                            print("Created audio player")
                                            
                                            // Setup audio session
                                            try AVAudioSession.sharedInstance().setCategory(.playback)
                                            try AVAudioSession.sharedInstance().setActive(true)
                                            print("Audio session activated")
                                            
                                            if audioPlayer?.play() == true {
                                                print("Started playing audio")
                                                isSpeaking = true
                                            } else {
                                                print("Failed to start audio playback")
                                            }
                                        } catch {
                                            print("Audio setup error: \(error)")
                                        }
                                    }
                                }
                            } catch {
                                print("Error: \(error)")
                                showingError = true
                                errorMessage = error.localizedDescription
                            }
                            isProcessingFrame = false
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

#Preview {
    ContentView()
}
