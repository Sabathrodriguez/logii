//
//  LibraryView.swift
//  Logii
//
//  Created by Sabath  Rodriguez on 11/11/25.
//
import SwiftUI
import PDFKit
internal import UniformTypeIdentifiers

struct LibraryView: View {
    // You would load these URLs from your app's storage
    @State var pdfURLs: [URL] = [/* ... your array of PDF URLs ... */]
    @State var showFilePicker: Bool = false
    @State var selectedURL: URL?
    
    // Define the grid columns
    let columns = [
        GridItem(.adaptive(minimum: 150))
    ]
    
    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(pdfURLs, id: \.self) { url in
                            NavigationLink(destination: FileImportView(url: url)) {
                                PDFThumbnailView(url: url)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    
                    Button("Import To Library") {
                        showFilePicker = true
                    }
                }
            }
        }
        .navigationTitle("Library") // Similar to the screenshot
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf]
        ) { result in
            // 3. When the user picks a file, save its URL
            switch result {
            case .success(let url):
                // We no longer need to start access here. We'll do it in the FileImportView
                // just before we need to display the file.
                
                // if all checks passed, add url to pdfURL's array
                pdfURLs.append(url)
                
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}
#Preview {
    LibraryView()
}
