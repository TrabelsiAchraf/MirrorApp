import AVFoundation
import CoreMedia

/// Possible errors raised by the capture engine
enum CaptureError: LocalizedError {
    case inputCreationFailed(Error)
    case inputNotSupported
    case outputNotSupported
    case sessionConfigurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .inputCreationFailed(let error):
            return "Failed to create capture input: \(error.localizedDescription)"
        case .inputNotSupported:
            return "Capture input is not supported by the session"
        case .outputNotSupported:
            return "Video output is not supported by the session"
        case .sessionConfigurationFailed(let reason):
            return "Failed to configure capture session: \(reason)"
        }
    }
}

/// Video capture engine — manages the AVCaptureSession pipeline
/// Uses an Actor to guarantee thread safety
actor CaptureEngine {
    private var session: AVCaptureSession?
    private let captureQueue = DispatchQueue(
        label: "com.mirrorkit.capture",
        qos: .userInteractive
    )
    private var sampleBufferDelegate: SampleBufferDelegate?

    /// Detected video stream resolution
    private(set) var detectedResolution: CGSize?

    /// Whether capture is currently running
    var isRunning: Bool {
        session?.isRunning ?? false
    }

    // MARK: - Capture control

    /// Starts capture from an AVCaptureDevice (iPhone)
    /// - Parameters:
    ///   - device: The AVCaptureDevice representing the iPhone
    ///   - frameHandler: Callback called for every received frame (called on the capture queue)
    func startCapture(
        device: AVCaptureDevice,
        frameHandler: @escaping @Sendable (CMSampleBuffer) -> Void
    ) throws {
        // Stop any existing session
        stopCapture()

        let session = AVCaptureSession()
        session.sessionPreset = .high

        // Configure the input
        session.beginConfiguration()

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw CaptureError.inputCreationFailed(error)
        }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.inputNotSupported
        }
        session.addInput(input)

        // Configure the video output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true

        // Delegate that receives the frames
        // Resolution detection + forwarding to the handler
        let resolutionFlag = AtomicFlag()
        let delegate = SampleBufferDelegate { [weak self] sampleBuffer in
            // Detect the resolution from the first frame
            if !resolutionFlag.value,
               let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                resolutionFlag.value = true
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let resolution = CGSize(width: width, height: height)
                Task { await self?.updateResolution(resolution) }
            }

            frameHandler(sampleBuffer)
        }
        output.setSampleBufferDelegate(delegate, queue: captureQueue)
        self.sampleBufferDelegate = delegate

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureError.outputNotSupported
        }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()
        self.session = session

        print("[MirrorKit] Capture started for \(device.localizedName)")
    }

    /// Stops the running capture
    func stopCapture() {
        session?.stopRunning()
        session = nil
        sampleBufferDelegate = nil
        detectedResolution = nil
        print("[MirrorKit] Capture stopped")
    }

    // MARK: - Internal

    private func updateResolution(_ resolution: CGSize) {
        if detectedResolution == nil {
            detectedResolution = resolution
            print("[MirrorKit] Detected resolution: \(Int(resolution.width))×\(Int(resolution.height))")
        }
    }
}

// MARK: - AtomicFlag

/// Thread-safe flag used for one-shot resolution detection
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - SampleBufferDelegate

/// Helper class that receives CMSampleBuffers (an Actor cannot be a delegate directly)
private final class SampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let handler: @Sendable (CMSampleBuffer) -> Void

    init(handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        handler(sampleBuffer)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Frame dropped — normal behavior with alwaysDiscardsLateVideoFrames
    }
}
