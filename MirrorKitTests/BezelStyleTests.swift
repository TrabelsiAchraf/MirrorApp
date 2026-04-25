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

@Suite("LegacyMigration.migrateBezelStyleIfNeeded")
struct LegacyMigrationTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.LegacyMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Legacy showDeviceFrame=true migrates to bezelStyle=classic")
    func legacyTrueMigratesToClassic() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "showDeviceFrame")
        let migrated = LegacyMigration.migrateBezelStyleIfNeeded(in: defaults)
        #expect(migrated == true)
        #expect(defaults.string(forKey: "bezelStyle") == "classic")
    }

    @Test("Legacy showDeviceFrame=false migrates to bezelStyle=none")
    func legacyFalseMigratesToNone() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "showDeviceFrame")
        let migrated = LegacyMigration.migrateBezelStyleIfNeeded(in: defaults)
        #expect(migrated == true)
        #expect(defaults.string(forKey: "bezelStyle") == "none")
    }

    @Test("No legacy and no current → defaults to classic")
    func noLegacyDefaultsToClassic() {
        let defaults = freshDefaults()
        let migrated = LegacyMigration.migrateBezelStyleIfNeeded(in: defaults)
        #expect(migrated == true)
        #expect(defaults.string(forKey: "bezelStyle") == "classic")
    }

    @Test("Already-set bezelStyle is not overwritten (idempotent)")
    func idempotent() {
        let defaults = freshDefaults()
        defaults.set("floating", forKey: "bezelStyle")
        defaults.set(true, forKey: "showDeviceFrame")  // legacy that should be ignored
        let migrated = LegacyMigration.migrateBezelStyleIfNeeded(in: defaults)
        #expect(migrated == false)
        #expect(defaults.string(forKey: "bezelStyle") == "floating")
    }
}
