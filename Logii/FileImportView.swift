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
    
//    @State var selectedURL: URL?
//    @State private var currentPageIndex: Int
    
    // NEW: Tracks where the current speech session started
    @State private var speechStartPageIndex: Int = 0
    
    @State var selectedURL: URL?
    @State var showFilePicker = false
    @State private var currentPageIndex: Int
    @State var initialPageIndex: Int = 0
    
    @State var sliderValue: Double = 0.5
    
    @State private var showPlaybackControls = false
    
    @StateObject private var speechService = SpeechService()
    
    init(url: URL? = nil) {
        // This line takes the 'url' we pass in
        // and uses it to set the initial value of the '@State var selectedURL'
        _selectedURL = State(initialValue: url)
        if let unwrappedURL = url {
            currentPageIndex = BookmarkManager.shared.loadBookmark(for: unwrappedURL)?.pageIndex ?? 0
            print("set page index from bookmark: \(currentPageIndex)")
        } else {
            currentPageIndex = 0
        }
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
            // MUST skip nil strings to match the cache logic above
            guard let page = document.page(at: i),
                  let selection = page.string else { continue }
            
            result.append(NSAttributedString(string: selection))
            result.append(NSAttributedString(string: " "))
        }
        return result
    }
        
    var body: some View {
        ZStack(alignment: .topTrailing) {
            
            // 1
            // PDF view
            // 1. If we have a URL, show the PDF.
            if let url = selectedURL {
                let _ = print("about to init pdfkitiew with current page index: \(currentPageIndex)")
//                print("current page index (FileImportView body) before PDFKitView init: \(currentPageIndex)")
                PDFKitView(url: url, currentPageIndex: $currentPageIndex, speechService: speechService, speechStartPageIndex: speechStartPageIndex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .all)
                    .onAppear {
                        // --- THIS IS THE FIX ---
                        // Re-gain access every time the view appears. This is crucial for when
                        // you navigate back from the library and the previous access was stopped.
                        _ = url.startAccessingSecurityScopedResource()
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
                        url.stopAccessingSecurityScopedResource()
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
                        initialPageIndex = currentPageIndex
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
                        url.stopAccessingSecurityScopedResource()
                        selectedURL = nil
                        speechService.stop()
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    Button {
                        let textFromPage: String = extractAttributedText(from: url)?.string ?? "N/A"
                        
                        // NEW: Reset start index to 0 for full document read
                        self.speechStartPageIndex = 0
                        
                        speechService.speakFromBeginning(text: textFromPage)
                    } label: {
                        Label("Read Current Doc", systemImage: "speaker")
                    }
                    
                    Button {
                        let textFromPage = extractAttributedText(from: url, startingAt: currentPageIndex)?.string ?? "N/A"
                        speechService.speakFromBeginning(text: textFromPage)
                        
                        // NEW: Sync start index with current page
                        self.speechStartPageIndex = currentPageIndex
                        
                        // Sync bookmark logic (existing)
                        BookmarkManager.shared.saveBookmark(
                            Bookmark(pageIndex: currentPageIndex, speechProgressLocation: 0),
                            for: url
                        )
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
                            PlaybackControlsView(
                                selectedVoice: $speechService.selectedVoice,
                                
                                // Bind directly to speechService.rate
                                speed: $speechService.rate,
                                
                                isPlaybackVisible: $showPlaybackControls,
                                voices: speechService.availableVoices,
                                isSpeaking: speechService.isSpeaking,
                                onPlay: {
                                    // No arguments needed anymore
                                    speechService.playOrResume()
                                },
                                onPause: {
                                    speechService.pause()
                                },
                                onStop: {
                                    speechService.stop()
                                }
                            )
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
