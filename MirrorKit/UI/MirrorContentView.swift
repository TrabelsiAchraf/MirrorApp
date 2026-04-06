import SwiftUI
import AVFoundation
import CoreMedia

/// Vue principale — device frame avec vidéo + toolbar flottante au hover
struct MirrorContentView: View {
    let deviceManager: DeviceManager
    let captureEngine: CaptureEngine
    var onResolutionDetected: ((NSSize) -> Void)?

    @State private var displayLayer = VideoDisplayLayer()
    @State private var isCapturing = false
    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var savedFrame: NSRect?
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    @AppStorage("showDeviceFrame") private var showDeviceFrame = true

    var body: some View {
        ZStack {
            // Gradient arrière-plan en mode étendu
            if isExpanded {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.11, blue: 0.25),
                        Color(red: 0.08, green: 0.08, blue: 0.18),
                        Color(red: 0.05, green: 0.05, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            VStack(spacing: 4) {
                // Toolbar flottante AU-DESSUS du frame
                toolbarArea

                // Contenu principal (device frame ou états)
                if isExpanded {
                    // Mode étendu : device frame centré, pas étiré
                    mainContent
                        .aspectRatio(9.0 / 19.5, contentMode: .fit)
                        .padding(40)
                } else {
                    mainContent
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        }
    }

    /// Zone de la toolbar — prend toujours la même hauteur, contenu visible au hover
    private var toolbarArea: some View {
        Group {
            if let device = deviceManager.selectedDevice {
                let spec = DeviceFrameProvider.frameSpec(for: device.modelID)
                FloatingToolbar(
                    deviceName: device.name,
                    modelName: spec.displayName,
                    onExpand: { toggleExpanded() }
                )
                .padding(.horizontal, 8)
                .opacity(isHovering ? 1 : 0)
            } else {
                // Placeholder quand pas de device — même hauteur
                Color.clear.frame(height: 44)
                    .opacity(0)
            }
        }
    }

    /// Contenu principal selon l'état
    private var mainContent: some View {
        Group {
            switch deviceManager.state {
            case .idle, .detecting:
                detectingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))

            case .connected(let device):
                connectedView(device: device)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))

            case .capturing:
                captureView

            case .error(let message):
                errorView(message: message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            }
        }
    }

    // MARK: - Capture view

    /// Device frame contenant le flux vidéo
    private var captureView: some View {
        Group {
            if showDeviceFrame, let device = deviceManager.selectedDevice {
                let spec = DeviceFrameProvider.frameSpec(for: device.modelID)

                // Le device frame contient la vidéo à l'intérieur
                DeviceFrameView(spec: spec) {
                    FrameRenderer(displayLayer: displayLayer)
                }
            } else {
                // Sans frame : vidéo brute avec coins arrondis
                FrameRenderer(displayLayer: displayLayer)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            }
        }
    }

    // MARK: - Autres vues

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
            startCapture(deviceID: device.id)
        }
    }

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

    // MARK: - Expand / Collapse

    /// Bascule entre mode normal et mode étendu (plein écran avec gradient)
    private func toggleExpanded() {
        guard let window = NSApp.keyWindow else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            if isExpanded {
                // Revenir à la taille normale
                isExpanded = false
                if let saved = savedFrame {
                    window.setFrame(saved, display: true, animate: true)
                    window.aspectRatio = saved.size
                }
            } else {
                // Sauvegarder la taille actuelle et agrandir à l'écran
                savedFrame = window.frame
                isExpanded = true
                if let screen = window.screen ?? NSScreen.main {
                    window.aspectRatio = NSSize(width: 0, height: 0) // Débloquer le ratio
                    window.setFrame(screen.visibleFrame, display: true, animate: true)
                }
            }
        }
    }

    // MARK: - Capture

    private func startCapture(deviceID: String) {
        guard !isCapturing else { return }

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
                    DispatchQueue.main.async {
                        displayLayer.displaySampleBuffer(sampleBuffer)
                    }
                }

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
