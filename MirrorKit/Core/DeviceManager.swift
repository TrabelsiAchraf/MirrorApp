import AVFoundation
import CoreMediaIO

/// Handles discovery of iPhones connected via USB through CoreMediaIO + AVFoundation.
///
/// Marked `@MainActor` because all mutable state is observed by SwiftUI views and
/// the AVFoundation device-connection notifications are delivered on `.main`.
@MainActor
@Observable
final class DeviceManager {
    /// List of detected devices
    var devices: [ConnectedDevice] = []
    /// Currently selected device
    var selectedDevice: ConnectedDevice?
    /// Current discovery/capture state
    var state: CaptureState = .idle

    private static let rescanInterval: TimeInterval = 2.0
    private static let maxRescanAttempts = 15 // 15 × 2s = 30s

    // Observer tokens are mutated only from MainActor methods (start/stopDiscovery)
    // and read from `deinit`, which is single-threaded by definition. The unsafe
    // marker lets `deinit` clean them up without an isolation hop.
    @ObservationIgnored
    nonisolated(unsafe) private var connectObserver: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) private var disconnectObserver: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) private var rescanTimer: Timer?
    @ObservationIgnored
    nonisolated(unsafe) private var rescanCount = 0

    deinit {
        // `removeObserver(_:)` is documented as thread-safe by Apple, so it can
        // be invoked from the nonisolated `deinit` of a MainActor class.
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = disconnectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        rescanTimer?.invalidate()
    }

    // MARK: - Device discovery

    /// Starts iPhone USB discovery after checking camera permission.
    func startDiscovery() {
        stopDiscovery()
        state = .detecting

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            beginDiscovery()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.beginDiscovery()
                    } else {
                        self?.state = .error("Camera access is required to mirror your iPhone. Grant it in System Settings > Privacy & Security > Camera.")
                    }
                }
            }
        case .denied, .restricted:
            state = .error("Camera access is required to mirror your iPhone. Grant it in System Settings > Privacy & Security > Camera.")
        @unknown default:
            beginDiscovery()
        }
    }

    /// Actual discovery logic — observers registered BEFORE scan to avoid race condition.
    private func beginDiscovery() {
        // Register observers FIRST so no notification is missed
        connectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            nonisolated(unsafe) let captured = device
            MainActor.assumeIsolated {
                self?.handleDeviceConnected(captured)
            }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            nonisolated(unsafe) let captured = device
            MainActor.assumeIsolated {
                self?.handleDeviceDisconnected(captured)
            }
        }

        // Now scan for devices already connected
        scanExistingDevices()

        // If no device found yet, start polling — CoreMediaIO may need a few seconds
        if devices.isEmpty {
            startRescanTimer()
        }
    }

    /// Stops discovery and cleans up timers/observers.
    func stopDiscovery() {
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
            connectObserver = nil
        }
        if let observer = disconnectObserver {
            NotificationCenter.default.removeObserver(observer)
            disconnectObserver = nil
        }
        stopRescanTimer()
    }

    // MARK: - Polling retry

    private func startRescanTimer() {
        rescanCount = 0
        rescanTimer = Timer.scheduledTimer(withTimeInterval: Self.rescanInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rescanForDevices()
            }
        }
    }

    private func stopRescanTimer() {
        rescanTimer?.invalidate()
        rescanTimer = nil
        rescanCount = 0
    }

    private func rescanForDevices() {
        rescanCount += 1

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: nil,
            position: .unspecified
        )
        for avDevice in discovery.devices where Self.isIOSScreenCapture(avDevice) {
            addDevice(from: avDevice)
        }
        autoSelectIfNeeded()

        if !devices.isEmpty {
            stopRescanTimer()
        } else if rescanCount >= Self.maxRescanAttempts {
            stopRescanTimer()
            state = .error("No iPhone detected.\n\n• Make sure your iPhone is connected via USB\n• Unlock your iPhone and tap \"Trust This Computer\"\n• Try a different USB cable or port")
        }
    }

    /// Selects a device for capture
    func selectDevice(_ device: ConnectedDevice) {
        selectedDevice = device
        state = .connected(device)
    }

    // MARK: - Internal handling

    /// Scans devices that are already connected at launch
    private func scanExistingDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: nil,
            position: .unspecified
        )

        print("[MirrorKit] Found \(discovery.devices.count) external device(s)")
        for avDevice in discovery.devices {
            print("[MirrorKit]   → \(avDevice.localizedName) | model=\(avDevice.modelID) | muxed=\(avDevice.hasMediaType(.muxed)) video=\(avDevice.hasMediaType(.video))")
            if Self.isIOSScreenCapture(avDevice) {
                addDevice(from: avDevice)
            }
        }

        // Auto-select if there is only one device
        autoSelectIfNeeded()

        // If no device was found, stay in detecting mode
        // Devices may take a few seconds to appear after CoreMediaIO activation
        if devices.isEmpty {
            state = .detecting
        }
    }

    private func handleDeviceConnected(_ avDevice: AVCaptureDevice) {
        // Accept iOS devices that provide video (muxed or video-only)
        guard Self.isIOSScreenCapture(avDevice) else { return }
        addDevice(from: avDevice)
        autoSelectIfNeeded()
        stopRescanTimer()
    }

    /// USB screen capture devices have `.muxed` media type (audio + video).
    /// Continuity Camera and webcams have only `.video` — this filter excludes them.
    private static func isIOSScreenCapture(_ device: AVCaptureDevice) -> Bool {
        device.hasMediaType(.muxed)
    }

    private func handleDeviceDisconnected(_ avDevice: AVCaptureDevice) {
        let deviceID = avDevice.uniqueID
        devices.removeAll { $0.id == deviceID }

        if selectedDevice?.id == deviceID {
            selectedDevice = nil
            // Select the next available device or fall back to detecting
            if let next = devices.first {
                selectDevice(next)
            } else {
                state = .detecting
            }
        }
    }

    private func addDevice(from avDevice: AVCaptureDevice) {
        // Avoid duplicates
        guard !devices.contains(where: { $0.id == avDevice.uniqueID }) else { return }

        let device = ConnectedDevice(
            id: avDevice.uniqueID,
            name: avDevice.localizedName,
            modelID: avDevice.modelID
        )
        devices.append(device)
        print("[MirrorKit] Device detected: \(device.name) (\(device.modelID))")
    }

    private func autoSelectIfNeeded() {
        if devices.count == 1, selectedDevice == nil {
            selectDevice(devices[0])
        }
    }
}
