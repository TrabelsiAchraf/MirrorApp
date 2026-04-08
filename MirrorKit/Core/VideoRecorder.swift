import AVFoundation
import CoreMedia
import Foundation

/// Records incoming CMSampleBuffers to a .mov file via AVAssetWriter.
/// Video only (v1) — audio can be added later.
actor VideoRecorder {
    enum RecorderError: LocalizedError {
        case writerCreationFailed(Error)
        case notReady

        var errorDescription: String? {
            switch self {
            case .writerCreationFailed(let error):
                return "Failed to create asset writer: \(error.localizedDescription)"
            case .notReady:
                return "Recorder is not ready"
            }
        }
    }

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private(set) var outputURL: URL?

    var isRecording: Bool { writer != nil }

    /// Start a new recording at the given URL. The file will be overwritten.
    func start(to url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw RecorderError.writerCreationFailed(error)
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        if writer.canAdd(input) {
            writer.add(input)
        }

        writer.startWriting()
        self.writer = writer
        self.input = input
        self.sessionStarted = false
        self.outputURL = url
    }

    /// Append a sample buffer. Safe to call when not recording — it becomes a no-op.
    func append(_ wrapped: UnsafeSampleBuffer) {
        guard let writer, let input else { return }
        let sampleBuffer = wrapped.buffer

        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    /// Finalize the recording and return the file URL.
    @discardableResult
    func stop() async -> URL? {
        guard let writer, let input else { return nil }
        input.markAsFinished()
        await writer.finishWriting()
        let url = outputURL
        self.writer = nil
        self.input = nil
        self.sessionStarted = false
        self.outputURL = nil
        return url
    }
}
