//
//  CompanionView.swift
//  Vision
//
//  Created by CAIT on 3/26/25.
//

import SwiftUI
import AVFoundation

struct CompanionView: View {
    // State variables to track conversation status
    @State private var conversationState: ConversationState = .idle
    
    // Animation properties
    @State private var userPulseScale: CGFloat = 1.0
    @State private var aiPulseScale: CGFloat = 1.0
    
    // State variables for text display
    @State private var userText: String = ""
    @State private var aiText: String = ""
    
    // Audio visualization
    @State private var currentRmsValue: Float = 0.0
    
    // WebSocket connection status
    @State private var isConnected: Bool = false
    @State private var isConnecting: Bool = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.8), Color.blue.opacity(0.5)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                Text("AI Companion")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                // Connection status
                if !isConnected {
                    Button(action: {
                        if !isConnecting {
                            connectToOpenAI()
                        }
                    }) {
                        HStack {
                            Image(systemName: isConnecting ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            Text(isConnecting ? "Connecting..." : "Connect to OpenAI")
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            Capsule()
                                .fill(isConnecting ? Color.orange.opacity(0.7) : Color.blue.opacity(0.7))
                        )
                        .padding(.top, 10)
                    }
                    .disabled(isConnecting)
                } else {
                    Button(action: {
                        disconnectFromOpenAI()
                    }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Disconnect")
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.7))
                        )
                        .padding(.top, 10)
                    }
                }
                
                Spacer()
                
                // Text displays
                VStack(spacing: 15) {
                    if !userText.isEmpty {
                        Text("You: \(userText)")
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.opacity(0.3))
                            )
                            .padding(.horizontal)
                    }
                    
                    if !aiText.isEmpty {
                        Text("AI: \(aiText)")
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.purple.opacity(0.3))
                            )
                            .padding(.horizontal)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                
                // Status display
                Text(conversationState.description)
                    .foregroundColor(.white)
                    .font(.headline)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        Capsule()
                            .fill(conversationState.color.opacity(0.7))
                    )
                    .padding(.bottom, 20)
                
                // Audio visualization
                if conversationState == .userSpeaking || conversationState == .aiSpeaking {
                    AudioVisualizerViewRepresentable(rmsValue: currentRmsValue)
                        .frame(height: 60)
                        .padding(.bottom, 10)
                }
                
                // Conversation visualization
                HStack(spacing: 40) {
                    // User visualization
                    VStack {
                        ZStack {
                            // Pulse animation for user
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 80, height: 80)
                                .scaleEffect(userPulseScale)
                                .animation(
                                    conversationState == .userSpeaking ?
                                        Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true) :
                                        Animation.easeInOut(duration: 0.3),
                                    value: userPulseScale
                                )
                            
                            // User icon
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                )
                        }
                        
                        Text("You")
                            .foregroundColor(.white)
                            .padding(.top, 5)
                    }
                    
                    // Status indicator
                    if conversationState == .aiThinking {
                        TypingIndicator()
                            .frame(width: 50, height: 30)
                    }
                    
                    // AI visualization
                    VStack {
                        ZStack {
                            // Pulse animation for AI
                            Circle()
                                .fill(Color.purple.opacity(0.3))
                                .frame(width: 80, height: 80)
                                .scaleEffect(aiPulseScale)
                                .animation(
                                    conversationState == .aiSpeaking ?
                                        Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true) :
                                        Animation.easeInOut(duration: 0.3),
                                    value: aiPulseScale
                                )
                            
                            // AI icon
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Image(systemName: "brain")
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                )
                        }
                        
                        Text("AI")
                            .foregroundColor(.white)
                            .padding(.top, 5)
                    }
                }
                .padding(.bottom, 20)
                
                // Talk button
                Button(action: {
                    // Toggle between user speaking and idle
                    if conversationState == .userSpeaking {
                        endUserSpeaking()
                    } else {
                        startUserSpeaking()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                conversationState == .userSpeaking ?
                                    Color.red.opacity(0.8) :
                                    Color.blue.opacity(0.8)
                            )
                            .frame(width: 70, height: 70)
                        
                        Image(systemName: conversationState == .userSpeaking ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                    }
                }
                .disabled(conversationState == .aiSpeaking || conversationState == .aiThinking || !isConnected)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            // Set initial animation states
            userPulseScale = 1.0
            aiPulseScale = 1.0
            
            // Setup notification observers
            setupNotificationObservers()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - WebSocket Methods
    
    private func connectToOpenAI() {
        isConnecting = true
        WebSocketManager.shared.connectWebSocketOfOpenAi()
    }
    
    private func disconnectFromOpenAI() {
        // Stop any ongoing audio
        PlayAudioContinuouslyManager.shared.audio_event_Queue.removeAll()
        WebSocketManager.shared.audio_String = ""
        WebSocketManager.shared.audio_String_count = 0
        
        // Stop audio recording
        RecordAudioManager.shared.pauseCaptureAudio()
        
        // Disconnect WebSocket
        WebSocketManager.shared.socket.disconnect()
        
        // Update UI state
        isConnected = false
        conversationState = .idle
    }
    
    // MARK: - Notification Handlers
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "WebSocketManager_connected_status_changed"), object: nil, queue: .main) { notification in
            self.handleConnectionStatusChange()
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "UserStartToSpeek"), object: nil, queue: .main) { _ in
            self.userText = ""
            self.aiText = ""
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "HaveInputText"), object: nil, queue: .main) { notification in
            if let dict = notification.object as? [String: Any], let text = dict["text"] as? String {
                self.userText = text
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "HaveOutputText"), object: nil, queue: .main) { notification in
            if let dict = notification.object as? [String: String], let text = dict["text"] {
                self.aiText = text
                
                // Update conversation state
                withAnimation {
                    self.conversationState = .aiSpeaking
                    self.aiPulseScale = 1.3
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "showMonitorAudioDataView"), object: nil, queue: .main) { notification in
            if let dict = notification.object as? [String: Any], let rmsValue = dict["rmsValue"] as? Float {
                self.currentRmsValue = rmsValue
            }
        }
    }
    
    private func handleConnectionStatusChange() {
        let status = WebSocketManager.shared.connected_status
        if status == "not_connected" {
            isConnected = false
            isConnecting = false
            conversationState = .idle
        } else if status == "connecting" {
            isConnected = false
            isConnecting = true
        } else if status == "connected" {
            isConnected = true
            isConnecting = false
        }
    }
    
    // MARK: - Helper Methods
    
    private func startUserSpeaking() {
        if !isConnected {
            return
        }
        
        withAnimation {
            conversationState = .userSpeaking
            userPulseScale = 1.3
            aiPulseScale = 1.0
        }
    }
    
    private func endUserSpeaking() {
        withAnimation {
            conversationState = .aiThinking
            userPulseScale = 1.0
        }
    }
}

// MARK: - Supporting Types

enum ConversationState {
    case idle
    case userSpeaking
    case aiThinking
    case aiSpeaking
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .userSpeaking:
            return "Listening..."
        case .aiThinking:
            return "Thinking..."
        case .aiSpeaking:
            return "Speaking..."
        }
    }
    
    var color: Color {
        switch self {
        case .idle:
            return .gray
        case .userSpeaking:
            return .blue
        case .aiThinking:
            return .orange
        case .aiSpeaking:
            return .purple
        }
    }
}

struct TypingIndicator: View {
    @State private var firstDotOpacity: Double = 0.3
    @State private var secondDotOpacity: Double = 0.3
    @State private var thirdDotOpacity: Double = 0.3
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .opacity(firstDotOpacity)
            
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .opacity(secondDotOpacity)
            
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .opacity(thirdDotOpacity)
        }
        .onAppear {
            let animation = Animation.easeInOut(duration: 0.4).repeatForever()
            
            withAnimation(animation.delay(0.0)) {
                firstDotOpacity = 1.0
            }
            
            withAnimation(animation.delay(0.2)) {
                secondDotOpacity = 1.0
            }
            
            withAnimation(animation.delay(0.4)) {
                thirdDotOpacity = 1.0
            }
        }
    }
}

#Preview {
    CompanionView()
}
