//
//  SharedState.swift
//  Vision
//
//  Created by CAIT on 3/31/25.
//

import Foundation
import SwiftUI

// This class will act as a shared state container across different views
class SharedContextManager: ObservableObject {
    // Singleton instance
    static let shared = SharedContextManager()
    
    // Maximum number of stored descriptions
    private let maxStoredDescriptions = 5
    
    // The stored descriptions with timestamps
    @Published private var storedDescriptions: [(description: String, timestamp: Date)] = []
    
    // Current formatted context string
    @Published var currentContext: String = ""
    
    private init() {}
    
    // Add a new description to the context
    func addDescription(_ description: String) {
        // Add new description with current timestamp
        storedDescriptions.append((description: description, timestamp: Date()))
        
        // Remove oldest if we exceed the maximum
        if storedDescriptions.count > maxStoredDescriptions {
            storedDescriptions.removeFirst()
        }
        
        // Update the current context string
        updateCurrentContext()
    }
    
    // Clear all stored descriptions
    func clearContext() {
        storedDescriptions.removeAll()
        currentContext = ""
    }
    
    // Update the current context string based on stored descriptions
    private func updateCurrentContext() {
        // Format the context with timestamps and descriptions
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        var contextComponents: [String] = []
        
        for (index, item) in storedDescriptions.enumerated() {
            let timeString = dateFormatter.string(from: item.timestamp)
            contextComponents.append("[\(timeString)] Description \(index + 1): \(item.description)")
        }
        
        currentContext = contextComponents.joined(separator: "\n\n")
    }
    
    // Get the current context for use with the OpenAI API
    func getCurrentContextForAPI() -> String? {
        return storedDescriptions.isEmpty ? nil : currentContext
    }
}
