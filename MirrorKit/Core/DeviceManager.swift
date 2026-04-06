import AVFoundation
import CoreMediaIO

/// Gère la détection des iPhones connectés en USB via CoreMediaIO + AVFoundation
@Observable
final class DeviceManager {
    /// Liste des appareils détectés
    var devices: [ConnectedDevice] = []
    /// Appareil actuellement sélectionné
    var selectedDevice: ConnectedDevice?
    /// État actuel de la détection/capture
    var state: CaptureState = .idle

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    deinit {
        stopDiscovery()
    }

    // MARK: - Découverte des appareils

    /// Lance la détection des iPhones connectés en USB
    func startDiscovery() {
        state = .detecting

        // Scanner les appareils déjà connectés
        scanExistingDevices()

        // Observer les connexions/déconnexions
        connectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            self?.handleDeviceConnected(device)
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            self?.handleDeviceDisconnected(device)
        }
    }

    /// Arrête la détection
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

    /// Sélectionne un appareil pour la capture
    func selectDevice(_ device: ConnectedDevice) {
        selectedDevice = device
        state = .connected(device)
    }

    // MARK: - Gestion interne

    /// Scanne les appareils déjà connectés au lancement
    private func scanExistingDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )

        for avDevice in discovery.devices {
            addDevice(from: avDevice)
        }

        // Auto-sélection si un seul appareil
        autoSelectIfNeeded()

        // Si aucun appareil trouvé, rester en mode detecting
        // Les appareils peuvent mettre quelques secondes à apparaître après l'activation CoreMediaIO
        if devices.isEmpty {
            state = .detecting
        }
    }

    private func handleDeviceConnected(_ avDevice: AVCaptureDevice) {
        // Ne traiter que les appareils de type muxed (écrans iOS)
        guard avDevice.hasMediaType(.muxed) else { return }
        addDevice(from: avDevice)
        autoSelectIfNeeded()
    }

    private func handleDeviceDisconnected(_ avDevice: AVCaptureDevice) {
        let deviceID = avDevice.uniqueID
        devices.removeAll { $0.id == deviceID }

        if selectedDevice?.id == deviceID {
            selectedDevice = nil
            // Sélectionner le prochain appareil disponible ou revenir en idle
            if let next = devices.first {
                selectDevice(next)
            } else {
                state = .detecting
            }
        }
    }

    private func addDevice(from avDevice: AVCaptureDevice) {
        // Éviter les doublons
        guard !devices.contains(where: { $0.id == avDevice.uniqueID }) else { return }

        let device = ConnectedDevice(
            id: avDevice.uniqueID,
            name: avDevice.localizedName,
            modelID: avDevice.modelID
        )
        devices.append(device)
        print("[MirrorKit] Appareil détecté : \(device.name) (\(device.modelID))")
    }

    private func autoSelectIfNeeded() {
        if devices.count == 1, selectedDevice == nil {
            selectDevice(devices[0])
        }
    }
}
