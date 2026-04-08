import Foundation

/// Saves snapshots and recordings to `~/Downloads/MirrorKit/`.
enum ExportManager {
    private static func ensureFolder() throws -> URL {
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

    private static func uniqueURL(extension ext: String, prefix: String) throws -> URL {
        let folder = try ensureFolder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())
        return folder.appendingPathComponent("\(prefix) \(stamp).\(ext)")
    }

    @discardableResult
    static func savePNG(_ data: Data) throws -> URL {
        let url = try uniqueURL(extension: "png", prefix: "Snapshot")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Returns the target URL for a new recording. The caller (AVAssetWriter)
    /// is responsible for writing to it.
    static func newRecordingURL() throws -> URL {
        try uniqueURL(extension: "mov", prefix: "Recording")
    }
}
