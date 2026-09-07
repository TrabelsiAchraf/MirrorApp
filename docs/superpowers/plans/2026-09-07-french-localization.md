# French Localization (1.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship MirrorKit 1.2.0 with a complete French UI (menus, views, error messages, camera permission prompt), selected automatically from the user's macOS language.

**Architecture:** Two String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`) with `en` as source language and `fr` translations. SwiftUI literals (`Text`, `Button`, `Label`, `Section`, `LabeledContent`, `.help`, `.accessibilityLabel`) localize through `LocalizedStringKey` for free; every other user-facing string (AppKit menu titles, error messages, onboarding copy, display names, panel prompts, toasts) goes through `String(localized:)`. A unit test parses the catalog to guarantee every key has a French translation, and a second test checks the built bundle actually resolves French.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, Foundation `String(localized:)`, Xcode String Catalogs (`.xcstrings`), Swift Testing, xcodegen 2.45.

**Spec:** ROADMAP.md — the "French localization" bullet moves from "Next release — 1.3" into "Shipped › 1.2.0" (this plan is the expansion; the user approved the four-point plan in conversation on 2026-09-07).

## Global Constraints

- macOS deployment target `14.0`; Swift `6.0`; `SWIFT_STRICT_CONCURRENCY: complete`; `SWIFT_EMIT_LOC_STRINGS: YES` (already set on the app target).
- 100% Apple frameworks, no external dependencies.
- Source code, comments and the English source strings stay in English. French is the only added language.
- Commit messages in English, one commit per task, ending with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Never add `entitlements.path` or `ENABLE_APP_SANDBOX` to `project.yml`. After adding files run `xcodegen generate` and commit `MirrorKit.xcodeproj/project.pbxproj`.
- Version stays `1.2.0` / build `10` (nothing has been archived yet).
- Build + test command (every task): `xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug -destination 'platform=macOS' test 2>&1 | grep -E "error:|warning: .*(MirrorKit/|MirrorKitTests/)|Test run with|TEST (SUCCEEDED|FAILED)"` — baseline `Test run with 49 tests in 8 suites passed`.
- French style: Apple macOS conventions — vouvoiement, infinitive for menu actions, French typography with a no-break space (U+00A0, written ` ` in JSON) before `:` `;` `!` `?` and inside « » guillemets, ellipsis `…` kept. Proper nouns and product names (MirrorKit, iPhone, Mac, USB, USB-C, QuickTime Player, MDM, iPhone model names such as "iPhone 16") are not translated.
- Format specifiers: a `String` interpolation becomes `%@`, an `Int` becomes `%lld`. Keys in the catalog are the English source strings exactly as written in code, with `\n` for newlines.

---

### Task 1: Route every non-SwiftUI user-facing string through `String(localized:)`

**Why:** SwiftUI view literals localize automatically, but ~45 strings are built in plain Swift (AppKit menus, error messages, onboarding step arrays, enum display names, NSOpenPanel prompts, toasts). Without this task they stay English whatever the catalog says. Zero visible change in English.

**Files:**
- Modify: `MirrorKit/AppDelegate.swift` (menu titles, About window title, init error)
- Modify: `MirrorKit/Core/DeviceManager.swift` (camera + no-iPhone errors)
- Modify: `MirrorKit/Core/CaptureFailure.swift` (`hint`, `message`)
- Modify: `MirrorKit/Core/CaptureEngine.swift` (`CaptureError.errorDescription`)
- Modify: `MirrorKit/Core/VideoRecorder.swift` (two error descriptions)
- Modify: `MirrorKit/UI/MirrorContentView.swift` (toasts, "Device not found", camera-button condition)
- Modify: `MirrorKit/UI/OnboardingView.swift` (steps array)
- Modify: `MirrorKit/UI/SettingsView.swift` ("Not set")
- Modify: `MirrorKit/UI/FloatingToolbar.swift` ("No device", "Settings…" menu item)
- Modify: `MirrorKit/Models/BackgroundPreset.swift`, `MirrorKit/Models/BezelStyle.swift` (display names)
- Modify: `MirrorKit/Utils/ExportManager.swift`, `MirrorKit/Utils/SaveLocationManager.swift`
- Test: `MirrorKitTests/CaptureFailureTests.swift` (existing assertions must keep passing; one new test below)

**Interfaces:**
- Produces: `DeviceManager.cameraAccessMessage: String` (static, localized) — consumed by `MirrorContentView.errorView` to decide whether to show "Open System Settings".
- Consumes: nothing new.

- [ ] **Step 1: Write the failing test**

Append to `struct CaptureFailureTests` in `MirrorKitTests/CaptureFailureTests.swift`:

```swift
    @Test func cameraAccessMessageIsAStableIdentity() {
        // The error view shows "Open System Settings" only for this message;
        // it must be a single shared value, not a duplicated literal.
        #expect(DeviceManager.cameraAccessMessage.contains("Camera access"))
    }
```

- [ ] **Step 2: Run the tests to verify it fails**

Run the build + test command. Expected: compile error `type 'DeviceManager' has no member 'cameraAccessMessage'`.

- [ ] **Step 3: DeviceManager — shared camera message and localized errors**

In `MirrorKit/Core/DeviceManager.swift`, add after `static let lastSelectedDeviceKey = "lastSelectedDeviceID"`:

```swift
    /// Shown when camera permission is missing. Kept as one shared value so the
    /// error view can recognise it and offer to open System Settings.
    static let cameraAccessMessage = String(localized: "Camera access is required to mirror your iPhone. Grant it in System Settings > Privacy & Security > Camera.")
```

Replace both `.error("Camera access is required …")` occurrences (in `startDiscovery`) with `.error(Self.cameraAccessMessage)`, and the no-iPhone error in `rescanForDevices()` with:

```swift
            state = .error(String(localized: "No iPhone detected.\n\n• Make sure your iPhone is connected via USB\n• Unlock your iPhone and tap \"Trust This Computer\"\n• Try a different USB cable or port"))
```

- [ ] **Step 4: MirrorContentView — camera button condition, toasts, not-found**

In `errorView(message:)` replace
```swift
            if message.contains("Camera access") || message.contains("System Settings") {
```
with
```swift
            if message == DeviceManager.cameraAccessMessage {
```
Replace the three toasts and the not-found error:
```swift
        showToast(String(localized: "Snapshot saved — \(url.lastPathComponent)"), revealing: url)
        …
        showToast(String(localized: "Recording saved — \(url.lastPathComponent)"), revealing: url)
        …
        showToast(String(localized: "Recording…"), revealing: nil)
        …
            deviceManager.state = .error(String(localized: "Device not found"))
```

- [ ] **Step 5: CaptureFailure — hint and messages**

Replace the bodies of `hint(deviceName:)` and `message(deviceName:)`:

```swift
    func hint(deviceName: String) -> String {
        String(localized: "Waiting for video from \(deviceName)… Unlock the iPhone and keep its screen on.")
    }

    func message(deviceName: String) -> String {
        switch self {
        case .deviceRefused:
            return String(localized: "\(deviceName) was detected but refused to stream its screen.\n\n• Restart the iPhone, then reconnect it — this fixes most cases\n• On the iPhone, check Screen Time › Content & Privacy Restrictions › Screen Recording is allowed\n• Check for a management (MDM) profile that restricts screen recording")
        case .deviceDisconnected:
            return String(localized: "\(deviceName) was disconnected.\n\nReconnect the USB cable and try again.")
        case .deviceInUse:
            return String(localized: "\(deviceName) is already being captured by another app.\n\nQuit QuickTime Player or any other mirroring app, then retry.")
        case .noFrames(let timeout):
            return String(localized: "No video received from \(deviceName) after \(Int(timeout)) seconds.\n\n• Unlock the iPhone and keep its screen on\n• Unplug and reconnect the iPhone\n• Try a different USB cable or port")
        case .other(let description):
            return String(localized: "Capture failed: \(description)")
        }
    }
```
(The existing tests assert `contains("Screen Time")`, `contains("10 seconds")`, `contains("Unlock")`, `contains("boom")`, `contains("Virus")` — all still true in English.)

- [ ] **Step 6: CaptureEngine and VideoRecorder error descriptions**

`CaptureError.errorDescription` in `MirrorKit/Core/CaptureEngine.swift`:
```swift
        case .inputCreationFailed(let error):
            return String(localized: "Failed to create capture input: \(error.localizedDescription)")
        case .inputNotSupported:
            return String(localized: "Capture input is not supported by the session")
        case .outputNotSupported:
            return String(localized: "Video output is not supported by the session")
        case .sessionConfigurationFailed(let reason):
            return String(localized: "Failed to configure capture session: \(reason)")
```
`MirrorKit/Core/VideoRecorder.swift` (lines 16 and 18):
```swift
            return String(localized: "Failed to create asset writer: \(error.localizedDescription)")
            …
            return String(localized: "Recorder is not ready")
```

- [ ] **Step 7: AppDelegate menus, About window, init error**

Wrap every `NSMenuItem(title:)`, `NSMenu(title:)` and `aboutWindow.title` literal in `String(localized:)`: "Show Window", "Always on Top" (twice), "Settings…" (twice), "Quit MirrorKit" (twice), "About MirrorKit" (menu item and window title), "Window", "Capture", "Start / Stop Recording", "Take Snapshot", "Rotate Left", "Rotate Right", "Reset Zoom", "Toggle Annotation Mode  (A)", "Open Captures Folder". Example:
```swift
        let showItem = NSMenuItem(
            title: String(localized: "Show Window"),
            action: #selector(showMirrorWindow),
            keyEquivalent: ""
        )
```
And in `applicationDidFinishLaunching`:
```swift
            deviceManager.state = .error(String(localized: "Failed to initialize screen capture. Please restart MirrorKit."))
```

- [ ] **Step 8: Onboarding steps, Settings default, toolbar strings, display names, panels**

`MirrorKit/UI/OnboardingView.swift` — wrap the six title/description literals of the `steps` array:
```swift
    private let steps: [(icon: String, title: String, description: String)] = [
        (
            "iphone.and.arrow.forward",
            String(localized: "Welcome to MirrorKit"),
            String(localized: "Display your iPhone screen directly on your Mac. Perfect for presentations, development, or just keeping an eye on your phone.")
        ),
        (
            "cable.connector",
            String(localized: "Plug in your iPhone via USB"),
            String(localized: "Connect your iPhone to your Mac with a USB or USB-C cable. MirrorKit uses a wired connection for real-time, low-latency display.")
        ),
        (
            "camera.fill",
            String(localized: "Grant camera access"),
            String(localized: "macOS will ask for camera permission. This is normal — your iPhone is seen as a video capture device. No data is recorded or transmitted.")
        ),
    ]
```
`MirrorKit/UI/SettingsView.swift`: `?? String(localized: "Not set")`.

`MirrorKit/UI/FloatingToolbar.swift`: `deviceName: selectedDevice?.name ?? String(localized: "No device")` and `title: String(localized: "Settings…")` for the popup's first item.

`MirrorKit/Models/BackgroundPreset.swift` display names: `case .midnight: return String(localized: "Midnight")` … for all eight cases (Midnight, Charcoal, Snow, Sunset, Ocean, Aurora, Black, Custom). `MirrorKit/Models/BezelStyle.swift`: `String(localized: "Classic")`, `String(localized: "Frameless")`.

`MirrorKit/Utils/ExportManager.swift` line 10: `String(localized: "No save folder selected. Please choose a folder in Settings (⌘,).")`. `MirrorKit/Utils/SaveLocationManager.swift`: `panel.prompt = String(localized: "Choose")`, `panel.message = String(localized: "Choose a folder where MirrorKit will save snapshots and recordings.")`.

- [ ] **Step 9: Run the tests to verify they pass**

Run the build + test command. Expected: `Test run with 50 tests in 8 suites passed`, `TEST SUCCEEDED`, no warnings. (Without a catalog, `String(localized:)` returns the key, so English output is unchanged.)

- [ ] **Step 10: Commit**

```bash
git add MirrorKit MirrorKitTests
git commit -m "refactor: route user-facing strings through String(localized:)"
```

---

### Task 2: String Catalogs with the French translations, completeness tests, roadmap

**Files:**
- Create: `MirrorKit/Resources/Localizable.xcstrings`
- Create: `MirrorKit/Resources/InfoPlist.xcstrings`
- Modify: `MirrorKit/Info.plist` (add `CFBundleDevelopmentRegion`)
- Modify: `ROADMAP.md`
- Test: `MirrorKitTests/LocalizationTests.swift` (create)
- Regenerate: `MirrorKit.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: every key introduced by Task 1 and every SwiftUI literal listed in the glossary below.

- [ ] **Step 1: Write the failing tests**

Create `MirrorKitTests/LocalizationTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run `xcodegen generate` and the tests to verify they fail**

Expected: `everyKeyHasATranslatedFrenchValue` fails reading a missing file (`Data(contentsOf:)` throws), `builtBundleResolvesFrench` fails on the `#require` (no `fr.lproj`).

- [ ] **Step 3: Add `CFBundleDevelopmentRegion` to Info.plist**

In `MirrorKit/Info.plist`, right after the `CFBundleName` pair:
```xml
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
```

- [ ] **Step 4: Create `MirrorKit/Resources/InfoPlist.xcstrings`**

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "NSCameraUsageDescription" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "MirrorKit needs access to your iPhone connected via USB in order to display its screen." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "MirrorKit a besoin d’accéder à votre iPhone branché en USB pour afficher son écran." } }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 5: Create `MirrorKit/Resources/Localizable.xcstrings` from the glossary**

Write one JSON entry per row below, in this exact shape (the `en` unit is optional in a catalog — include only the `fr` localization, so the key itself is the English source):

```json
    "Retry" : {
      "localizations" : {
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Réessayer" } }
      }
    },
```

Escape `\n` and `"` in JSON keys/values; write no-break spaces as ` ` and apostrophes as the typographic `’`. File skeleton:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    … entries …
  },
  "version" : "1.0"
}
```

**Glossary (key → French).** Rows marked (same) keep the English value so the completeness test passes.

Floating toolbar:
| Key | French |
|---|---|
| Close window | Fermer la fenêtre |
| Minimize window | Réduire la fenêtre |
| Toggle expanded mode | Basculer le mode étendu |
| Stop recording | Arrêter l’enregistrement |
| Start recording | Démarrer l’enregistrement |
| Take snapshot | Prendre une capture |
| Rotate | Pivoter |
| Exit annotation mode | Quitter le mode annotation |
| Annotate | Annoter |
| No device | Aucun appareil |
| Settings… | Réglages… |
| Device and settings menu | Menu appareil et réglages |
| Choose device or open Settings | Choisir l’appareil ou ouvrir les Réglages |

Menus (AppDelegate):
| Key | French |
|---|---|
| Show Window | Afficher la fenêtre |
| Always on Top | Toujours au premier plan |
| Quit MirrorKit | Quitter MirrorKit |
| About MirrorKit | À propos de MirrorKit |
| Window | Fenêtre |
| Capture | Capture |
| Start / Stop Recording | Démarrer / arrêter l’enregistrement |
| Take Snapshot | Prendre une capture |
| Rotate Left | Pivoter à gauche |
| Rotate Right | Pivoter à droite |
| Reset Zoom | Réinitialiser le zoom |
| Toggle Annotation Mode  (A) | Mode annotation  (A) |
| Open Captures Folder | Ouvrir le dossier des captures |
| Failed to initialize screen capture. Please restart MirrorKit. | Impossible d’initialiser la capture d’écran. Veuillez relancer MirrorKit. |

Discovery and capture errors (keys contain `\n`, `%@`, `%lld` exactly as below):
| Key | French |
|---|---|
| Camera access is required to mirror your iPhone. Grant it in System Settings > Privacy & Security > Camera. | L’accès à la caméra est nécessaire pour afficher votre iPhone. Autorisez-le dans Réglages Système > Confidentialité et sécurité > Caméra. |
| No iPhone detected.\n\n• Make sure your iPhone is connected via USB\n• Unlock your iPhone and tap "Trust This Computer"\n• Try a different USB cable or port | Aucun iPhone détecté.\n\n• Vérifiez que votre iPhone est branché en USB\n• Déverrouillez votre iPhone et touchez « Se fier à cet ordinateur »\n• Essayez un autre câble ou un autre port USB |
| Device not found | Appareil introuvable |
| Waiting for video from %@… Unlock the iPhone and keep its screen on. | En attente de la vidéo de %@… Déverrouillez l’iPhone et laissez son écran allumé. |
| %@ was detected but refused to stream its screen.\n\n• Restart the iPhone, then reconnect it — this fixes most cases\n• On the iPhone, check Screen Time › Content & Privacy Restrictions › Screen Recording is allowed\n• Check for a management (MDM) profile that restricts screen recording | %@ a été détecté mais refuse de diffuser son écran.\n\n• Redémarrez l’iPhone puis rebranchez-le — cela résout la plupart des cas\n• Sur l’iPhone, vérifiez que Temps d’écran › Restrictions relatives au contenu et à la confidentialité › Enregistrement de l’écran est autorisé\n• Vérifiez qu’aucun profil de gestion (MDM) ne bloque l’enregistrement de l’écran |
| %@ was disconnected.\n\nReconnect the USB cable and try again. | %@ a été déconnecté.\n\nRebranchez le câble USB et réessayez. |
| %@ is already being captured by another app.\n\nQuit QuickTime Player or any other mirroring app, then retry. | %@ est déjà capturé par une autre app.\n\nQuittez QuickTime Player ou toute autre app de recopie, puis réessayez. |
| No video received from %@ after %lld seconds.\n\n• Unlock the iPhone and keep its screen on\n• Unplug and reconnect the iPhone\n• Try a different USB cable or port | Aucune vidéo reçue de %@ après %lld secondes.\n\n• Déverrouillez l’iPhone et laissez son écran allumé\n• Débranchez puis rebranchez l’iPhone\n• Essayez un autre câble ou un autre port USB |
| Capture failed: %@ | Échec de la capture : %@ |
| Failed to create capture input: %@ | Impossible de créer l’entrée de capture : %@ |
| Capture input is not supported by the session | L’entrée de capture n’est pas prise en charge par la session |
| Video output is not supported by the session | La sortie vidéo n’est pas prise en charge par la session |
| Failed to configure capture session: %@ | Impossible de configurer la session de capture : %@ |
| Failed to create asset writer: %@ | Impossible de créer l’enregistreur : %@ |
| Recorder is not ready | L’enregistreur n’est pas prêt |

Main view:
| Key | French |
|---|---|
| Snapshot saved — %@ | Capture enregistrée — %@ |
| Recording saved — %@ | Enregistrement sauvegardé — %@ |
| Recording… | Enregistrement… |
| Connect an iPhone via USB | Branchez un iPhone en USB |
| Searching for devices… | Recherche d’appareils… |
| Unlock your iPhone | Déverrouillez votre iPhone |
| Tap "Trust This Computer" if prompted | Touchez « Se fier à cet ordinateur » si demandé |
| Try a different USB cable or port | Essayez un autre câble ou un autre port USB |
| Restart your iPhone | Redémarrez votre iPhone |
| Start Mirroring | Démarrer la recopie |
| Error | Erreur |
| Open System Settings | Ouvrir les Réglages Système |
| Retry | Réessayer |

Onboarding and About:
| Key | French |
|---|---|
| Welcome to MirrorKit | Bienvenue dans MirrorKit |
| Display your iPhone screen directly on your Mac. Perfect for presentations, development, or just keeping an eye on your phone. | Affichez l’écran de votre iPhone directement sur votre Mac. Idéal pour les présentations, le développement, ou simplement pour garder un œil sur votre téléphone. |
| Plug in your iPhone via USB | Branchez votre iPhone en USB |
| Connect your iPhone to your Mac with a USB or USB-C cable. MirrorKit uses a wired connection for real-time, low-latency display. | Reliez votre iPhone à votre Mac avec un câble USB ou USB-C. MirrorKit utilise une connexion filaire pour un affichage en temps réel, à faible latence. |
| Grant camera access | Autorisez l’accès à la caméra |
| macOS will ask for camera permission. This is normal — your iPhone is seen as a video capture device. No data is recorded or transmitted. | macOS demandera l’autorisation d’accéder à la caméra. C’est normal : votre iPhone est vu comme un appareil de capture vidéo. Aucune donnée n’est enregistrée ni transmise. |
| Back | Précédent |
| Next | Suivant |
| Get Started | Commencer |
| Version %@ (%@) | Version %@ (%@) (same) |
| Display your iPhone screen\non your Mac via USB. | Affichez l’écran de votre iPhone\nsur votre Mac via USB. |
| © 2026 Achraf Trabelsi | © 2026 Achraf Trabelsi (same) |

Settings:
| Key | French |
|---|---|
| Not set | Non défini |
| Captures | Captures (same) |
| Save location | Emplacement d’enregistrement |
| Choose… | Choisir… |
| Display | Affichage |
| Bezel style | Style de bordure |
| Bezel color | Couleur de la bordure |
| Black | Noir |
| Silver | Argent |
| Gold | Or |
| Background (expanded mode) | Arrière-plan (mode étendu) |
| Custom… | Personnalisé… |
| Classic | Classique |
| Frameless | Sans bordure |
| Midnight | Minuit |
| Charcoal | Anthracite |
| Snow | Neige |
| Sunset | Crépuscule |
| Ocean | Océan |
| Aurora | Aurore |
| Custom | Personnalisé |
| No save folder selected. Please choose a folder in Settings (⌘,). | Aucun dossier d’enregistrement sélectionné. Choisissez un dossier dans les Réglages (⌘,). |
| Choose | Choisir |
| Choose a folder where MirrorKit will save snapshots and recordings. | Choisissez le dossier où MirrorKit enregistrera les captures et les enregistrements. |

That is 86 keys. Validate the JSON with `python3 -c "import json,sys; d=json.load(open('MirrorKit/Resources/Localizable.xcstrings')); print(len(d['strings']))"` → `86`.

- [ ] **Step 6: Regenerate, build, run the tests**

Run `xcodegen generate`, then the build + test command. Expected: `Test run with 54 tests in 9 suites passed` (50 + 2 parameterized cases + 2), `TEST SUCCEEDED`. If `builtBundleResolvesFrench` fails because `fr.lproj` is absent from the built app, the catalog was not compiled for French: check `ls "$(xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/MirrorKit.app/Contents/Resources"` for `fr.lproj`; if missing, report BLOCKED with that listing — do not improvise project settings.

- [ ] **Step 7: Update ROADMAP.md**

Remove the bullet `- **French localization** — no string catalog yet; FR is the primary market.` from "## Next release — 1.3" and append to "### 1.2.0" under "## Shipped":
```markdown
- French localization: String Catalogs for the UI and the camera permission
  prompt, selected from the macOS system language.
```

- [ ] **Step 8: Commit**

```bash
git add MirrorKit/Resources/Localizable.xcstrings MirrorKit/Resources/InfoPlist.xcstrings MirrorKit/Info.plist MirrorKitTests/LocalizationTests.swift MirrorKit.xcodeproj/project.pbxproj ROADMAP.md
git commit -m "feat: French localization via String Catalogs"
```

---

### Task 3 (controller, on the machine): verify the French UI

- [ ] Quit any running MirrorKit, then launch the Debug build in French: `open "<DerivedData>/Build/Products/Debug/MirrorKit.app" --args -AppleLanguages "(fr)"`.
- [ ] Menu bar: MirrorKit menu shows « À propos de MirrorKit », « Réglages… », « Quitter MirrorKit »; Fenêtre › « Toujours au premier plan »; Capture › « Prendre une capture ». Status item menu: « Afficher la fenêtre » … « Quitter MirrorKit ».
- [ ] Main view with no iPhone: « Branchez un iPhone en USB » / « Recherche d’appareils… »; with a locked iPhone after 10 s: the hint « En attente de la vidéo de … ».
- [ ] Toolbar accessibility labels in French (« Fermer la fenêtre », « Prendre une capture », …) via the AX dump script from the 1.2 batch plan.
- [ ] Settings window: « Emplacement d’enregistrement », « Style de bordure », « Arrière-plan (mode étendu) ».
- [ ] Relaunch without the argument: everything back in English.
