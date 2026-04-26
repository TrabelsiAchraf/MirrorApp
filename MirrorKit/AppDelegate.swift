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
        LegacyMigration.migrateBezelStyleIfNeeded(in: .standard)
        // Enable iOS device discovery (iPhone screens via USB)
        let coreMediaIOReady = enableScreenCaptureDevices()

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

        // Start device discovery (or show error if CoreMediaIO failed)
        if coreMediaIOReady {
            deviceManager.startDiscovery()
        } else {
            deviceManager.state = .error("Failed to initialize screen capture. Please restart MirrorKit.")
        }
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

    /// Intercepts Cmd+T (always-on-top), capture shortcuts (record, snapshot, rotate, zoom reset)
    /// and the bare "A" key for annotation mode (only when the mirror window is key
    /// and no text field is being edited).
    private func setupKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Bare "A" toggles annotation mode — only when the mirror window is key
            // and no text editor is the first responder (so Settings text fields keep
            // accepting the literal character).
            if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
               event.charactersIgnoringModifiers?.lowercased() == "a",
               self.mirrorWindowController?.window?.isKeyWindow == true,
               !Self.isEditingText() {
                MirrorActions.shared.toggleAnnotationMode?()
                return nil
            }

            guard event.modifierFlags.contains(.command) else { return event }
            let shift = event.modifierFlags.contains(.shift)
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

            // Arrow keys (rotate left/right)
            if let special = event.specialKey, !shift {
                switch special {
                case .leftArrow:
                    MirrorActions.shared.rotateLeft?()
                    return nil
                case .rightArrow:
                    MirrorActions.shared.rotateRight?()
                    return nil
                default:
                    break
                }
            }

            switch (chars, shift) {
            case ("t", false):
                self.toggleAlwaysOnTopFromMenu()
                return nil
            case ("r", false):
                MirrorActions.shared.toggleRecording?()
                return nil
            case ("s", false):
                MirrorActions.shared.takeSnapshot?()
                return nil
            case ("r", true):
                MirrorActions.shared.toggleRotation?()
                return nil
            case ("0", false):
                MirrorActions.shared.resetZoom?()
                return nil
            default:
                return event
            }
        }
    }

    /// True when the focused responder is a text editor (NSTextView, including the
    /// field editor used by NSTextField/NSSearchField). Lets us preserve typing of
    /// "a" inside Settings or any other text input.
    private static func isEditingText() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if responder is NSTextField {
            return true
        }
        return false
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
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
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

        // "Capture" menu
        let captureMenu = NSMenu(title: "Capture")
        let captureMenuItem = NSMenuItem()
        captureMenuItem.submenu = captureMenu

        let recordItem = NSMenuItem(title: "Start / Stop Recording", action: #selector(captureToggleRecording), keyEquivalent: "r")
        recordItem.target = self
        captureMenu.addItem(recordItem)

        let snapshotItem = NSMenuItem(title: "Take Snapshot", action: #selector(captureSnapshot), keyEquivalent: "s")
        snapshotItem.target = self
        captureMenu.addItem(snapshotItem)

        captureMenu.addItem(.separator())

        let rotateLeftItem = NSMenuItem(title: "Rotate Left", action: #selector(captureRotateLeft), keyEquivalent: "\u{F702}")
        rotateLeftItem.keyEquivalentModifierMask = [.command]
        rotateLeftItem.target = self
        captureMenu.addItem(rotateLeftItem)

        let rotateRightItem = NSMenuItem(title: "Rotate Right", action: #selector(captureRotateRight), keyEquivalent: "\u{F703}")
        rotateRightItem.keyEquivalentModifierMask = [.command]
        rotateRightItem.target = self
        captureMenu.addItem(rotateRightItem)

        let resetZoomItem = NSMenuItem(title: "Reset Zoom", action: #selector(captureResetZoom), keyEquivalent: "0")
        resetZoomItem.target = self
        captureMenu.addItem(resetZoomItem)

        // The hotkey is handled by setupKeyboardMonitor (bare "A" with text-field guard);
        // the menu item itself omits keyEquivalent to avoid intercepting text input.
        let annotateItem = NSMenuItem(
            title: "Toggle Annotation Mode  (A)",
            action: #selector(captureToggleAnnotation),
            keyEquivalent: ""
        )
        annotateItem.target = self
        captureMenu.addItem(annotateItem)

        captureMenu.addItem(.separator())

        let openFolderItem = NSMenuItem(
            title: "Open Captures Folder",
            action: #selector(openCapturesFolder),
            keyEquivalent: "o"
        )
        openFolderItem.keyEquivalentModifierMask = [.command, .shift]
        openFolderItem.target = self
        captureMenu.addItem(openFolderItem)

        mainMenu.addItem(captureMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func captureToggleRecording() { MirrorActions.shared.toggleRecording?() }
    @objc private func captureSnapshot() { MirrorActions.shared.takeSnapshot?() }
    @objc private func captureRotate() { MirrorActions.shared.toggleRotation?() }
    @objc private func captureRotateLeft() { MirrorActions.shared.rotateLeft?() }
    @objc private func captureRotateRight() { MirrorActions.shared.rotateRight?() }
    @objc private func captureResetZoom() { MirrorActions.shared.resetZoom?() }
    @objc private func captureToggleAnnotation() { MirrorActions.shared.toggleAnnotationMode?() }

    @objc private func openCapturesFolder() {
        if let url = SaveLocationManager.accessSaveFolder() {
            NSWorkspace.shared.open(url)
            url.stopAccessingSecurityScopedResource()
        } else if let url = SaveLocationManager.promptForFolder() {
            NSWorkspace.shared.open(url)
        }
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

    @objc private func openSettings() {
        // Open the SwiftUI Settings scene (macOS 14+)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
    @discardableResult
    private func enableScreenCaptureDevices() -> Bool {
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
            return false
        }
        print("[MirrorKit] CoreMediaIO enabled — iOS device discovery is now possible")
        return true
    }
}
