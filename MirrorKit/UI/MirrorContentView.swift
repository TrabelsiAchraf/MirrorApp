import SwiftUI
import AVFoundation
import CoreMedia

/// Main view — device frame with video + floating toolbar on hover
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
            // Background gradient in expanded mode
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
                // Floating toolbar ABOVE the frame
                toolbarArea

                // Main content (device frame or status views)
                if isExpanded {
                    // Expanded mode: device frame centered, not stretched
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
        .onChange(of: deviceManager.state) { _, newState in
            // Reset capture flag and tear down the engine when leaving the
            // capturing state (e.g. iPhone unplugged), so reconnecting can
            // start a fresh capture session.
            if case .capturing = newState { return }
            isCapturing = false
            Task { await captureEngine.stopCapture() }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        }
    }

    /// Toolbar area — always takes the same height, content visible on hover
    private var toolbarArea: some View {
        Group {
            if let device = deviceManager.selectedDevice {
                let spec = DeviceFrameProvider.frameSpec(for: device.modelID)
                FloatingToolbar(
                    devices: deviceManager.devices,
                    selectedDevice: device,
                    modelName: spec.displayName,
                    onSelect: { deviceManager.selectDevice($0) },
                    onExpand: { toggleExpanded() }
                )
                .padding(.horizontal, 8)
                .opacity(isHovering ? 1 : 0)
            } else {
                // Placeholder when no device — same height
                Color.clear.frame(height: 44)
                    .opacity(0)
            }
        }
    }

    /// Main content depending on the current state
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

    /// Device frame containing the video stream
    private var captureView: some View {
        Group {
            if showDeviceFrame, let device = deviceManager.selectedDevice {
                let spec = DeviceFrameProvider.frameSpec(for: device.modelID)

                // The device frame contains the video inside
                DeviceFrameView(spec: spec) {
                    FrameRenderer(displayLayer: displayLayer)
                }
            } else {
                // Without frame: raw video with rounded corners
                FrameRenderer(displayLayer: displayLayer)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            }
        }
    }

    // MARK: - Other views

    private var detectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Connect an iPhone via USB")
                .font(.title3)
                .foregroundColor(.white)

            Text("Waiting for a device…")
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
                Label("Start Mirroring", systemImage: "play.fill")
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

            Text("Error")
                .font(.title2)
                .foregroundColor(.white)

            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                deviceManager.state = .detecting
                deviceManager.startDiscovery()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Expand / Collapse

    /// Toggles between normal and expanded mode (full screen with gradient)
    private func toggleExpanded() {
        guard let window = NSApp.keyWindow else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            if isExpanded {
                // Restore the previous size
                isExpanded = false
                if let saved = savedFrame {
                    window.setFrame(saved, display: true, animate: true)
                    window.aspectRatio = saved.size
                }
            } else {
                // Save the current size and expand to fill the screen
                savedFrame = window.frame
                isExpanded = true
                if let screen = window.screen ?? NSScreen.main {
                    window.aspectRatio = NSSize(width: 0, height: 0) // Unlock the aspect ratio
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
            deviceManager.state = .error("Device not found")
            return
        }

        Task {
            do {
                try await captureEngine.startCapture(device: avDevice) { [displayLayer] sampleBuffer in
                    // CMSampleBuffer is not Sendable on the macOS 14 SDK (it becomes
                    // Sendable on macOS 15). The buffer is consumed once on the main
                    // thread and never retained, so the unsafe transfer is sound.
                    nonisolated(unsafe) let buffer = sampleBuffer
                    DispatchQueue.main.async {
                        displayLayer.displaySampleBuffer(buffer)
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
