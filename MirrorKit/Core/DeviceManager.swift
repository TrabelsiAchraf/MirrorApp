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

    // Observer tokens are mutated only from MainActor methods (start/stopDiscovery)
    // and read from `deinit`, which is single-threaded by definition. The unsafe
    // marker lets `deinit` clean them up without an isolation hop.
    @ObservationIgnored
    nonisolated(unsafe) private var connectObserver: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) private var disconnectObserver: NSObjectProtocol?

    deinit {
        // `removeObserver(_:)` is documented as thread-safe by Apple, so it can
        // be invoked from the nonisolated `deinit` of a MainActor class.
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = disconnectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Device discovery

    /// Starts iPhone USB discovery
    func startDiscovery() {
        state = .detecting

        // Scan devices that are already connected
        scanExistingDevices()

        // Observe connections / disconnections.
        // The notifications are delivered on `.main` so we can assume MainActor
        // isolation inside the closure even though its type is nonisolated.
        connectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            // Notification is delivered on `.main`; AVCaptureDevice is a stable
            // system object referenced from the main thread only.
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
    }

    /// Stops discovery
    func stopDiscovery() {
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
            connectObserver = nil
        }
        if let observer = disconnectObserver {
            NotificationCenter.default.removeObserver(observer)
            disconnectObserver = nil
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
            mediaType: .muxed,
            position: .unspecified
        )

        for avDevice in discovery.devices {
            addDevice(from: avDevice)
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
        // Only handle muxed devices (iOS screens)
        guard avDevice.hasMediaType(.muxed) else { return }
        addDevice(from: avDevice)
        autoSelectIfNeeded()
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
