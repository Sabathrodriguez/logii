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
        }
        
        // If the view was told to turn the page (e.g. auto-read moved to next page)
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

         // MARK: - Highlight Logic
         func highlightSpokenWord(range: NSRange) {
             guard let pdfView = pdfView, let document = pdfView.document else { return }
             
             if range.length == 0 {
                 pdfView.clearSelection()
                 return
             }
             
             // SIMPLIFIED: We know exactly which page to highlight
             // because speechService is only reading one page at a time.
             let pageIndex = parent.speechStartPageIndex
             
             guard let page = document.page(at: pageIndex) else { return }
             
             // The range is now local to this page.
             // We assume AVSpeechSynthesizer range matches PDFKit text string range.
             if let selection = page.selection(for: range) {
                 pdfView.setCurrentSelection(selection, animate: true)
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
