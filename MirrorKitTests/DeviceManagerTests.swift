import Foundation
import Testing
@testable import MirrorKit

@Suite("DeviceManager selection")
@MainActor
struct DeviceManagerTests {
    private let a = ConnectedDevice(id: "A", name: "iPhone A", modelID: "iOS Device")
    private let b = ConnectedDevice(id: "B", name: "iPhone B", modelID: "iOS Device")

    private func makeDefaults() -> UserDefaults {
        let suite = "DeviceManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func singleDeviceIsAutoSelected() {
        let manager = DeviceManager(defaults: makeDefaults())
        manager.register(a)
        #expect(manager.selectedDevice?.id == "A")
        #expect(manager.state == .connected(a))
    }

    @Test func userPickRemembersTheDevice() {
        let defaults = makeDefaults()
        let manager = DeviceManager(defaults: defaults)
        manager.register(a)
        manager.register(b)
        manager.selectDevice(b)
        #expect(defaults.string(forKey: DeviceManager.lastSelectedDeviceKey) == "B")
    }

    @Test func rememberedDeviceWinsWhenSeveralAppearAtOnce() {
        let defaults = makeDefaults()
        defaults.set("B", forKey: DeviceManager.lastSelectedDeviceKey)
        let manager = DeviceManager(defaults: defaults)
        manager.register(a)      // alone → auto-selected
        manager.register(b)      // remembered → takes over (no user pick this session)
        #expect(manager.selectedDevice?.id == "B")
    }

    @Test func userPickIsNotOverriddenByRememberedDeviceArrivingLater() {
        let defaults = makeDefaults()
        defaults.set("B", forKey: DeviceManager.lastSelectedDeviceKey)
        let manager = DeviceManager(defaults: defaults)
        manager.register(a)
        manager.selectDevice(a)  // explicit pick this session
        manager.register(b)
        #expect(manager.selectedDevice?.id == "A")
        #expect(defaults.string(forKey: DeviceManager.lastSelectedDeviceKey) == "A")
    }

    @Test func fallbackAfterDisconnectDoesNotOverwritePreference() {
        let defaults = makeDefaults()
        let manager = DeviceManager(defaults: defaults)
        manager.register(a)
        manager.register(b)
        manager.selectDevice(b)
        manager.unregister(deviceID: "B")
        #expect(manager.selectedDevice?.id == "A")
        #expect(defaults.string(forKey: DeviceManager.lastSelectedDeviceKey) == "B")
    }

    @Test func unregisteringLastDeviceGoesBackToDetecting() {
        let manager = DeviceManager(defaults: makeDefaults())
        manager.register(a)
        manager.unregister(deviceID: "A")
        #expect(manager.selectedDevice == nil)
        #expect(manager.state == .detecting)
    }
}
