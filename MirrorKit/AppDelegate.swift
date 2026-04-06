import AppKit
import SwiftUI
import CoreMediaIO

/// Delegate de l'application — CoreMediaIO, fenêtre miroir, menu bar icon, Cmd+T
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mirrorWindowController: MirrorWindowController?
    private let deviceManager = DeviceManager()
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activer la découverte des appareils iOS (écrans iPhone via USB)
        enableScreenCaptureDevices()

        // Créer et afficher la fenêtre miroir
        mirrorWindowController = MirrorWindowController(deviceManager: deviceManager)
        mirrorWindowController?.showWindow(nil)

        // Configurer le menu bar icon
        setupStatusItem()

        // Moniteur clavier pour Cmd+T (always-on-top)
        setupKeyboardMonitor()

        // Configurer le menu principal après SwiftUI
        DispatchQueue.main.async { [weak self] in
            self?.setupMainMenu()
        }

        // Lancer la détection des appareils
        deviceManager.startDiscovery()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // L'app reste active via le status item même si la fenêtre est fermée
    }

    // MARK: - Status Item (Menu Bar Icon)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "MirrorKit")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        updateStatusMenu()
    }

    /// Met à jour le menu du status item
    private func updateStatusMenu() {
        let menu = NSMenu()

        // Afficher la fenêtre
        let showItem = NSMenuItem(
            title: "Afficher la fenêtre",
            action: #selector(showMirrorWindow),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        // Always-on-top toggle
        let alwaysOnTopItem = NSMenuItem(
            title: "Toujours au premier plan",
            action: #selector(toggleAlwaysOnTopFromMenu),
            keyEquivalent: ""
        )
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = (mirrorWindowController?.isAlwaysOnTop ?? false) ? .on : .off
        menu.addItem(alwaysOnTopItem)

        // Device frame toggle
        let frameItem = NSMenuItem(
            title: "Afficher le cadre iPhone",
            action: #selector(toggleDeviceFrame),
            keyEquivalent: ""
        )
        frameItem.target = self
        frameItem.state = UserDefaults.standard.object(forKey: "showDeviceFrame") == nil
            ? .on  // Par défaut activé
            : UserDefaults.standard.bool(forKey: "showDeviceFrame") ? .on : .off
        menu.addItem(frameItem)

        menu.addItem(.separator())

        // Quitter
        let quitItem = NSMenuItem(
            title: "Quitter MirrorKit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Moniteur clavier

    /// Intercepte Cmd+T pour basculer always-on-top
    private func setupKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.contains(.command) else { return event }

            if event.charactersIgnoringModifiers == "t" {
                self.toggleAlwaysOnTopFromMenu()
                return nil
            }
            return event
        }
    }

    // MARK: - Menu Principal

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Menu "MirrorKit"
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let aboutItem = NSMenuItem(title: "À propos de MirrorKit", action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quitter MirrorKit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        mainMenu.addItem(appMenuItem)

        // Menu "Fenêtre"
        let windowMenu = NSMenu(title: "Fenêtre")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu

        let alwaysOnTopItem = NSMenuItem(
            title: "Toujours au premier plan",
            action: #selector(toggleAlwaysOnTopFromMenu),
            keyEquivalent: "t"
        )
        alwaysOnTopItem.target = self
        windowMenu.addItem(alwaysOnTopItem)

        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Actions

    @objc private func showMirrorWindow() {
        if mirrorWindowController?.window?.isVisible == false {
            mirrorWindowController?.showWindow(nil)
        }
        mirrorWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAlwaysOnTopFromMenu() {
        mirrorWindowController?.toggleAlwaysOnTop()
        updateStatusMenu()
    }

    @objc private func toggleDeviceFrame() {
        let current = UserDefaults.standard.object(forKey: "showDeviceFrame") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "showDeviceFrame")
        UserDefaults.standard.set(!current, forKey: "showDeviceFrame")
        updateStatusMenu()
    }

    @objc private func showAboutWindow() {
        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)
        let aboutWindow = NSWindow(contentViewController: hostingController)
        aboutWindow.title = "À propos de MirrorKit"
        aboutWindow.styleMask = [.titled, .closable]
        aboutWindow.center()
        aboutWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
