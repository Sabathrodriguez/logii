import Foundation
import AVFoundation
import SwiftUI
import Combine

class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    private let ttsSynthesizer = AVSpeechSynthesizer()
    private var fullText: String = ""
    
    // 1. FIX SYNC: Track how much text we have already spoken in previous sessions
    private var currentUtteranceOffset: Int = 0
    
    @Published var rate: Float = 0.5
    @Published var isSpeaking: Bool = false
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "en-US")

    // 2. FIX SCROLLING: Remove @Published. Use a Subject so only the PDFView listens, not the whole UI.
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
    }
    
    private func loadVoices() {
        self.availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }
            .sorted { $0.name < $1.name }
        
//        if let premium = availableVoices.first(where: { $0.quality == .premium }) {
//            self.selectedVoice = premium
//        } else {
//            self.selectedVoice = availableVoices.first
//        }
    }
    
    private func restartIfActive() {
        if isSpeaking || ttsSynthesizer.isPaused {
            ttsSynthesizer.stopSpeaking(at: .immediate)
            playOrResume()
        }
    }
    
    func speakFromBeginning(text: String) {
        ttsSynthesizer.stopSpeaking(at: .immediate)
        
        self.fullText = text
        self.speechProgress = NSRange(location: 0, length: 0)
        self.currentUtteranceOffset = 0 // Reset offset
        
        let utterance = AVSpeechUtterance(string: self.fullText)
        utterance.rate = self.rate
        utterance.voice = selectedVoice
        
        ttsSynthesizer.speak(utterance)
    }
        
    func playOrResume() {
        if ttsSynthesizer.isPaused {
            ttsSynthesizer.continueSpeaking()
        } else if !self.fullText.isEmpty {
            ttsSynthesizer.stopSpeaking(at: .immediate)
            
            // Calculate where we are starting from
            let startIndex = self.speechProgress.location
            
            // FIX SYNC: Remember this starting point as our offset
            self.currentUtteranceOffset = startIndex
            
            let remainingText = (self.fullText as NSString).substring(from: startIndex)
            let utterance = AVSpeechUtterance(string: remainingText)
            utterance.rate = self.rate
            utterance.voice = selectedVoice
            
            ttsSynthesizer.speak(utterance)
        }
    }
    
    func pause() {
        ttsSynthesizer.pauseSpeaking(at: .word)
    }
    
    func stop() {
        ttsSynthesizer.stopSpeaking(at: .immediate)
    }
    
    // --- DELEGATE METHODS ---
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        // FIX SYNC: Add the offset to the current range
        let globalLocation = range.location + currentUtteranceOffset
        let globalRange = NSRange(location: globalLocation, length: range.length)
        
        DispatchQueue.main.async {
            self.speechProgress = globalRange
            // FIX SCROLLING: Send update only to subscribers, don't trigger full objectWillChange
            self.speechProgressPublisher.send(globalRange)
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
            // REMOVED: self.speechProgress = NSRange(location: 0, length: 0)
            // REMOVED: self.currentUtteranceOffset = 0
            
            // We do NOT reset the offsets here.
            // If we are just changing voices, we need these values to persist.
            // If we are starting a new document, `speakFromBeginning` will reset them for us.
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
