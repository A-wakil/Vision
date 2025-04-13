//
//  VisionApp.swift
//  Vision
//
//  Created by CAIT on 3/12/25.
//

import SwiftUI
import UIKit

// Create an AppDelegate class to handle application lifecycle and screen timeout
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set up notification observers for conversation state changes
        setupNotificationObservers()
        return true
    }
    
    private func setupNotificationObservers() {
        // Listen for conversation state changes to manage screen timeout
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "ConversationStateChanged"),
            object: nil,
            queue: .main
        ) { notification in
            if let dict = notification.object as? [String: String], let state = dict["state"] {
                self.updateIdleTimer(for: state)
            }
        }
        
        // Listen for specific AI speaking notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "HaveOutputText"),
            object: nil,
            queue: .main
        ) { _ in
            // When AI starts speaking, prevent screen timeout
            UIApplication.shared.isIdleTimerDisabled = true
        }
        
        // Listen for audio playback finished
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "AudioPlaybackFinished"),
            object: nil,
            queue: .main
        ) { _ in
            // When audio playback finishes, allow screen timeout again
            UIApplication.shared.isIdleTimerDisabled = false
        }
        
        // Listen for audio playback stopped
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "AudioPlaybackStopped"),
            object: nil,
            queue: .main
        ) { _ in
            // When audio playback is stopped, allow screen timeout again
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    private func updateIdleTimer(for state: String) {
        switch state {
        case "userSpeaking", "aiThinking", "aiSpeaking":
            // Prevent screen timeout when user is speaking, AI is thinking, or AI is speaking
            UIApplication.shared.isIdleTimerDisabled = true
        case "idle":
            // Allow normal screen timeout when the app is idle
            UIApplication.shared.isIdleTimerDisabled = false
        default:
            break
        }
    }
}

@main
struct VisionApp: App {
    // Register the AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
