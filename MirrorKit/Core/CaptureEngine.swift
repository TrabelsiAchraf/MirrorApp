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

    /// Observer for `AVCaptureSessionRuntimeError` on the active session.
    private var runtimeErrorObserver: NSObjectProtocol?
    /// Fires `.noFrames` if the first frame never arrives after `startRunning()`.
    private var firstFrameWatchdog: Task<Void, Never>?

    /// How long to wait for the first frame before declaring the stream dead.
    /// The iOS screen capture assistant gives up its handshake after ~3 s, and
    /// the resulting runtime error is not always delivered — so we keep our own
    /// timer as a safety net.
    static let firstFrameTimeout: TimeInterval = 10

    /// Detected video stream resolution
    private(set) var detectedResolution: CGSize?

    /// Optional recorder that receives every sample buffer when active.
    private let recorder = VideoRecorder()

    var videoRecorder: VideoRecorder { recorder }

    /// Whether capture is currently running
    var isRunning: Bool {
        session?.isRunning ?? false
    }

    // MARK: - Capture control

    /// Starts capture from an AVCaptureDevice (iPhone)
    /// - Parameters:
    ///   - device: The AVCaptureDevice representing the iPhone
    ///   - frameHandler: Callback called for every received frame (called on the capture queue)
    ///   - onResolutionChange: Called from the capture queue when the stream dimensions change
    ///   - onFailure: Called at most once, from an arbitrary queue, when the running
    ///     session fails (runtime error) or never delivers a frame. The caller is
    ///     expected to stop the capture and surface the failure.
    func startCapture(
        device: AVCaptureDevice,
        frameHandler: @escaping @Sendable (CMSampleBuffer) -> Void,
        onResolutionChange: (@Sendable (CGSize) -> Void)? = nil,
        onFailure: (@Sendable (CaptureFailure) -> Void)? = nil
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
        let lastResolution = AtomicSize()
        let capturedRecorder = recorder
        let receivedFirstFrame = AtomicFlag()
        let failureReported = AtomicFlag()
        let delegate = SampleBufferDelegate { [weak self] sampleBuffer in
            receivedFirstFrame.set()

            // Track resolution changes (first frame AND device rotations)
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let resolution = CGSize(width: width, height: height)
                if lastResolution.value != resolution {
                    lastResolution.value = resolution
                    Task { await self?.updateResolution(resolution) }
                    onResolutionChange?(resolution)
                }
            }

            // Forward to recorder only when actively recording (skip the
            // Task allocation entirely otherwise — saves ~60 wakes/sec).
            if capturedRecorder.isRecordingFlag.value {
                let wrapped = UnsafeSampleBuffer(sampleBuffer)
                Task { await capturedRecorder.append(wrapped) }
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

        // Runtime errors arrive asynchronously *after* startRunning() returns
        // successfully (e.g. '!dev' when the iPhone refuses the screen stream).
        // Without this observer the session silently stays "running" with no
        // frames and the user sees a black screen.
        if let onFailure {
            runtimeErrorObserver = NotificationCenter.default.addObserver(
                forName: .AVCaptureSessionRuntimeError,
                object: session,
                queue: nil
            ) { notification in
                let failure: CaptureFailure
                if let error = CaptureFailure.error(from: notification) {
                    failure = CaptureFailure.classify(error)
                    print("[MirrorKit] Capture runtime error: \(error)")
                } else {
                    failure = .other("Unknown capture session error")
                    print("[MirrorKit] Capture runtime error without details")
                }
                if failureReported.setIfClear() {
                    onFailure(failure)
                }
            }

            // Safety net: the runtime error is not always delivered, so also
            // fail if nothing shows up within the timeout.
            let timeout = Self.firstFrameTimeout
            firstFrameWatchdog = Task.detached(priority: .utility) {
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled, !receivedFirstFrame.isSet else { return }
                print("[MirrorKit] No frame received after \(Int(timeout))s")
                if failureReported.setIfClear() {
                    onFailure(.noFrames(timeout: timeout))
                }
            }
        }

        session.startRunning()
        self.session = session

        print("[MirrorKit] Capture started for \(device.localizedName)")
    }

    /// Stops the running capture
    func stopCapture() {
        firstFrameWatchdog?.cancel()
        firstFrameWatchdog = nil
        if let observer = runtimeErrorObserver {
            NotificationCenter.default.removeObserver(observer)
            runtimeErrorObserver = nil
        }
        session?.stopRunning()
        session = nil
        sampleBufferDelegate = nil
        detectedResolution = nil
        print("[MirrorKit] Capture stopped")
    }

    // MARK: - Internal

    private func updateResolution(_ resolution: CGSize) {
        if detectedResolution != resolution {
            detectedResolution = resolution
            print("[MirrorKit] Resolution changed: \(Int(resolution.width))×\(Int(resolution.height))")
        }
    }
}

// MARK: - UnsafeSampleBuffer

/// Sendable wrapper around CMSampleBuffer. CMSampleBuffer only becomes Sendable
/// on the macOS 15 SDK; on macOS 14 we ferry it across isolation boundaries by
/// hand. Safe because the buffer is consumed once and not mutated.
struct UnsafeSampleBuffer: @unchecked Sendable {
    let buffer: CMSampleBuffer
    init(_ buffer: CMSampleBuffer) { self.buffer = buffer }
}

// MARK: - AtomicSize

/// Thread-safe CGSize used to detect resolution changes on the capture queue.
private final class AtomicSize: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: CGSize = .zero

    var value: CGSize {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - AtomicFlag

/// Thread-safe one-way boolean flag shared between the capture queue, the
/// notification queue and the watchdog task.
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _isSet = false

    var isSet: Bool { lock.withLock { _isSet } }

    func set() { lock.withLock { _isSet = true } }

    /// Sets the flag and returns `true` only for the caller that flipped it —
    /// used to guarantee a failure is reported exactly once.
    func setIfClear() -> Bool {
        lock.withLock {
            if _isSet { return false }
            _isSet = true
            return true
        }
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
