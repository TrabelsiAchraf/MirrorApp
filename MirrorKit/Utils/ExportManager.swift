import Foundation

/// Saves snapshots and recordings to `~/Downloads/MirrorKit/`.
enum ExportManager {
    /// Resolves (and creates if needed) the MirrorKit folder inside `~/Downloads`.
    static func ensureOutputDirectory() throws -> URL {
        let fm = FileManager.default
        let downloads = try fm.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = downloads.appendingPathComponent("MirrorKit", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Returns a unique URL inside the MirrorKit folder for the given extension.
    static func uniqueOutputURL(extension ext: String, prefix: String) throws -> URL {
        let folder = try ensureOutputDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: Date())
        return folder.appendingPathComponent("\(prefix)_\(stamp).\(ext)")
    }

    @discardableResult
    static func savePNG(_ data: Data) throws -> URL {
        let url = try uniqueOutputURL(extension: "png", prefix: "Snapshot")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Returns the target URL for a new recording. The caller (AVAssetWriter)
    /// is responsible for writing to it.
    static func newRecordingURL() throws -> URL {
        try uniqueOutputURL(extension: "mov", prefix: "Recording")
    }
}
