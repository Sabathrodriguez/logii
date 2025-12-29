//
//  PlaybackControlsView.swift
//  Logii
//
//  Created by Sabath  Rodriguez on 12/25/25.
//

import SwiftUI
import AVFoundation

struct PlaybackControlsView: View {
    @Binding var selectedVoice: AVSpeechSynthesisVoice?
    
    // CHANGED: Double -> Float to match SpeechService
    @Binding var speed: Float
    @Binding var isPlaybackVisible: Bool
    
    let voices: [AVSpeechSynthesisVoice]
    let isSpeaking: Bool
    
    // CHANGED: No parameters needed now
    var onPlay: () -> Void
    var onPause: () -> Void
    var onStop: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            
            HStack(spacing: 55) {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                }
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                }
                Button(role: .destructive, action: onStop) {
                    Image(systemName: "stop.fill")
                }
            }
            .font(.title2)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 5) {
                Text("Voice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                
                Picker("Select Voice", selection: $selectedVoice) {
                    ForEach(voices, id: \.identifier) { voice in
                        let quality = voice.quality == .premium ? " (Premium)" : ""
//                        let _ = if voice.name == "Samantha" {print(voice.name)} else {print("NA")}
                        let voiceString = voice.name == "Samantha" ? "\(voice.name)\(quality) (Default)" : "\(voice.name)\(quality)"
                        Text(voiceString).tag(Optional(voice))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
            }
            
            VStack {
                Text("Voice Speed: \(speed, specifier: "%.2f")")
                    .font(.caption)
                // Slider works best with Float when specified explicitly
                Slider(value: $speed, in: 0.0...1.0, step: 0.05) { isEditing in
                    if !isEditing && isSpeaking {
                        onPlay()
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 280)
        .presentationCompactAdaptation(.popover)
    }
}
