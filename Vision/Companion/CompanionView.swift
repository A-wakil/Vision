//
//  CompanionView.swift
//  Vision
//
//  Created by CAIT on 3/26/25.
//

import SwiftUI

struct CompanionView: View {
    // State variables to track conversation status
    @State private var conversationState: ConversationState = .idle
    
    // Animation properties
    @State private var userPulseScale: CGFloat = 1.0
    @State private var aiPulseScale: CGFloat = 1.0
    
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
                
                Spacer()
                
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
                .disabled(conversationState == .aiSpeaking || conversationState == .aiThinking)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            // Set initial animation states
            userPulseScale = 1.0
            aiPulseScale = 1.0
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Helper Methods
    
    private func startUserSpeaking() {
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
        
        // Simulate AI thinking and then speaking
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            simulateAIResponse()
        }
    }
    
    private func simulateAIResponse() {
        withAnimation {
            conversationState = .aiSpeaking
            aiPulseScale = 1.3
        }
        
        // Simulate AI speaking for a few seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Return to idle state
            withAnimation {
                conversationState = .idle
                aiPulseScale = 1.0
            }
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
