import SwiftUI
import AVFoundation
import CoreMedia

/// Vue principale — affiche l'état de connexion ou le flux vidéo
struct MirrorContentView: View {
    let deviceManager: DeviceManager
    let captureEngine: CaptureEngine
    /// Callback quand la résolution du flux est détectée
    var onResolutionDetected: ((NSSize) -> Void)?

    @State private var displayLayer = VideoDisplayLayer()
    @State private var isCapturing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black

            switch deviceManager.state {
            case .idle, .detecting:
                detectingView

            case .connected(let device):
                connectedView(device: device)

            case .capturing:
                FrameRenderer(displayLayer: displayLayer)

            case .error(let message):
                errorView(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sous-vues

    /// Vue affichée pendant la détection
    private var detectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Connectez un iPhone en USB")
                .font(.title3)
                .foregroundColor(.white)

            Text("En attente d'un appareil...")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    /// Vue affichée quand un appareil est connecté
    private func connectedView(device: ConnectedDevice) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone")
                .font(.system(size: 48))
                .foregroundColor(.white)

            Text(device.name)
                .font(.title2)
                .foregroundColor(.white)

            Button(action: {
                startCapture(deviceID: device.id)
            }) {
                Label("Démarrer le mirroring", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .onAppear {
            // Auto-démarrage de la capture
            startCapture(deviceID: device.id)
        }
    }

    /// Vue affichée en cas d'erreur
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Erreur")
                .font(.title2)
                .foregroundColor(.white)

            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Réessayer") {
                deviceManager.state = .detecting
                deviceManager.startDiscovery()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Capture

    /// Démarre la capture vidéo pour l'appareil sélectionné
    private func startCapture(deviceID: String) {
        guard !isCapturing else { return }

        // Retrouver l'AVCaptureDevice correspondant
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )
        guard let avDevice = discovery.devices.first(where: { $0.uniqueID == deviceID }) else {
            deviceManager.state = .error("Appareil introuvable")
            return
        }

        Task {
            do {
                try await captureEngine.startCapture(device: avDevice) { [displayLayer] sampleBuffer in
                    // Afficher la frame sur le main thread
                    DispatchQueue.main.async {
                        displayLayer.displaySampleBuffer(sampleBuffer)
                    }
                }

                // Notifier la résolution détectée
                if let resolution = await captureEngine.detectedResolution {
                    await MainActor.run {
                        onResolutionDetected?(NSSize(width: resolution.width, height: resolution.height))
                    }
                }

                await MainActor.run {
                    isCapturing = true
                    deviceManager.state = .capturing
                }
            } catch {
                await MainActor.run {
                    deviceManager.state = .error(error.localizedDescription)
                }
            }
        }
    }
}
