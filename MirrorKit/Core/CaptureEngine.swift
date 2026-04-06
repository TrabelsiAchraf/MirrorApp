import AVFoundation
import CoreMedia

/// Erreurs possibles du moteur de capture
enum CaptureError: LocalizedError {
    case inputCreationFailed(Error)
    case inputNotSupported
    case outputNotSupported
    case sessionConfigurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .inputCreationFailed(let error):
            return "Impossible de créer l'entrée de capture : \(error.localizedDescription)"
        case .inputNotSupported:
            return "L'entrée de capture n'est pas supportée par la session"
        case .outputNotSupported:
            return "La sortie vidéo n'est pas supportée par la session"
        case .sessionConfigurationFailed(let reason):
            return "Échec de la configuration de la session : \(reason)"
        }
    }
}

/// Moteur de capture vidéo — gère le pipeline AVCaptureSession
/// Utilise un Actor pour garantir la thread-safety
actor CaptureEngine {
    private var session: AVCaptureSession?
    private let captureQueue = DispatchQueue(
        label: "com.mirrorkit.capture",
        qos: .userInteractive
    )
    private var sampleBufferDelegate: SampleBufferDelegate?

    /// Résolution du flux vidéo détectée
    private(set) var detectedResolution: CGSize?

    /// Indique si la capture est en cours
    var isRunning: Bool {
        session?.isRunning ?? false
    }

    // MARK: - Contrôle de la capture

    /// Démarre la capture depuis un AVCaptureDevice (iPhone)
    /// - Parameters:
    ///   - device: L'AVCaptureDevice représentant l'iPhone
    ///   - frameHandler: Callback appelé à chaque frame reçue (appelé sur la capture queue)
    func startCapture(
        device: AVCaptureDevice,
        frameHandler: @escaping @Sendable (CMSampleBuffer) -> Void
    ) throws {
        // Arrêter toute session existante
        stopCapture()

        let session = AVCaptureSession()
        session.sessionPreset = .high

        // Configurer l'input
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

        // Configurer l'output vidéo
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true

        // Delegate pour recevoir les frames
        // Détection de la résolution + forwarding vers le handler
        let resolutionFlag = AtomicFlag()
        let delegate = SampleBufferDelegate { [weak self] sampleBuffer in
            // Détecter la résolution à partir de la première frame
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

        print("[MirrorKit] Capture démarrée pour \(device.localizedName)")
    }

    /// Arrête la capture en cours
    func stopCapture() {
        session?.stopRunning()
        session = nil
        sampleBufferDelegate = nil
        detectedResolution = nil
        print("[MirrorKit] Capture arrêtée")
    }

    // MARK: - Interne

    private func updateResolution(_ resolution: CGSize) {
        if detectedResolution == nil {
            detectedResolution = resolution
            print("[MirrorKit] Résolution détectée : \(Int(resolution.width))×\(Int(resolution.height))")
        }
    }
}

// MARK: - AtomicFlag

/// Flag thread-safe pour la détection unique de résolution
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - SampleBufferDelegate

/// Classe helper pour recevoir les CMSampleBuffer (un Actor ne peut pas être delegate directement)
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
        // Frame ignorée — comportement normal avec alwaysDiscardsLateVideoFrames
    }
}
