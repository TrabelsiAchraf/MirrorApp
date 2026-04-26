import SwiftUI
import AVFoundation
import CoreMedia

/// Main view — device frame with video + floating toolbar on hover
struct MirrorContentView: View {
    let deviceManager: DeviceManager
    let captureEngine: CaptureEngine
    var onResolutionDetected: ((NSSize) -> Void)?
    var onRotationChanged: ((Bool) -> Void)?

    @State private var displayLayer = VideoDisplayLayer()
    @State private var isCapturing = false
    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var savedFrame: NSRect?
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var annotationCanvas = AnnotationCanvas()

    @State private var isRecording = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var basePanOffset: CGSize = .zero
    @State private var rotationQuarterTurns: Int = 0  // 0 = portrait, 1 = landscape
    @State private var cachedPortraitSize: NSSize?
    @State private var detectedResolution: NSSize?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var detectingSeconds: Int = 0
    @State private var detectingTimer: Timer?

    @AppStorage("backgroundPreset") private var backgroundPresetRaw: String = "midnight"
    @AppStorage("backgroundCustomColor") private var backgroundCustomColorHex: String = "#1F1C40"
    @AppStorage("bezelStyle") private var bezelStyleRaw: String = "classic"
    @AppStorage("bezelColor") private var bezelColorRaw: String = "black"

    private var currentBackgroundPreset: BackgroundPreset {
        BackgroundPreset(rawValue: backgroundPresetRaw) ?? .midnight
    }

    private var currentBackgroundCustomColor: Color {
        Color(hex: backgroundCustomColorHex) ?? .black
    }

    private var currentBezelStyle: BezelStyle {
        BezelStyle(rawValue: bezelStyleRaw) ?? .classic
    }

    private var currentFrameColor: DeviceFrameSpec.FrameColor {
        DeviceFrameSpec.FrameColor(rawValue: bezelColorRaw) ?? .black
    }

    var body: some View {
        ZStack {
            // Background gradient in expanded mode
            if isExpanded {
                currentBackgroundPreset
                    .makeBackground(customColor: currentBackgroundCustomColor)
                    .ignoresSafeArea()
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

            // Annotation tools side panel — trailing edge, vertically centered.
            // Floats over the bezel since the window's aspect ratio is locked
            // and there's no room outside the device frame.
            if annotationCanvas.isAnnotationModeActive {
                HStack {
                    Spacer()
                    AnnotationToolbar(canvas: annotationCanvas)
                        .padding(.trailing, 12)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Toast overlay
            if let message = toastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                        )
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: annotationCanvas.isAnnotationModeActive)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onChange(of: deviceManager.state) { _, newState in
            // Reset capture flag and tear down the engine when leaving the
            // capturing state.
            if case .capturing = newState { return }
            isCapturing = false
            detectedResolution = nil
            cachedPortraitSize = nil
            Task { await captureEngine.stopCapture() }

            // Clear annotations when leaving an active session.
            switch newState {
            case .detecting, .error, .idle:
                annotationCanvas.clearAll()
                annotationCanvas.isAnnotationModeActive = false
            default:
                break
            }
        }
        .onChange(of: detectedResolution) { _, newResolution in
            guard let newResolution, let window = NSApp.keyWindow else { return }
            print("[MirrorKit] Applying new resolution to window: \(Int(newResolution.width))x\(Int(newResolution.height))")

            window.aspectRatio = newResolution

            // Target ~50% of the native resolution, clamped to 80% of screen.
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            var targetW = newResolution.width * 0.5
            var targetH = newResolution.height * 0.5
            let maxW = visible.width * 0.8
            let maxH = visible.height * 0.8
            if targetW > maxW || targetH > maxH {
                let ratio = min(maxW / targetW, maxH / targetH)
                targetW *= ratio
                targetH *= ratio
            }
            let current = window.frame
            let newFrame = NSRect(
                x: current.midX - targetW / 2,
                y: current.midY - targetH / 2,
                width: targetW,
                height: targetH
            )
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        }
        .onChange(of: deviceManager.selectedDevice?.id) { _, _ in
            // On device switch, stop the current capture so the new device
            // goes through a fresh startCapture → resolution detection → window resize.
            isCapturing = false
            detectedResolution = nil
            cachedPortraitSize = nil
            Task { await captureEngine.stopCapture() }

            // Clear annotations on device switch.
            annotationCanvas.clearAll()
            annotationCanvas.isAnnotationModeActive = false
        }
        .onAppear {
            MirrorActions.shared.toggleRecording = { toggleRecording() }
            MirrorActions.shared.takeSnapshot = { takeSnapshot() }
            MirrorActions.shared.toggleRotation = { toggleRotation() }
            MirrorActions.shared.rotateLeft = { rotateLeft() }
            MirrorActions.shared.rotateRight = { rotateRight() }
            MirrorActions.shared.resetZoom = { resetZoom() }
            MirrorActions.shared.toggleAnnotationMode = {
                annotationCanvas.isAnnotationModeActive.toggle()
            }
        }
        .onChange(of: annotationCanvas.isAnnotationModeActive) { _, active in
            // The borderless window normally drags from anywhere on its background,
            // which would steal the mouseDown from SwiftUI's DragGesture. Suspend
            // background-dragging while drawing so strokes are continuous.
            NSApp.windows.first(where: { $0 is BorderlessWindow })?.isMovableByWindowBackground = !active
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
                let spec = DeviceFrameProvider.frameSpec(for: device.modelID, resolution: detectedResolution)
                FloatingToolbar(
                    devices: deviceManager.devices,
                    selectedDevice: device,
                    modelName: spec.displayName,
                    isRecording: isRecording,
                    onSelect: { deviceManager.selectDevice($0) },
                    onExpand: { toggleExpanded() },
                    onToggleRecording: { toggleRecording() },
                    onSnapshot: { takeSnapshot() },
                    onToggleRotation: { toggleRotation() },
                    canvas: annotationCanvas
                )
                .padding(.horizontal, 8)
                .opacity(isHovering ? 1 : 0)
            } else {
                // Placeholder when no device — same height
                Color.clear.frame(height: 56)
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
                    .id(device.id)  // force a fresh onAppear on device switch

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
        GeometryReader { geo in
            let isLandscape = ((rotationQuarterTurns % 2) + 2) % 2 == 1
            // Pre-rotation size: swap so rotated content fills the container.
            let preSize: CGSize = isLandscape
                ? CGSize(width: geo.size.height, height: geo.size.width)
                : geo.size

            ZStack {
                Group {
                    if let device = deviceManager.selectedDevice {
                        let baseSpec = DeviceFrameProvider.frameSpec(for: device.modelID, resolution: detectedResolution)
                        let spec = baseSpec.with(frameColor: currentFrameColor)
                        DeviceFrameView(spec: spec, style: currentBezelStyle) {
                            FrameRenderer(displayLayer: displayLayer)
                        }
                    } else {
                        FrameRenderer(displayLayer: displayLayer)
                            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    }
                }

                // Always render the annotation layer so committed strokes stay
                // visible. Hit testing is gated so zoom/pan pass through when
                // annotation mode is off.
                AnnotationLayer(canvas: annotationCanvas)
                    .allowsHitTesting(annotationCanvas.isAnnotationModeActive)
            }
            .frame(width: preSize.width, height: preSize.height)
            .rotationEffect(.degrees(Double(rotationQuarterTurns) * 90))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .scaleEffect(zoomScale)
        .offset(panOffset)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    zoomScale = max(1.0, min(4.0, baseZoomScale * value))
                }
                .onEnded { _ in
                    baseZoomScale = zoomScale
                    if zoomScale <= 1.0 { panOffset = .zero; basePanOffset = .zero }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard zoomScale > 1.0 else { return }
                    panOffset = CGSize(
                        width: basePanOffset.width + value.translation.width,
                        height: basePanOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in basePanOffset = panOffset }
        )
    }

    // MARK: - Snapshot / Recording / Rotation / Zoom

    func takeSnapshot() {
        guard let pixelBuffer = displayLayer.lastPixelBuffer,
              let baseImage = SnapshotEncoder.makeNSImage(pixelBuffer: pixelBuffer) else {
            NSSound.beep()
            return
        }

        let composited = AnnotationCompositor.compositeSync(
            frame: baseImage,
            annotations: annotationCanvas.annotations,
            canvasSize: baseImage.size
        )

        guard let data = SnapshotEncoder.encodePNG(image: composited) else {
            NSSound.beep()
            return
        }

        do {
            let url = try ExportManager.savePNG(data)
            print("[MirrorKit] Snapshot saved: \(url.path)")
            NSSound(named: "Grab")?.play()
            showToast("Snapshot saved — \(url.lastPathComponent)", revealing: url)
        } catch {
            print("[MirrorKit] Snapshot failed: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    func toggleRecording() {
        if isRecording {
            Task {
                let url = await captureEngine.videoRecorder.stop()
                await MainActor.run {
                    ExportManager.endRecording()
                    isRecording = false
                    if let url {
                        print("[MirrorKit] Recording saved: \(url.path)")
                        NSSound(named: "Glass")?.play()
                        showToast("Recording saved — \(url.lastPathComponent)", revealing: url)
                    }
                }
            }
        } else {
            guard let resolution = displayLayer.lastPixelBuffer.map({
                CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0))
            }) else { NSSound.beep(); return }

            do {
                let url = try ExportManager.newRecordingURL()
                Task {
                    do {
                        try await captureEngine.videoRecorder.start(
                            to: url,
                            width: Int(resolution.width),
                            height: Int(resolution.height)
                        )
                        await MainActor.run {
                            isRecording = true
                            showToast("Recording…", revealing: nil)
                        }
                    } catch {
                        print("[MirrorKit] Recording start failed: \(error.localizedDescription)")
                        await MainActor.run { NSSound.beep() }
                    }
                }
            } catch {
                print("[MirrorKit] Could not create recording URL: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    func toggleRotation() { rotate(by: 1) }
    func rotateLeft() { rotate(by: -1) }
    func rotateRight() { rotate(by: 1) }

    private func rotate(by delta: Int) {
        // Keep the value unbounded so withAnimation takes the shortest path
        // (going from 0 to -90 rather than 0 to 270 when rotating left).
        let next = rotationQuarterTurns + delta
        let nextLandscape = ((next % 2) + 2) % 2 == 1
        let wasLandscape = ((rotationQuarterTurns % 2) + 2) % 2 == 1

        // Resize the window animated, but compute the target from a *cached*
        // portrait size so rapid left/right presses don't drift the dimensions.
        if nextLandscape != wasLandscape, let window = NSApp.keyWindow {
            // Capture the portrait reference the first time we know we are in portrait.
            if cachedPortraitSize == nil, !wasLandscape {
                cachedPortraitSize = window.frame.size
            }
            let portrait = cachedPortraitSize ?? window.frame.size
            let targetSize: NSSize = nextLandscape
                ? NSSize(width: portrait.height, height: portrait.width)
                : portrait
            let current = window.frame
            let newOrigin = NSPoint(
                x: current.midX - targetSize.width / 2,
                y: current.midY - targetSize.height / 2
            )
            window.aspectRatio = targetSize
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(
                    NSRect(origin: newOrigin, size: targetSize),
                    display: true
                )
            }
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            rotationQuarterTurns = next
        }
    }

    private func showToast(_ message: String, revealing url: URL?) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { toastMessage = message }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { toastMessage = nil }
        }
        if let url {
            // Briefly flash the file in Finder so the user can locate it
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = 1.0
            baseZoomScale = 1.0
            panOffset = .zero
            basePanOffset = .zero
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

            Text("Searching for devices…")
                .font(.caption)
                .foregroundColor(.gray)

            if detectingSeconds >= 5 {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Unlock your iPhone", systemImage: "lock.open")
                    Label("Tap \"Trust This Computer\" if prompted", systemImage: "hand.tap")
                    if detectingSeconds >= 10 {
                        Label("Try a different USB cable or port", systemImage: "cable.connector")
                    }
                    if detectingSeconds >= 15 {
                        Label("Restart your iPhone", systemImage: "arrow.clockwise")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
                .transition(.opacity.animation(.easeIn(duration: 0.3)))
            }
        }
        .onAppear {
            detectingSeconds = 0
            detectingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                MainActor.assumeIsolated {
                    detectingSeconds += 1
                }
            }
        }
        .onDisappear {
            detectingTimer?.invalidate()
            detectingTimer = nil
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

            if message.contains("Camera access") || message.contains("System Settings") {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }

            Button("Retry") {
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
            mediaType: nil,
            position: .unspecified
        )
        guard let avDevice = discovery.devices.first(where: { $0.uniqueID == deviceID }) else {
            deviceManager.state = .error("Device not found")
            return
        }

        Task {
            do {
                try await captureEngine.startCapture(
                    device: avDevice,
                    frameHandler: { [displayLayer] sampleBuffer in
                        // CMSampleBuffer is not Sendable on the macOS 14 SDK (it becomes
                        // Sendable on macOS 15). The buffer is consumed once on the main
                        // thread and never retained, so the unsafe transfer is sound.
                        nonisolated(unsafe) let buffer = sampleBuffer
                        DispatchQueue.main.async {
                            displayLayer.displaySampleBuffer(buffer)
                        }
                    },
                    onResolutionChange: { resolution in
                        // Delivered from the capture queue whenever the stream
                        // dimensions change (first frame + device rotations).
                        DispatchQueue.main.async {
                            let nsSize = NSSize(width: resolution.width, height: resolution.height)
                            detectedResolution = nsSize
                            onResolutionDetected?(nsSize)
                        }
                    }
                )

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
