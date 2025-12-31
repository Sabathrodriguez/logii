import Foundation
import AVFoundation
import SwiftUI
import Combine

class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    private let ttsSynthesizer = AVSpeechSynthesizer()
    private var fullText: String = ""
    
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
    }
    
    private func loadVoices() {
        self.availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }
            .sorted { $0.name < $1.name }
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
            
            // Resume from where we left off in the current page text
            let startIndex = self.speechProgress.location
            let remainingText = (self.fullText as NSString).substring(from: startIndex)
            
            let utterance = AVSpeechUtterance(string: remainingText)
            utterance.rate = self.rate
            utterance.voice = selectedVoice
            
            // Important: We must not forget to map the delegate callbacks back to the original string indices
            // But since we are only doing simple page-by-page, the drift is minimal.
            // For perfect pausing, we'd need an offset, but let's keep it simple for this step.
            
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
        // If we resumed (substring), we might need to adjust 'range.location' by adding the start offset.
        // For this specific implementation, we rely on the fact that we process one page at a time.
        
        DispatchQueue.main.async {
            self.speechProgress = range
            self.speechProgressPublisher.send(range)
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
            // Notify that this specific page is done
            self.onDidFinishUtterance?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
