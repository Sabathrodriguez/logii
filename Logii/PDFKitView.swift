//
//  PDFKitView.swift
//  Logii
//
//  Created by Sabath  Rodriguez on 11/8/25.
//

import SwiftUI
import PDFKit

// 1. We create a struct that conforms to UIViewRepresentable
struct PDFKitView: UIViewRepresentable {
    
    // 2. This will be the URL of the PDF we want to show
    let url: URL
    /// A binding to report the current page index back to the parent SwiftUI view.
    @Binding var currentPageIndex: Int
    /// The page index to jump to when the view is first created.
    let initialPageIndex: Int?

    // 3. This function CREATES the UIKit view
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        
        // Load the document from the URL
        pdfView.document = PDFDocument(url: url)
        
        // Go to the initial page if it's set.
        // We do this here in makeUIView to ensure it happens only once on creation.
        if let pageIndex = initialPageIndex, let page = pdfView.document?.page(at: pageIndex) {
            // Dispatch this to the main queue asynchronously to give the PDFView
            // a moment to finish its layout and be ready for navigation.
            DispatchQueue.main.async {
                pdfView.go(to: page)
            }
        }
        
        pdfView.autoScales = true // Fit the PDF to the screen
        
        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handlePageChange),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        return pdfView
    }
    
    // 4. This function UPDATES the view if data changes
    func updateUIView(_ pdfView: PDFView, context: Context) {
        // We'll update the document if the URL changes
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
        }
        
        // --- THIS IS THE FIX ---
        // Check if the desired initial page has changed and we're not already on it.
        // This handles the case where the parent view reloads the bookmark and updates the state.
        if let pageIndex = initialPageIndex,
           let page = pdfView.document?.page(at: pageIndex),
           pdfView.currentPage != page {
            // Dispatch to give the view time to be ready for navigation.
            DispatchQueue.main.async {
                pdfView.go(to: page)
            }
        }
    }
    
    // 5. Coordinator to handle notifications
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: PDFKitView

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        @objc func handlePageChange(notification: Notification) {
            if let pdfView = notification.object as? PDFView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) {
                parent.currentPageIndex = pageIndex
            }
        }
    }
}
