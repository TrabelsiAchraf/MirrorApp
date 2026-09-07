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

    @Test func retryReactivatesSelectionWithoutRecordingAPick() {
        let defaults = makeDefaults()
        let manager = DeviceManager(defaults: defaults)
        manager.register(a)
        manager.register(b)
        manager.selectDevice(b)
        manager.unregister(deviceID: "B")   // fallback to A, preference stays "B"
        manager.state = .error("boom")
        manager.retrySelectedDevice()
        #expect(manager.state == .connected(a))
        #expect(defaults.string(forKey: DeviceManager.lastSelectedDeviceKey) == "B")
        // The remembered device coming back must still take over (no explicit pick this session for A).
        manager.register(b)
        #expect(manager.selectedDevice?.id == "B")
    }

    @Test func severalDevicesWithoutPreferenceSelectTheFirst() {
        let manager = DeviceManager(defaults: makeDefaults())
        manager.register(a)
        manager.register(b)
        #expect(manager.selectedDevice?.id == "A")
        #expect(manager.state == .connected(a))
    }

    @Test func unregisteringANonSelectedDeviceKeepsTheUserPick() {
        let defaults = makeDefaults()
        defaults.set("A", forKey: DeviceManager.lastSelectedDeviceKey)
        let manager = DeviceManager(defaults: defaults)
        manager.register(a)
        manager.register(b)
        manager.selectDevice(b)          // explicit pick this session
        manager.unregister(deviceID: "A")  // not the selected one
        #expect(manager.selectedDevice?.id == "B")
        manager.register(a)              // remembered id is now "B"; A returning must not take over
        #expect(manager.selectedDevice?.id == "B")
    }

    @Test func errorStateSurvivesRepublishOfTheFailedDevice() {
        // A refused screen stream makes CoreMediaIO unpublish/republish the
        // iPhone. The error view must stay, with no fallback and no take-over.
        let defaults = makeDefaults()
        let manager = DeviceManager(defaults: defaults)
        manager.register(a)
        manager.register(b)
        manager.selectDevice(b)
        manager.state = .error("refused")
        manager.unregister(deviceID: "B")
        #expect(manager.state == .error("refused"))
        #expect(manager.selectedDevice?.id == "B")
        #expect(manager.devices.map(\.id) == ["A"])
        manager.register(b)
        #expect(manager.state == .error("refused"))
        #expect(manager.selectedDevice?.id == "B")
    }

    @Test func discoveryErrorStillAutoSelectsANewDevice() {
        // "No iPhone detected" has no selected device: plugging one in must
        // still switch to it automatically.
        let manager = DeviceManager(defaults: makeDefaults())
        manager.state = .error("No iPhone detected.")
        manager.register(a)
        #expect(manager.selectedDevice?.id == "A")
        #expect(manager.state == .connected(a))
    }

    @Test func retryFallsBackWhenTheFailedDeviceIsGone() {
        let manager = DeviceManager(defaults: makeDefaults())
        manager.register(a)
        manager.register(b)
        manager.selectDevice(b)
        manager.state = .error("refused")
        manager.unregister(deviceID: "B")
        manager.retrySelectedDevice()
        #expect(manager.selectedDevice?.id == "A")
        #expect(manager.state == .connected(a))
    }

    @Test func retryGoesBackToDetectingWhenNoDeviceRemains() {
        let manager = DeviceManager(defaults: makeDefaults())
        manager.register(a)
        manager.selectDevice(a)
        manager.state = .error("refused")
        manager.unregister(deviceID: "A")
        manager.retrySelectedDevice()
        #expect(manager.selectedDevice == nil)
        #expect(manager.state == .detecting)
    }

    @Test func registerIgnoresDuplicates() {
        let manager = DeviceManager(defaults: makeDefaults())
        manager.register(a)
        manager.register(a)
        #expect(manager.devices.count == 1)
    }
}
