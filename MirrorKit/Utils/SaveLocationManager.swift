import AppKit

/// Manages a user-selected save folder using security-scoped bookmarks.
enum SaveLocationManager {
    private static let bookmarkKey = "saveLocationBookmark"

    /// Returns the bookmarked save folder, or `nil` if none is set.
    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Re-save the bookmark to refresh it
            saveBookmark(for: url)
        }
        return url
    }

    /// Saves a security-scoped bookmark for the given folder URL.
    @discardableResult
    static func saveBookmark(for url: URL) -> Bool {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return false }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        return true
    }

    /// Returns the bookmarked folder, starting security-scoped access.
    /// The caller must call `url.stopAccessingSecurityScopedResource()` when done.
    static func accessSaveFolder() -> URL? {
        guard let url = resolveBookmark() else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    /// Presents an NSOpenPanel for the user to pick a save folder.
    /// Returns the chosen URL (already bookmarked) or `nil` if cancelled.
    @MainActor
    static func promptForFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder where MirrorKit will save snapshots and recordings."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        saveBookmark(for: url)
        return url
    }
}
