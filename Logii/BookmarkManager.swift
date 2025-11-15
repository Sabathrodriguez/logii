//
//  BookmarkManager.swift
//  Logii
//
//  Created by Sabath  Rodriguez on 11/12/25.
//

import Foundation

/// A data structure to hold bookmark information for a PDF.
/// It conforms to `Codable` so it can be easily encoded to and decoded from `Data`.
struct Bookmark: Codable {
    /// The zero-based index of the page the user was on.
    let pageIndex: Int
    /// The character location within the full text where speech was last stopped.
    let speechProgressLocation: Int
}

/// Manages saving and loading bookmarks using UserDefaults.
/// This class uses a Singleton pattern (`shared`) to ensure only one instance manages bookmarks throughout the app.
class BookmarkManager {
    
    /// The shared singleton instance of the bookmark manager.
    static let shared = BookmarkManager()
    
    private let userDefaults = UserDefaults.standard
    /// The key used to store the dictionary of all bookmarks in UserDefaults.
    private let bookmarksKey = "PDFBookmarks"

    /// The initializer is private to enforce the singleton pattern.
    private init() {}

    /// Saves a bookmark for a given PDF URL.
    /// - Parameters:
    ///   - bookmark: The `Bookmark` object to save.
    ///   - url: The URL of the PDF file, used as a unique key.
    func saveBookmark(_ bookmark: Bookmark, for url: URL) {
        // Use the URL's absolute string as a unique key for the bookmark.
        let key = url.absoluteString
        // Encode the Bookmark struct into Data.
        if let encodedData = try? JSONEncoder().encode(bookmark) {
            // Fetch the existing dictionary of bookmarks, or create a new one.
            var bookmarks = userDefaults.dictionary(forKey: bookmarksKey) ?? [:]
            // Store the encoded data in the dictionary with the URL string as the key.
            bookmarks[key] = encodedData
            // Save the updated dictionary back to UserDefaults.
            userDefaults.set(bookmarks, forKey: bookmarksKey)
        }
    }

    /// Loads a bookmark for a given PDF URL.
    /// - Parameter url: The URL of the PDF file to load a bookmark for.
    /// - Returns: An optional `Bookmark` object if one was found, otherwise `nil`.
    func loadBookmark(for url: URL) -> Bookmark? {
        let key = url.absoluteString
        guard let bookmarks = userDefaults.dictionary(forKey: bookmarksKey),
              let data = bookmarks[key] as? Data,
              // Decode the Data back into a Bookmark struct.
              let bookmark = try? JSONDecoder().decode(Bookmark.self, from: data) else {
            return nil
        }
        return bookmark
    }
}
