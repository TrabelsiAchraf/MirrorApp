import AppKit
import SwiftUI
import CoreMediaIO

/// App delegate — CoreMediaIO, mirror window, menu bar icon, Cmd+T
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mirrorWindowController: MirrorWindowController?
    private let deviceManager = DeviceManager()
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enable iOS device discovery (iPhone screens via USB)
        enableScreenCaptureDevices()

        // Create and show the mirror window
        mirrorWindowController = MirrorWindowController(deviceManager: deviceManager)
        mirrorWindowController?.showWindow(nil)

        // Configure the menu bar icon
        setupStatusItem()

        // Keyboard monitor for Cmd+T (always-on-top)
        setupKeyboardMonitor()

        // Configure the main menu after SwiftUI
        DispatchQueue.main.async { [weak self] in
            self?.setupMainMenu()
        }

        // Start device discovery
        deviceManager.startDiscovery()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // The app stays alive via the status item even after the window is closed
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

    /// Updates the status item menu
    private func updateStatusMenu() {
        let menu = NSMenu()

        // Show window
        let showItem = NSMenuItem(
            title: "Show Window",
            action: #selector(showMirrorWindow),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        // Always-on-top toggle
        let alwaysOnTopItem = NSMenuItem(
            title: "Always on Top",
            action: #selector(toggleAlwaysOnTopFromMenu),
            keyEquivalent: ""
        )
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = (mirrorWindowController?.isAlwaysOnTop ?? false) ? .on : .off
        menu.addItem(alwaysOnTopItem)

        // Device frame toggle
        let frameItem = NSMenuItem(
            title: "Show iPhone Frame",
            action: #selector(toggleDeviceFrame),
            keyEquivalent: ""
        )
        frameItem.target = self
        frameItem.state = UserDefaults.standard.object(forKey: "showDeviceFrame") == nil
            ? .on  // Enabled by default
            : UserDefaults.standard.bool(forKey: "showDeviceFrame") ? .on : .off
        menu.addItem(frameItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit MirrorKit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Keyboard Monitor

    /// Intercepts Cmd+T to toggle always-on-top
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

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // "MirrorKit" menu
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let aboutItem = NSMenuItem(title: "About MirrorKit", action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit MirrorKit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        mainMenu.addItem(appMenuItem)

        // "Window" menu
        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu

        let alwaysOnTopItem = NSMenuItem(
            title: "Always on Top",
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
        aboutWindow.title = "About MirrorKit"
        aboutWindow.styleMask = [.titled, .closable]
        aboutWindow.center()
        aboutWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - CoreMediaIO

    /// Enables kCMIOHardwarePropertyAllowScreenCaptureDevices so macOS exposes
    /// iPhone screens connected via USB as AVCaptureDevice instances
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
            print("[MirrorKit] CoreMediaIO activation error: \(status)")
        } else {
            print("[MirrorKit] CoreMediaIO enabled — iOS device discovery is now possible")
        }
    }
}
