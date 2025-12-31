//
//  FileImport.swift
//  Logii
//
//  Created by Sabath Rodriguez on 11/8/25.
//

import SwiftUI
internal import UniformTypeIdentifiers
import PDFKit
import AVFoundation

struct FileImportView: View {
    
    // NEW: Tracks the page currently being read aloud
    @State private var speechStartPageIndex: Int = 0
    
    @State var selectedURL: URL?
    @State var showFilePicker = false
    @State private var currentPageIndex: Int
    @State var initialPageIndex: Int = 0
    
    @State var sliderValue: Double = 0.5
    
    @State private var showPlaybackControls = false
    
    @StateObject private var speechService = SpeechService()
    
    init(url: URL? = nil) {
        _selectedURL = State(initialValue: url)
        if let unwrappedURL = url {
            currentPageIndex = BookmarkManager.shared.loadBookmark(for: unwrappedURL)?.pageIndex ?? 0
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
    
    // --- NEW LOGIC: Extract just one page ---
    func extractText(from pageIndex: Int, documentURL: URL) -> String? {
        guard let document = PDFDocument(url: documentURL),
              let page = document.page(at: pageIndex) else { return nil }
        
        return page.string
    }
    
    // --- NEW LOGIC: Recursive Page Reading ---
    func startReadingPage(at index: Int) {
        guard let url = selectedURL,
              let document = PDFDocument(url: url),
              index < document.pageCount else {
            // Stop if we run out of pages
            return 
        }
        
        // 1. Sync State
        self.speechStartPageIndex = index
        self.currentPageIndex = index // Optional: Turn pages automatically visually
        
        // 2. Extract Text
        guard let text = extractText(from: index, documentURL: url) else {
            // If page is empty (e.g. image only), skip to next
            startReadingPage(at: index + 1)
            return
        }
        
        // 3. Setup Completion for NEXT page
        speechService.onDidFinishUtterance = {
            self.startReadingPage(at: index + 1)
        }
        
        // 4. Speak
        speechService.speakFromBeginning(text: text)
        
        // 5. Update Bookmark
        BookmarkManager.shared.saveBookmark(
             Bookmark(pageIndex: index, speechProgressLocation: 0),
             for: url
         )
    }
        
    var body: some View {
        ZStack(alignment: .topTrailing) {
            
            if let url = selectedURL {
                PDFKitView(url: url, currentPageIndex: $currentPageIndex, speechService: speechService, speechStartPageIndex: speechStartPageIndex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .all)
                    .onAppear {
                        _ = url.startAccessingSecurityScopedResource()
                        let pageToLoad = BookmarkManager.shared.loadBookmark(for: url)?.pageIndex ?? 0
                        self.initialPageIndex = pageToLoad
                        self.currentPageIndex = pageToLoad
                        setupAudioSession()
                    }
                    .onDisappear {
                        speechService.stop()
                        BookmarkManager.shared.saveBookmark(
                            Bookmark(pageIndex: currentPageIndex, speechProgressLocation: 0),
                            for: url
                        )
                        url.stopAccessingSecurityScopedResource()
                    }
            } else {
                Button("Add PDF") {
                    showFilePicker = true
                }
            }
            
            // Action Menu
            if let url = selectedURL {
                Menu {
                    Button {
                        BookmarkManager.shared.saveBookmark(
                            Bookmark(pageIndex: currentPageIndex, speechProgressLocation: 0),
                            for: url
                        )
                        initialPageIndex = currentPageIndex
                    } label: {
                        Label("Save Page", systemImage: "bookmark.fill")
                    }
                    Button {
                        showFilePicker = true
                        speechService.stop()
                    } label: {
                        Label("Choose Another", systemImage: "doc")
                    }
                    Button(role: .destructive) {
                        url.stopAccessingSecurityScopedResource()
                        selectedURL = nil
                        speechService.stop()
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    
                    // --- UPDATED BUTTONS ---
                    Button {
                        // Start reading from the very first page
                        startReadingPage(at: 0)
                    } label: {
                        Label("Read Current Doc", systemImage: "speaker")
                    }
                    
                    Button {
                        // Start reading from the current page
                        startReadingPage(at: currentPageIndex)
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
            
            // Voice Settings
            if let _ = selectedURL {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showPlaybackControls.toggle()
                        } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .shadow(radius: 6, x: 0, y: 3)
                                .padding(.bottom, 8)
                                .padding(.trailing, 8)
                        }
                        .popover(isPresented: $showPlaybackControls) {
                            PlaybackControlsView(
                                selectedVoice: $speechService.selectedVoice,
                                speed: $speechService.rate,
                                isPlaybackVisible: $showPlaybackControls,
                                voices: speechService.availableVoices,
                                isSpeaking: speechService.isSpeaking,
                                onPlay: { speechService.playOrResume() },
                                onPause: { speechService.pause() },
                                onStop: { speechService.stop() }
                            )
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf]
        ) { result in
            switch result {
            case .success(let url):
                _ = url.startAccessingSecurityScopedResource()
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