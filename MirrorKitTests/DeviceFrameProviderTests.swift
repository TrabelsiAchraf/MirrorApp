import CoreGraphics
import Testing
@testable import MirrorKit

@Suite("DeviceFrameProvider")
struct DeviceFrameProviderTests {
    private let generic = "iOS Device"

    @Test func genericModelIDUsesResolutionForProMax() {
        let spec = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 1320, height: 2868))
        #expect(spec.displayName == "iPhone 17 Pro Max")
        #expect(spec.notchStyle == .dynamicIsland)
        #expect(spec.kind == .iPhone)
    }

    @Test func evenRoundedWidthStillMatches() {
        // AVFoundation reports 1180×2556 for the 1179×2556 iPhone 14 Pro panel.
        let spec = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 1180, height: 2556))
        #expect(spec.displayName == "iPhone 16")
        #expect(spec.notchStyle == .dynamicIsland)
    }

    @Test func landscapeResolutionMatchesTheSameModel() {
        let portrait = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 1179, height: 2556))
        let landscape = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 2556, height: 1179))
        #expect(portrait.displayName == "iPhone 16")
        #expect(landscape.displayName == portrait.displayName)
    }

    @Test func notchGenerationIsRecognised() {
        let spec = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 1170, height: 2532))
        #expect(spec.displayName == "iPhone 14")
        #expect(spec.notchStyle == .notch)
    }

    @Test func homeButtonPhoneHasNoNotch() {
        let spec = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 750, height: 1334))
        #expect(spec.displayName == "iPhone SE")
        #expect(spec.notchStyle == .none)
    }

    @Test func unknownResolutionFallsBackToGenericIPhone() {
        let spec = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 1000, height: 2000))
        #expect(spec.displayName == "iPhone")
    }

    @Test func specificModelIDStillWins() {
        // A real identifier must not be overridden by the resolution table.
        // "iPhone15,2" resolves via the existing majorVersion switch to "iPhone 15"
        // (unchanged by this task); the point is that it must NOT become "iPhone 16",
        // which is what the passed resolution (1179x2556) would match in the catalog.
        let spec = DeviceFrameProvider.frameSpec(for: "iPhone15,2", resolution: CGSize(width: 1179, height: 2556))
        #expect(spec.displayName == "iPhone 15")
    }

    @Test func iPadResolutionStillProducesIPadSpec() {
        let spec = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 1668, height: 2388))
        #expect(spec.kind == .iPad)
    }

    @Test func resolutionOutsideToleranceDoesNotMatch() {
        // 3 px off the 1179×2556 panel must fall back to the generic spec.
        let spec = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 1182, height: 2556))
        #expect(spec.displayName == "iPhone")
    }
}
