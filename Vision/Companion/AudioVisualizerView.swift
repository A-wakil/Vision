//
//  AudioVisualizerView.swift
//  Vision
//
//  Created by CAIT on 3/27/25.
//

import SwiftUI
import UIKit

class AudioVisualizerView: UIView {
    
    private var circleViews = [UIView]()
    private let numberOfCircles = 5
    private let maxCircleSize: CGFloat = 25
    private let minCircleSize: CGFloat = 5
    
    // Colors for the circles
    private let circleColors: [UIColor] = [
        UIColor(red: 0.4, green: 0.2, blue: 0.7, alpha: 0.8),
        UIColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 0.7),
        UIColor(red: 0.6, green: 0.4, blue: 0.9, alpha: 0.6),
        UIColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 0.5),
        UIColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 0.4)
    ]
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCircles()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCircles()
    }
    
    private func setupCircles() {
        // Remove any existing circles
        for view in circleViews {
            view.removeFromSuperview()
        }
        circleViews.removeAll()
        
        // Center point for the visualizer
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2
        
        // Create and position circles
        for i in 0..<numberOfCircles {
            let size = minCircleSize + CGFloat(i) * (maxCircleSize - minCircleSize) / CGFloat(numberOfCircles - 1)
            let circleView = UIView(frame: CGRect(x: centerX - size/2, y: centerY - size/2, width: size, height: size))
            circleView.backgroundColor = circleColors[i % circleColors.count]
            circleView.layer.cornerRadius = size / 2
            addSubview(circleView)
            circleViews.append(circleView)
            
            // Initially hide the circles
            circleView.alpha = 0
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setupCircles()
    }
    
    // Update the circles based on audio volume
    func updateCircles(with rmsValue: Float) {
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2
        
        // Amplify the RMS value to make visualization more dramatic
        let amplifiedValue = min(1.0, rmsValue * 3.0)
        
        for (index, circleView) in circleViews.enumerated() {
            // Calculate size based on audio volume
            let maxSize = minCircleSize + CGFloat(index) * (maxCircleSize - minCircleSize) / CGFloat(numberOfCircles - 1)
            let size = maxSize * CGFloat(amplifiedValue)
            
            // Update position and size with animation
            UIView.animate(withDuration: 0.1) {
                circleView.frame = CGRect(x: centerX - size/2, y: centerY - size/2, width: size, height: size)
                circleView.layer.cornerRadius = size / 2
                circleView.alpha = CGFloat(amplifiedValue)
            }
        }
    }
}

// SwiftUI wrapper for the UIKit AudioVisualizerView
struct AudioVisualizerViewRepresentable: UIViewRepresentable {
    var rmsValue: Float
    
    func makeUIView(context: Context) -> AudioVisualizerView {
        return AudioVisualizerView(frame: .zero)
    }
    
    func updateUIView(_ uiView: AudioVisualizerView, context: Context) {
        uiView.updateCircles(with: rmsValue)
    }
}

#Preview {
    AudioVisualizerView()
}
