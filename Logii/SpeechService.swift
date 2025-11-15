//
//  SpeechService.swift
//  Logii
//
//  Created by Sabath  Rodriguez on 11/10/25.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

// 1. Must be NSObject to be a delegate, and ObservableObject to update the UI
class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    private let ttsSynthesizer = AVSpeechSynthesizer()
    
    // 2. The full text to be spoken
    private var fullText: String = ""
    
    // 3. The "Bookmark"
    //    We publish this so you could even make a progress bar later
    @Published var speechProgress: NSRange = NSRange(location: 0, length: 0)
    
    // 4. Published state for your UI
    @Published var isSpeaking: Bool = false
    
    override init() {
        super.init()
        // 5. Set this class as the delegate
        self.ttsSynthesizer.delegate = self
    }
    
    // --- PUBLIC COMMANDS ---
    
    func speakFromBeginning(text: String, rate: Float) {
        ttsSynthesizer.stopSpeaking(at: .immediate)
        self.fullText = text
        self.speechProgress = NSRange(location: 0, length: 0) // Reset bookmark
        
        let utterance = AVSpeechUtterance(string: self.fullText)
        utterance.rate = rate
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.speech.synthesis.voice.siri_female_en-US_enhanced")
        
        ttsSynthesizer.speak(utterance)
    }
    
    func playOrResume(rate: Float) {
        if ttsSynthesizer.isPaused {
            // It was just paused, so continue
            ttsSynthesizer.continueSpeaking()
        } else if !self.fullText.isEmpty {
            // It was stopped, so start a new speech from the bookmarked location
            ttsSynthesizer.stopSpeaking(at: .immediate) // Clear old one first
            
            // 6. Get the *remaining* text from the bookmark
            let remainingText = (self.fullText as NSString).substring(from: self.speechProgress.location)
            
            let utterance = AVSpeechUtterance(string: remainingText)
            utterance.rate = rate
            utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.speech.synthesis.voice.siri_female_en-US_enhanced")
            
            ttsSynthesizer.speak(utterance)
        }
    }
    
    func pause() {
        ttsSynthesizer.pauseSpeaking(at: .word)
    }
    
    func stop() {
        ttsSynthesizer.stopSpeaking(at: .immediate)
    }
    
    // --- AVSPEECHSYNTHESIZER DELEGATE METHODS ---
    
    // 7. THIS IS THE KEY: The synthesizer tells us where it's about to speak
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        // Update our bookmark
        DispatchQueue.main.async {
            self.speechProgress = range
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
    }
    
    // Called when speech is finished OR cancelled
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            // Reset bookmark to the start
            self.speechProgress = NSRange(location: 0, length: 0)
        }
    }
    
    // 8. IMPORTANT: Called by stopSpeaking().
    //    We DON'T reset the bookmark here, because we want to save our spot.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}

