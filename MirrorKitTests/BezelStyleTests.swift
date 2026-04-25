import Testing
import Foundation
@testable import MirrorKit

@Suite("BezelStyle")
struct BezelStyleTests {
    @Test("Parses valid raw values")
    func parsesValidRawValues() {
        #expect(BezelStyle(rawValue: "classic") == .classic)
        #expect(BezelStyle(rawValue: "floating") == .floating)
        #expect(BezelStyle(rawValue: "none") == BezelStyle.none)
    }

    @Test("Unknown raw value returns nil")
    func unknownRawValueReturnsNil() {
        #expect(BezelStyle(rawValue: "fancy") == nil)
    }

    @Test("Display names are user-readable")
    func displayNames() {
        #expect(BezelStyle.classic.displayName == "Classic")
        #expect(BezelStyle.floating.displayName == "Floating")
        #expect(BezelStyle.none.displayName == "Frameless")
    }

    @Test("FrameColor round-trips via raw value")
    func frameColorRoundTrip() {
        #expect(DeviceFrameSpec.FrameColor(rawValue: "black") == .black)
        #expect(DeviceFrameSpec.FrameColor(rawValue: "silver") == .silver)
        #expect(DeviceFrameSpec.FrameColor(rawValue: "gold") == .gold)
        #expect(DeviceFrameSpec.FrameColor(rawValue: "purple") == nil)
        #expect(DeviceFrameSpec.FrameColor.black.rawValue == "black")
        #expect(DeviceFrameSpec.FrameColor.silver.rawValue == "silver")
        #expect(DeviceFrameSpec.FrameColor.gold.rawValue == "gold")
    }
}
