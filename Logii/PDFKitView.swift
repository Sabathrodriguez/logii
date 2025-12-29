import SwiftUI
import Combine
import PDFKit

struct PDFKitView: UIViewRepresentable {
    
    let url: URL
    @Binding var currentPageIndex: Int
    
    var speechService: SpeechService
    var speechStartPageIndex: Int
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: url)
        
        // Handle Initial Page Load
        if let page = pdfView.document?.page(at: currentPageIndex) {
            DispatchQueue.main.async {
                pdfView.go(to: page)
            }
        }
        
        context.coordinator.pdfView = pdfView
        
        // Pre-calculate page lengths for stable highlighting
        context.coordinator.buildPageCache(for: pdfView.document, startPage: speechStartPageIndex)
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handlePageChange),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.parent = self
        
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
            // Re-build cache if doc changes
            context.coordinator.buildPageCache(for: pdfView.document, startPage: speechStartPageIndex)
        }
        
        // If the START page changes (e.g. user clicked "Read Current Doc" vs "Read Page"), rebuild cache
        if context.coordinator.lastStartPage != speechStartPageIndex {
            context.coordinator.buildPageCache(for: pdfView.document, startPage: speechStartPageIndex)
        }
        
        if let document = pdfView.document,
           currentPageIndex < document.pageCount,
           let page = document.page(at: currentPageIndex),
           pdfView.currentPage != page {
             
            DispatchQueue.main.async {
                pdfView.go(to: page)
            }
        }
    }
    
     func makeCoordinator() -> Coordinator {
         Coordinator(parent: self, speechService: speechService)
     }
    
     class Coordinator: NSObject {
         var parent: PDFKitView
         weak var pdfView: PDFView?
         private var cancellables = Set<AnyCancellable>()
         
         // CACHE: Stores (PageIndex: StartIndexInSpeechString)
         // This ensures we don't recalculate page.string continuously
         var pageStartIndices: [Int: Int] = [:]
         var pageLengths: [Int: Int] = [:]
         var lastStartPage: Int = -1

         init(parent: PDFKitView, speechService: SpeechService) {
             self.parent = parent
             super.init()
            
             speechService.speechProgressPublisher
                 .receive(on: DispatchQueue.main)
                 .sink { [weak self] range in
                     self?.highlightSpokenWord(range: range)
                 }
                 .store(in: &cancellables)
             
             speechService.$isSpeaking
                 .receive(on: DispatchQueue.main)
                 .sink { [weak self] isSpeaking in
                     self?.ensureInteractionEnabled()
                     if !isSpeaking {
                         self?.pdfView?.clearSelection()
                     }
                 }
                 .store(in: &cancellables)
         }
         
         // In PDFKitView.swift -> Coordinator class

         func buildPageCache(for document: PDFDocument?, startPage: Int) {
             guard let document = document else { return }
             
             print("Building Page Cache starting at: \(startPage)")
             self.lastStartPage = startPage
             self.pageStartIndices.removeAll()
             self.pageLengths.removeAll()
             
             var currentAccumulatedLength = 0
             
             for i in startPage..<document.pageCount {
                 guard let page = document.page(at: i) else { continue }
                 
                 // 1. FIX: Skip pages with nil text, exactly like extractAttributedText does.
                 // If we don't skip, we add a "phantom space" to the math that doesn't exist in the speech.
                 guard let pageText = page.string else { continue }
                 
                 // Record start index
                 pageStartIndices[i] = currentAccumulatedLength
                 
                 // 2. FIX: Use .utf16.count
                 // AVSpeechSynthesizer works on NSString (UTF-16) lengths.
                 // Swift's standard .count handles Emojis differently, causing drift.
                 let length = pageText.utf16.count + 1 // +1 for the space we added
                 
                 pageLengths[i] = length
                 currentAccumulatedLength += length
             }
         }

         // MARK: - Highlight Logic
         func highlightSpokenWord(range: NSRange) {
             guard let pdfView = pdfView, let document = pdfView.document else { return }
             
             if range.length == 0 {
                 pdfView.clearSelection()
                 return
             }
             
             // Find which page this range belongs to.
             // Since we cached the start indices, we can just look it up.
             // We iterate through our cached pages to find the fit.
             
             let startPage = parent.speechStartPageIndex
             
             for i in startPage..<document.pageCount {
                 guard let pageStart = pageStartIndices[i],
                       let pageLength = pageLengths[i] else { continue }
                 
                 let pageEnd = pageStart + pageLength
                 
                 // Check if the current spoken index falls inside this page
                 if range.location >= pageStart && range.location < pageEnd {
                     
                     // We found the page!
                     guard let page = document.page(at: i) else { return }
                     
                     // Map Global Index -> Page Index
                     let localStart = range.location - pageStart
                     
                     // Ensure we don't crash if localStart is out of bounds (safety)
                     if localStart < 0 { return }
                     
                     // Create selection
                     let localRange = NSRange(location: localStart, length: range.length)
                     
                     // Select
                     if let selection = page.selection(for: localRange) {
                         pdfView.setCurrentSelection(selection, animate: true)
                     }
                     
                     break // Stop looking
                 }
             }
         }

         @objc func handlePageChange(notification: Notification) {
             if let pdfView = notification.object as? PDFView,
                let currentPage = pdfView.currentPage,
                let pageIndex = pdfView.document?.index(for: currentPage) {
                 parent.currentPageIndex = pageIndex
             }
         }
        
         func ensureInteractionEnabled() {
             guard let pdfView = pdfView else { return }
             if !pdfView.isUserInteractionEnabled {
                 pdfView.isUserInteractionEnabled = true
             }
         }
     }
}
