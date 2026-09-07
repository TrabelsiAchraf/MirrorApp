import Foundation
import Testing
@testable import MirrorKit

@Suite("Localization")
struct LocalizationTests {
    /// Repo-relative path resolved from this test file's location.
    private static func catalogURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // MirrorKitTests/
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("MirrorKit/Resources/\(name).xcstrings")
    }

    private static func strings(in catalog: String) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: catalogURL(catalog))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "en")
        return try #require(root["strings"] as? [String: [String: Any]])
    }

    @Test(arguments: ["Localizable", "InfoPlist"])
    func everyKeyHasATranslatedFrenchValue(catalog: String) throws {
        let strings = try Self.strings(in: catalog)
        #expect(!strings.isEmpty)
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: Any]
            let fr = localizations?["fr"] as? [String: Any]
            let unit = fr?["stringUnit"] as? [String: Any]
            #expect(unit?["state"] as? String == "translated", "Missing French for key: \(key)")
            #expect((unit?["value"] as? String)?.isEmpty == false, "Empty French for key: \(key)")
        }
    }

    @Test func catalogCoversTheStringsRoutedInCode() throws {
        let keys = Set(try Self.strings(in: "Localizable").keys)
        for expected in [
            "Retry", "Show Window", "Settings…", "Start Mirroring", "Welcome to MirrorKit",
            "Camera access is required to mirror your iPhone. Grant it in System Settings > Privacy & Security > Camera.",
            "%@ was disconnected.\n\nReconnect the USB cable and try again.",
            "No video received from %@ after %lld seconds.\n\n• Unlock the iPhone and keep its screen on\n• Unplug and reconnect the iPhone\n• Try a different USB cable or port",
            "Midnight", "Classic", "Not set", "Choose",
        ] {
            #expect(keys.contains(expected), "Catalog lacks key: \(expected)")
        }
        #expect(keys.count >= 80)
    }

    @Test func builtBundleResolvesFrench() throws {
        let frPath = try #require(Bundle.main.path(forResource: "fr", ofType: "lproj"))
        let fr = try #require(Bundle(path: frPath))
        #expect(fr.localizedString(forKey: "Retry", value: nil, table: nil) == "Réessayer")
        #expect(fr.localizedString(forKey: "Show Window", value: nil, table: nil) == "Afficher la fenêtre")
        #expect(fr.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist") == "MirrorKit a besoin d’accéder à votre iPhone branché en USB pour afficher son écran.")
    }

    /// Every `String(localized: "…")` literal in the app sources must have a
    /// catalog entry — catches a new string added without a translation.
    @Test func everyStringLocalizedCallHasACatalogKey() throws {
        let keys = Set(try Self.strings(in: "Localizable").keys)
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MirrorKit")
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        let pattern = try NSRegularExpression(pattern: #"String\(localized: "((?:[^"\\]|\\.)*)""#)
        var found = 0
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let r = Range(match.range(at: 1), in: source) else { continue }
                var key = String(source[r])
                    .replacingOccurrences(of: #"\(Int(timeout))"#, with: "%lld")
                    .replacingOccurrences(of: #"\""#, with: "\"")
                    // The catalog is JSON: `\n` in the source literal decodes to a
                    // real newline once JSONSerialization parses the catalog key.
                    .replacingOccurrences(of: #"\n"#, with: "\n")
                // Any remaining String interpolation becomes %@.
                key = key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%@", options: .regularExpression)
                found += 1
                #expect(keys.contains(key), "No catalog entry for \(file.lastPathComponent): \(key)")
            }
        }
        #expect(found >= 40)
    }

    /// French values must keep the exact placeholder sequence of their key
    /// (a `%lld` turned into `%@` would be a runtime crash).
    @Test func frenchValuesKeepPlaceholders() throws {
        let strings = try Self.strings(in: "Localizable")
        let spec = try NSRegularExpression(pattern: #"%(?:lld|@)"#)
        func placeholders(_ s: String) -> [String] {
            spec.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }
        }
        for (key, entry) in strings {
            let value = ((entry["localizations"] as? [String: Any])?["fr"] as? [String: Any])
                .flatMap { $0["stringUnit"] as? [String: Any] }?["value"] as? String ?? ""
            #expect(placeholders(key) == placeholders(value), "Placeholder mismatch for key: \(key)")
        }
    }
}
