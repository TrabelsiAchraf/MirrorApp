import Testing
@testable import MirrorKit

@Suite("BackgroundPreset")
struct BackgroundPresetTests {
    @Test("Parses valid raw values")
    func parsesValidRawValues() {
        #expect(BackgroundPreset(rawValue: "midnight") == .midnight)
        #expect(BackgroundPreset(rawValue: "charcoal") == .charcoal)
        #expect(BackgroundPreset(rawValue: "snow") == .snow)
        #expect(BackgroundPreset(rawValue: "sunset") == .sunset)
        #expect(BackgroundPreset(rawValue: "ocean") == .ocean)
        #expect(BackgroundPreset(rawValue: "aurora") == .aurora)
        #expect(BackgroundPreset(rawValue: "black") == .black)
        #expect(BackgroundPreset(rawValue: "custom") == .custom)
    }

    @Test("Unknown raw value returns nil")
    func unknownRawValueReturnsNil() {
        #expect(BackgroundPreset(rawValue: "purple_haze") == nil)
        #expect(BackgroundPreset(rawValue: "") == nil)
    }

    @Test("All cases have distinct display names")
    func allCasesHaveDistinctDisplayNames() {
        let names = Set(BackgroundPreset.allCases.map(\.displayName))
        #expect(names.count == BackgroundPreset.allCases.count)
    }

    @Test("Display name for midnight is 'Midnight'")
    func displayNameForMidnightIsCapitalized() {
        #expect(BackgroundPreset.midnight.displayName == "Midnight")
    }
}
