//
//  PDFThumbnailView.swift
//  Logii
//
//  Created by Sabath  Rodriguez on 11/11/25.
//

import SwiftUI
import PDFKit

struct PDFThumbnailView: View {
    let url: URL
    
    // We'll generate the thumbnail and store it in state
    @State private var thumbnailImage: Image?
    
    var body: some View {
        VStack(alignment: .leading) {
            
            // 1. The Thumbnail Image
            ZStack {
                if let thumbnailImage {
                    thumbnailImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                    
                } else {
                    // Placeholder while loading
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .aspectRatio(2/3, contentMode: .fit) // Common book aspect ratio
                        .overlay(ProgressView())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            
            // 2. The Title (from the file name)
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .padding(.horizontal, 4)
            
            // 3. The Progress (like "43%" in your screenshot)
            // You could add this later by storing progress
            Text("NEW") // Example of a badge
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
        }
        .onAppear(perform: generateThumbnail)
    }
    
    // --- Thumbnail Generation ---
    
    private func generateThumbnail() {
        // Run this in the background
        DispatchQueue.global(qos: .userInitiated).async {
            
            // A. Open the PDF document
            guard let document = PDFDocument(url: url),
                  // B. Get the first page
                  let page = document.page(at: 0) else {
                return
            }
            
            // C. Define a size for the thumbnail
            let thumbnailSize = CGSize(width: 300, height: 450)
            
            // D. Generate the UIImage (this is a UIKit class)
            let uiImage = page.thumbnail(of: thumbnailSize, for: .cropBox)
            
            // E. Switch back to the main thread to update the UI
            DispatchQueue.main.async {
                // Convert the UIImage to a SwiftUI Image
                self.thumbnailImage = Image(uiImage: uiImage)
            }
        }
    }
}
