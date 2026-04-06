import AppKit
import CoreMediaIO

/// Delegate de l'application — active CoreMediaIO au lancement et gère la fenêtre miroir
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mirrorWindowController: MirrorWindowController?
    private let deviceManager = DeviceManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activer la découverte des appareils iOS (écrans iPhone via USB)
        enableScreenCaptureDevices()

        // Créer et afficher la fenêtre miroir
        mirrorWindowController = MirrorWindowController(deviceManager: deviceManager)
        mirrorWindowController?.showWindow(nil)

        // Lancer la détection des appareils
        deviceManager.startDiscovery()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - CoreMediaIO

    /// Active kCMIOHardwarePropertyAllowScreenCaptureDevices pour que macOS expose
    /// les écrans iPhone connectés en USB comme des AVCaptureDevice
    private func enableScreenCaptureDevices() {
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &property,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
        if status != noErr {
            print("[MirrorKit] Erreur activation CoreMediaIO: \(status)")
        } else {
            print("[MirrorKit] CoreMediaIO activé — découverte des appareils iOS possible")
        }
    }
}
