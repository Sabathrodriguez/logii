//
//  FileImport.swift
//  Logii
//
//  Created by Sabath  Rodriguez on 11/8/25.
//

import SwiftUI
internal import UniformTypeIdentifiers
import PDFKit
import AVFoundation

struct FileImportView: View {
    
    @State var selectedURL: URL?
    @State var showFilePicker = false
    @State private var currentPageIndex: Int = 0
    @State var initialPageIndex: Int = 0
    
    @State var sliderValue: Double = 0.5
    
    @State private var showPlaybackControls = false
    
    @StateObject private var speechService = SpeechService()
    
    init(url: URL? = nil) {
        // This line takes the 'url' we pass in
        // and uses it to set the initial value of the '@State var selectedURL'
        _selectedURL = State(initialValue: url)
    }
    
    func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    func extractAttributedText(from url: URL, startingAt pageIndex: Int = 0) -> NSAttributedString? {
        guard let document = PDFDocument(url: url) else { return nil }
        let result = NSMutableAttributedString()
        for i in pageIndex..<document.pageCount {
            guard let page = document.page(at: i), // Start from the given page index
                  let selection = page.string else { continue }
            result.append(selection.isEmpty ? NSAttributedString(string: "") : NSAttributedString(string: selection))
            result.append(NSAttributedString(string: "\n"))
        }
        return result
    }
        
    var body: some View {
        ZStack(alignment: .topTrailing) {
            
            // 1
            // PDF view
            // 1. If we have a URL, show the PDF.
            if let url = selectedURL {
                PDFKitView(url: url, currentPageIndex: $currentPageIndex, initialPageIndex: initialPageIndex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .all)
                    .onAppear {
                        // Load the most recent bookmark every time the view appears.
                        let pageToLoad = BookmarkManager.shared.loadBookmark(for: url)?.pageIndex ?? 0
                        self.initialPageIndex = pageToLoad
                        self.currentPageIndex = pageToLoad
                        print("View appeared. Loaded bookmark for page index: \(pageToLoad)")
                        setupAudioSession()
                    }
                    .onDisappear {
                        // Stop speech and save progress when the view disappears.
                        speechService.stop()
                        print("Saving bookmark at page index: \(currentPageIndex)")
                        BookmarkManager.shared.saveBookmark(
                            Bookmark(pageIndex: currentPageIndex, speechProgressLocation: 0),
                            for: url
                        )
                    }
            // 2. If not, show a button to pick one.
            } else {
                Button("Add PDF") {
                    showFilePicker = true
                }
            }
            
            // 2
            // Floating circular action button (top-right)
            if let url = selectedURL {
                Menu {
                    Button {
                        // --- EXPLICIT SAVE BUTTON ---
                        print("Saving bookmark at page index: \(currentPageIndex)")
                        BookmarkManager.shared.saveBookmark(
                            Bookmark(pageIndex: currentPageIndex, speechProgressLocation: 0),
                            for: url
                        )
                    } label: {
                        Label("Save Page", systemImage: "bookmark.fill")
                    }
                    Button {
                        // Keep current access (so PDF stays readable) and open picker
                        showFilePicker = true
                        speechService.stop()
                        
                    } label: {
                        Label("Choose Another", systemImage: "doc")
                    }
                    Button(role: .destructive) {
                        // Stop access and clear selection
                        selectedURL = nil
                        speechService.stop()
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    Button {                                                   
                        let s: String = extractAttributedText(from: url)?.string ?? "N/A"
                        
                        speechService.speakFromBeginning(text: s, rate: Float(sliderValue))                        
                        
                        print("s: \(s)")
                    } label: {
                        Label("Read Current Doc", systemImage: "speaker")
                    }
                    Button {
                        // Extract text starting from the current page
                        let textFromPage = extractAttributedText(from: url, startingAt: currentPageIndex)?.string ?? "N/A"
                        speechService.speakFromBeginning(text: textFromPage, rate: Float(sliderValue))

                        // --- THIS IS THE FIX ---
                        // Sync the initialPageIndex with the current page so the view doesn't jump back.
                        self.initialPageIndex = currentPageIndex
                        BookmarkManager.shared.saveBookmark(
                            Bookmark(pageIndex: currentPageIndex, speechProgressLocation: 0),
                            for: url
                        )
                        
                        print("Reading from page \(currentPageIndex + 1)")
                    } label: {
                        Label("Read from This Page", systemImage: "text.book.closed")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(radius: 6, x: 0, y: 3)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                        .accessibilityLabel("PDF actions")
                }
            }
            
            // 3
            // voice settings menu (bottom-right)
            if let url = selectedURL {
                VStack {
                    Spacer() // Pushes the HStack to the bottom
                    HStack {
                        Spacer() // Pushes the Button to the right
                        
                        // --- THIS IS THE REPLACEMENT ---
                        
                        // 1. This is just a regular Button now
                        Button {
                            showPlaybackControls.toggle() // Action: Show the popover
                        } label: {
                            Image(systemName: "gear") // The label is the same as before
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .shadow(radius: 6, x: 0, y: 3)
                                .padding(.bottom, 8)
                                .padding(.trailing, 8)
                                .accessibilityLabel("More options")
                        }
                        // 2. Attach the popover modifier to the Button
                        .popover(isPresented: $showPlaybackControls) {
                            
                            // 3. This is the content for the popover
                            VStack(spacing: 15) {
                                // A horizontal layout for the buttons
                                HStack(spacing: 55) {
                                    Button {
                                        speechService.pause()
                                    } label: {
                                        Image(systemName: "pause.fill")
                                    }
                                    
                                    Button {
                                        speechService.playOrResume(rate: Float(sliderValue))
                                    } label: {
                                        Image(systemName: "play.fill")
                                    }
                                    
                                    Button(role: .destructive) {
                                        speechService.stop()
                                    } label: {
                                        Image(systemName: "stop.fill")
                                    }
                                }
                                .font(.title2) // Make the buttons a bit bigger
                                
                                // The slider
                                VStack {
                                    // I've added a specifier to format the number nicely
                                    Text("Voice Speed: \(sliderValue, specifier: "%.2f")")
                                        .font(.caption)
                                    Slider(value: $sliderValue, in: 0.0...1.0, step: 0.05) { isEditing in
                                        // This 'isEditing' boolean is the key.
                                        // We only want to act when the user lets go (isEditing == false)
                                        if !isEditing && speechService.isSpeaking {
                                                // ...resume speech from the last bookmark with the new rate.
                                                speechService.playOrResume(rate: Float(sliderValue))
                                            }
                                    }
                                }
                            }
                            .padding() // Adds nice spacing inside the popover
                            // This line helps it look like a popover on iPhone
                            .presentationCompactAdaptation(.popover)
                        }
                        // --- END OF REPLACEMENT ---
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf]
        ) { result in
            // 3. When the user picks a file, save its URL
            switch result {
            case .success(let url):
                
                // --- (THE "START") ---
                // "Use the key to unlock the door"
                // We must do this *before* we try to display the URL
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                
                if !didStartAccessing {
                    print("Failed to start security access for \(url.lastPathComponent)")
                    // Here you would show an error to the user
                }
                
                // If a previous URL was open, stop its access before replacing
                if let previousURL = self.selectedURL {
                    previousURL.stopAccessingSecurityScopedResource()
                }
                
                self.selectedURL = url
                
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}
 
#Preview {
    FileImportView()
}
