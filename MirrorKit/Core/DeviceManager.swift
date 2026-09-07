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

    /// UserDefaults key holding the `uniqueID` of the iPhone the user picked last.
    static let lastSelectedDeviceKey = "lastSelectedDeviceID"

    /// Shown when camera permission is missing. Kept as one shared value so the
    /// error view can recognise it and offer to open System Settings.
    nonisolated static let cameraAccessMessage = String(localized: "Camera access is required to mirror your iPhone. Grant it in System Settings > Privacy & Security > Camera.")

    @ObservationIgnored
    private let defaults: UserDefaults
    /// True once the user explicitly picked a device in this session; the
    /// remembered device must not override an explicit choice.
    @ObservationIgnored
    private var userPickedThisSession = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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
                        self?.state = .error(Self.cameraAccessMessage)
                    }
                }
            }
        case .denied, .restricted:
            state = .error(Self.cameraAccessMessage)
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
        rescanTimer?.invalidate()   // idempotent: restart the cycle
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

        if !devices.isEmpty {
            stopRescanTimer()
        } else if rescanCount >= Self.maxRescanAttempts {
            stopRescanTimer()
            state = .error(String(localized: "No iPhone detected.\n\n• Make sure your iPhone is connected via USB\n• Unlock your iPhone and tap \"Trust This Computer\"\n• Try a different USB cable or port"))
        }
    }

    /// Selects a device for capture — user intent: remembered across launches.
    func selectDevice(_ device: ConnectedDevice) {
        userPickedThisSession = true
        defaults.set(device.id, forKey: Self.lastSelectedDeviceKey)
        activate(device)
    }

    /// True while the error view describes a failure of the *selected* device
    /// (refused stream, dead stream). Discovery errors ("No iPhone detected",
    /// camera permission) have no selection and must keep auto-selecting a
    /// device that shows up.
    private var isShowingCaptureError: Bool {
        if case .error = state { return selectedDevice != nil }
        return false
    }

    /// Makes `device` the active one without touching the stored preference.
    private func activate(_ device: ConnectedDevice) {
        print("[MirrorKit] Activating \(device.name) (was: \(selectedDevice?.name ?? "none"), state: \(state))")
        selectedDevice = device
        state = .connected(device)
    }

    /// Re-enters `.connected` for the current selection so the view restarts
    /// capture after an error. Not a user pick: the stored preference and
    /// `userPickedThisSession` are left untouched. No-op when nothing is selected.
    func retrySelectedDevice() {
        guard let device = selectedDevice else { return }
        // The failed device may have been unplugged while the error was shown.
        guard devices.contains(where: { $0.id == device.id }) else {
            selectedDevice = nil
            if let next = devices.first {
                userPickedThisSession = false
                activate(next)
            } else {
                state = .detecting
                startRescanTimer()
            }
            return
        }
        activate(device)
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
        stopRescanTimer()
    }

    /// USB screen capture devices have `.muxed` media type (audio + video).
    /// Continuity Camera and webcams have only `.video` — this filter excludes them.
    private static func isIOSScreenCapture(_ device: AVCaptureDevice) -> Bool {
        device.hasMediaType(.muxed)
    }

    private func handleDeviceDisconnected(_ avDevice: AVCaptureDevice) {
        unregister(deviceID: avDevice.uniqueID)
    }

    /// Removes a device; falls back to another connected device or to detecting.
    func unregister(deviceID: String) {
        let name = devices.first { $0.id == deviceID }?.name ?? deviceID
        print("[MirrorKit] Device disconnected: \(name) (selected: \(selectedDevice?.name ?? "none"), state: \(state))")
        devices.removeAll { $0.id == deviceID }

        // While an error is displayed, leave the selection and the message
        // alone. A failed screen stream makes CoreMediaIO unpublish and
        // republish the iPhone; reacting to that would replace the error view
        // with a fallback capture and then bounce back to the failing device
        // (remembered-device take-over) — an endless loop with no guidance.
        // The user resolves it with Retry or by picking another device.
        if isShowingCaptureError { return }

        if selectedDevice?.id == deviceID {
            selectedDevice = nil
            if let next = devices.first {
                // Fallback, not a user choice: the newly active device wasn't
                // picked this session, so the remembered device must still be
                // able to take over if it reappears (rule 3).
                userPickedThisSession = false
                activate(next)
            } else {
                state = .detecting
                // Connect notifications can be missed while CoreMediaIO
                // restarts its assistant; poll so republished iPhones are found.
                startRescanTimer()
            }
        }

        // Removing a device that wasn't selected can still leave nothing
        // selected (e.g. a prior state with no usable preference) — give the
        // fallback rules another chance to resolve a selection.
        autoSelectIfNeeded()
    }

    private func addDevice(from avDevice: AVCaptureDevice) {
        register(ConnectedDevice(
            id: avDevice.uniqueID,
            name: avDevice.localizedName,
            modelID: avDevice.modelID
        ))
    }

    /// Adds a device (ignoring duplicates) and applies the auto-selection rules.
    /// Internal so tests can drive the manager without AVCaptureDevice.
    func register(_ device: ConnectedDevice) {
        if !devices.contains(where: { $0.id == device.id }) {
            devices.append(device)
            print("[MirrorKit] Device detected: \(device.name) (\(device.modelID))")
        }
        // Also for an already-known device: a rescan or a republish after a
        // failed stream must be able to resolve a selection when the app is
        // sitting in .detecting with nothing selected.
        autoSelectIfNeeded()
    }

    /// Resolves a selection whenever nothing is currently selected, in order:
    /// 1. A single connected device is always selected.
    /// 2. The remembered device (last explicit pick), if it's connected.
    /// 3. The first connected device — a last resort so the toolbar's device
    ///    picker appears and the user can switch, instead of getting stuck on
    ///    "Searching for devices…" with several iPhones plugged in.
    ///
    /// When something is already selected, the remembered device can still
    /// take over an automatic (non-user) selection once it shows up (rule below).
    private func autoSelectIfNeeded() {
        // Never auto-switch away from (or back to) a device while its error is
        // on screen — see `unregister`.
        if isShowingCaptureError { return }

        let remembered = defaults.string(forKey: Self.lastSelectedDeviceKey)

        if selectedDevice == nil {
            if devices.count == 1 {
                activate(devices[0])
            } else if let match = devices.first(where: { $0.id == remembered }) {
                activate(match)
            } else if let first = devices.first {
                // Several devices, no usable preference: pick the first so the
                // toolbar's device picker appears and the user can switch.
                activate(first)
            }
            return
        }

        // Something is already active. If it was picked automatically and the
        // remembered device has just shown up, prefer the remembered one.
        if !userPickedThisSession,
           let remembered,
           selectedDevice?.id != remembered,
           let match = devices.first(where: { $0.id == remembered }) {
            activate(match)
        }
    }
}
