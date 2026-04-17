import AppKit

/// Saves snapshots and recordings to a user-selected folder (security-scoped bookmark).
enum ExportManager {

    enum ExportError: LocalizedError {
        case noSaveFolder

        var errorDescription: String? {
            "No save folder selected. Please choose a folder in Settings (⌘,)."
        }
    }

    /// Returns the user-selected save folder, prompting if none is set.
    @MainActor
    private static func resolveFolder() throws -> URL {
        if let url = SaveLocationManager.accessSaveFolder() {
            return url
        }
        // First time — prompt the user to pick a folder
        guard let url = SaveLocationManager.promptForFolder() else {
            throw ExportError.noSaveFolder
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw ExportError.noSaveFolder
        }
        return url
    }

    @MainActor
    private static func uniqueURL(extension ext: String, prefix: String) throws -> URL {
        let folder = try resolveFolder()
        defer { folder.stopAccessingSecurityScopedResource() }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())
        let url = folder.appendingPathComponent("\(prefix) \(stamp).\(ext)")
        return url
    }

    @MainActor
    @discardableResult
    static func savePNG(_ data: Data) throws -> URL {
        let folder = try resolveFolder()
        defer { folder.stopAccessingSecurityScopedResource() }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())
        let url = folder.appendingPathComponent("Snapshot \(stamp).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Folder currently held open for an active recording.
    @MainActor
    private static var activeRecordingFolder: URL?

    /// Returns the target URL for a new recording. The caller (AVAssetWriter)
    /// is responsible for writing to it. Call `endRecording()` when the
    /// recording finishes to release security-scoped access.
    @MainActor
    static func newRecordingURL() throws -> URL {
        let folder = try resolveFolder()
        activeRecordingFolder = folder
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())
        return folder.appendingPathComponent("Recording \(stamp).mov")
    }

    /// Releases security-scoped access held during a recording session.
    @MainActor
    static func endRecording() {
        activeRecordingFolder?.stopAccessingSecurityScopedResource()
        activeRecordingFolder = nil
    }

    /// Returns the current save folder URL (without starting scoped access).
    static var saveFolderURL: URL? {
        SaveLocationManager.resolveBookmark()
    }
}
