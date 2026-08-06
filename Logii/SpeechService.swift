import Foundation
import AVFoundation
import SwiftUI
import Combine

class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    private let ttsSynthesizer = AVSpeechSynthesizer()
    private var fullText: String = ""
    
    // NEW: Tracks how much text was skipped if we resumed mid-page
    private var currentUtteranceOffset: Int = 0
    
    // NEW: Counter to handle multiple rapid stops (like scrubbing)
    private var explicitStopCount: Int = 0
    
    // Callback to trigger the next page load
    var onDidFinishUtterance: (() -> Void)?
    
    @Published var rate: Float = 0.5
    @Published var isSpeaking: Bool = false
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "en-US")

    // Sends the current range to the PDFView for highlighting
    var speechProgress: NSRange = NSRange(location: 0, length: 0)
    let speechProgressPublisher = PassthroughSubject<NSRange, Never>()
    
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        self.ttsSynthesizer.delegate = self
        loadVoices()
        
        // Watch for voice changes to auto-restart
        $selectedVoice
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restartIfActive()
            }
            .store(in: &cancellables)
            
        // Watch for rate changes to auto-restart (Scrubbing logic)
        $rate
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restartIfActive()
            }
            .store(in: &cancellables)
    }
    
    private func loadVoices() {
        self.availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }
            .sorted { $0.name < $1.name }
    }
    
    // Helper to safely stop without triggering page turns
    private func stopAndIgnoreFinish() {
        // Only count it if the synthesizer is actually doing something that will trigger didFinish
        if ttsSynthesizer.isSpeaking || ttsSynthesizer.isPaused {
            explicitStopCount += 1
            ttsSynthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    private func restartIfActive() {
        // If we are currently active, stop (ignoring finish) and resume
        if isSpeaking || ttsSynthesizer.isPaused {
            stopAndIgnoreFinish()
            playOrResume()
        }
    }
    
    func speakFromBeginning(text: String) {
        // Stop any previous speech without triggering next page
        stopAndIgnoreFinish()
        
        self.fullText = text
        self.speechProgress = NSRange(location: 0, length: 0)
        self.currentUtteranceOffset = 0
        
        // Ensure count is clean for new speech if it somehow got desynced
        // (Though strictly relying on increment/decrement is safer, resetting here ensures we don't block the new speech)
        // Only reset if we are sure we are stopped.
        // Actually, safer to let the logic flow, but forcing 0 here resets state for the NEW page.
        // Any pending 'didFinish' from the previous page stop should have been caught by stopAndIgnoreFinish above.
        // However, since we are starting FRESH, we want to respect the stop count for the stop we just issued,
        // but ensure we are ready for the new finish.
        // The safest approach: The stopAndIgnoreFinish() incremented the count. The pending didFinish will decrement it.
        // So we don't reset explicitStopCount here.
        
        let utterance = AVSpeechUtterance(string: self.fullText)
        utterance.rate = self.rate
        utterance.voice = selectedVoice
        
        ttsSynthesizer.speak(utterance)
    }
        
    func playOrResume() {
        if ttsSynthesizer.isPaused {
            ttsSynthesizer.continueSpeaking()
        } else if !self.fullText.isEmpty {
            
            // If we are already speaking, stop first (ignoring finish)
            stopAndIgnoreFinish()
            
            // Resume from where we left off
            let startIndex = self.speechProgress.location
            
            // Safety check
            if startIndex < fullText.count {
                let remainingText = (self.fullText as NSString).substring(from: startIndex)
                
                // SAVE THE OFFSET!
                self.currentUtteranceOffset = startIndex
                
                let utterance = AVSpeechUtterance(string: remainingText)
                utterance.rate = self.rate
                utterance.voice = selectedVoice
                
                ttsSynthesizer.speak(utterance)
            } else {
                 // End of text, treat as natural finish? Or just stop.
                 // If we consider it natural finish, we might loop. Let's just stop.
                 self.isSpeaking = false
            }
        }
    }
    
    func pause() {
        ttsSynthesizer.pauseSpeaking(at: .word)
    }
    
    func stop() {
        stopAndIgnoreFinish()
        self.currentUtteranceOffset = 0
    }
    
    // --- DELEGATE METHODS ---
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        
        DispatchQueue.main.async {
            // Add the offset back to the range location
            let correctedLocation = range.location + self.currentUtteranceOffset
            let correctedRange = NSRange(location: correctedLocation, length: range.length)
            
            self.speechProgress = correctedRange
            self.speechProgressPublisher.send(correctedRange)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            
            // CRITICAL FIX WITH COUNTER:
            if self.explicitStopCount > 0 {
                // This finish was caused by our code (stop/scrub).
                // Ignore it and decrement the counter.
                self.explicitStopCount -= 1
            } else {
                // This was a natural finish (end of page).
                // Load the next page.
                self.currentUtteranceOffset = 0
                self.onDidFinishUtterance?()
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.currentUtteranceOffset = 0
            // Cancel usually means we don't want to proceed.
            // We can clear the count here to be safe.
            self.explicitStopCount = 0
        }
    }
}
