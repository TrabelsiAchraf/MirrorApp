# Priority 1 Batch (1.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the six low-risk quality fixes selected for MirrorKit 1.2: a non-blocking "waiting for video" hint, per-model bezel/name from the stream resolution, Dock reopen, Settings in the status menu, VoiceOver labels on the toolbar, and remembering the last selected iPhone.

**Architecture:** Every change stays inside the existing layers: `DeviceFrameProvider` (pure lookup, unit-tested), `DeviceManager` (`@MainActor @Observable`, unit-tested through a new internal `register(_:)` entry point and an injected `UserDefaults`), `CaptureFailure` (pure, unit-tested), and AppKit/SwiftUI glue in `AppDelegate`, `FloatingToolbar`, `MirrorContentView` (verified manually and with the accessibility dump script). No new files except tests and one small resolution table.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, AVFoundation/CoreMediaIO, Swift Testing (`import Testing`, `@Suite`, `#expect`), xcodegen.

**Spec:** ROADMAP.md, section "Next release — 1.2" (this plan is the spec's expansion; there is no separate design doc).

## Global Constraints

- macOS deployment target `14.0`; Swift `6.0`; `SWIFT_STRICT_CONCURRENCY: complete`.
- 100% Apple frameworks, no external dependencies.
- Everything in English: UI strings and code comments.
- Commit messages in English, one commit per task, ending with the `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` trailer.
- After adding a file, run `xcodegen generate` (the project is generated from `project.yml`; `MirrorKitTests` picks up every file under `MirrorKitTests/`).
- Never add `entitlements.path` or `ENABLE_APP_SANDBOX` to `project.yml`.
- Build + test command (used in every task):
  `xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug -destination 'platform=macOS' test 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"`
- Test on a physical iPhone for any capture-pipeline change (Task 0 and Task 1).

## Verification helper (used by Tasks 2, 3, 4)

Accessibility dump script — save as `/tmp/ax.swift`, compile with `swiftc -O /tmp/ax.swift -o /tmp/ax`, run with the app open. Requires the terminal to be allowed in System Settings › Privacy & Security › Accessibility.

```swift
import AppKit
import ApplicationServices
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.achraftrabelsi.MirrorKit").first else { print("not running"); exit(1) }
let axApp = AXUIElementCreateApplication(app.processIdentifier)
func attr(_ e: AXUIElement, _ a: String) -> Any? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func dump(_ e: AXUIElement, _ depth: Int) {
    guard depth < 6 else { return }
    let role = attr(e, kAXRoleAttribute) as? String ?? "?"
    let title = attr(e, kAXTitleAttribute) as? String ?? ""
    let desc = attr(e, kAXDescriptionAttribute) as? String ?? ""
    let value = attr(e, kAXValueAttribute) as? String ?? ""
    print(String(repeating: "  ", count: depth) + "\(role) title='\(title)' desc='\(desc)' value='\(value)'")
    if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { for k in kids { dump(k, depth + 1) } }
}
dump(axApp, 0)
```

---

### Task 0: "Waiting for video" hint instead of a hard error

**Why:** Observed on 2026-09-07 with a locked iPhone 14 Pro: the 10 s first-frame watchdog added in `d2fc6d7` turned a still-valid session into an error view ("No video received…"), while the real `'!dev'` refusal is the only case that must be fatal. A missing first frame must show a hint over the capture view and disappear when frames start.

**Files:**
- Modify: `MirrorKit/Core/CaptureFailure.swift`
- Modify: `MirrorKit/UI/MirrorContentView.swift` (state + `startCapture` + capture view overlay)
- Test: `MirrorKitTests/CaptureFailureTests.swift`

**Interfaces:**
- Produces: `CaptureFailure.isFatal: Bool` (false only for `.noFrames`), `CaptureFailure.hint(deviceName:) -> String` (short one-line text for the overlay).
- Consumes: `CaptureEngine.startCapture(device:frameHandler:onResolutionChange:onFailure:)` from `d2fc6d7` — unchanged.

- [ ] **Step 1: Write the failing tests**

Append inside `struct CaptureFailureTests`:

```swift
    @Test func onlyNoFramesIsNonFatal() {
        #expect(CaptureFailure.noFrames(timeout: 10).isFatal == false)
        #expect(CaptureFailure.deviceRefused.isFatal)
        #expect(CaptureFailure.deviceDisconnected.isFatal)
        #expect(CaptureFailure.deviceInUse.isFatal)
        #expect(CaptureFailure.other("boom").isFatal)
    }

    @Test func noFramesHintIsShortAndNamesTheDevice() {
        let hint = CaptureFailure.noFrames(timeout: 10).hint(deviceName: "Virus")
        #expect(hint.contains("Virus"))
        #expect(!hint.contains("\n"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run the build + test command. Expected: compile error `value of type 'CaptureFailure' has no member 'isFatal'`.

- [ ] **Step 3: Implement `isFatal` and `hint(deviceName:)`**

In `CaptureFailure.swift`, after `static let badDeviceOSStatus`:

```swift
    /// Whether the failure must tear the session down. `.noFrames` is only a
    /// hint: a locked iPhone or a slow USB re-enumeration legitimately delays
    /// the first frame, and the session recovers on its own.
    var isFatal: Bool {
        if case .noFrames = self { return false }
        return true
    }

    /// One-line text for the non-blocking overlay shown while no frame has
    /// arrived yet.
    func hint(deviceName: String) -> String {
        "Waiting for video from \(deviceName)… Unlock the iPhone and keep its screen on."
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the build + test command. Expected: `Test run with 30 tests in 6 suites passed`.

- [ ] **Step 5: Show the hint in the view instead of switching to `.error`**

In `MirrorContentView.swift`:

Add a state next to `@State private var detectedResolution: NSSize?`:

```swift
    /// Non-blocking hint shown over the capture view while no frame has arrived.
    @State private var waitingHint: String?
```

In `startCapture(deviceID:)`, replace the `onFailure` closure body:

```swift
                    onFailure: { [deviceManager] failure in
                        Task { @MainActor in
                            if failure.isFatal {
                                // Switching to .error tears the engine down via
                                // the onChange(of: deviceManager.state) handler.
                                deviceManager.state = .error(failure.message(deviceName: deviceName))
                            } else {
                                waitingHint = failure.hint(deviceName: deviceName)
                            }
                        }
                    }
```

In the same function, inside `onResolutionChange` (first frame → resolution known), clear the hint:

```swift
                        DispatchQueue.main.async {
                            waitingHint = nil
                            let nsSize = NSSize(width: resolution.width, height: resolution.height)
                            detectedResolution = nsSize
                            onResolutionDetected?(nsSize)
                        }
```

In `.onChange(of: deviceManager.state)` and `.onChange(of: deviceManager.selectedDevice?.id)`, add `waitingHint = nil` next to `isCapturing = false`.

In `mainContent`, `case .capturing:` — wrap the existing `captureView` so the hint overlays it:

```swift
            case .capturing:
                captureView
                    .aspectRatio(captureViewAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        if let waitingHint {
                            Label(waitingHint, systemImage: "hourglass")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                                .padding(.bottom, 40)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: waitingHint)
```

- [ ] **Step 6: Build, run on device**

Run the build + test command (expected SUCCEEDED, 30 tests). Launch the Debug app, plug a **locked** iPhone: after ~10 s the hint capsule appears at the bottom of the bezel, the view stays in capturing state. Unlock the iPhone: video appears and the hint disappears. Plug an iPhone that refuses the stream (if available): the error view still appears.

- [ ] **Step 7: Commit**

```bash
git add MirrorKit/Core/CaptureFailure.swift MirrorKit/UI/MirrorContentView.swift MirrorKitTests/CaptureFailureTests.swift
git commit -m "fix: show a waiting hint instead of an error when the first frame is late"
```

---

### Task 1: Model name and bezel from the stream resolution

**Why:** AVFoundation reports `modelID = "iOS Device"` for every USB iPhone, so `DeviceFrameProvider.frameSpec` always falls into the `default` spec ("iPhone", no notch, radius 40). The stream resolution is the only model signal we have.

**Precondition (verified 2026-09-07):** the stream is native-size, but the width can be rounded to an even number: the iPhone 14 Pro (native 1179×2556) logged `[MirrorKit] Resolution changed: 1180×2556`. The lookup must therefore tolerate ±2 px per dimension.

**Files:**
- Create: `MirrorKit/Utils/IPhoneResolutionCatalog.swift`
- Modify: `MirrorKit/Utils/DeviceFrameProvider.swift` (`frameSpec(for:resolution:)`, `iPhoneSpec(for:)`)
- Test: `MirrorKitTests/DeviceFrameProviderTests.swift`

**Interfaces:**
- Produces: `IPhoneResolutionCatalog.match(_ resolution: CGSize) -> IPhoneResolutionCatalog.Entry?` with `Entry { displayName: String; notchStyle: DeviceFrameSpec.NotchStyle; cornerRadius: CGFloat; bezelWidth: CGFloat }`.
- Consumes: `DeviceFrameSpec`, `DeviceFrameProvider.frameSpec(for:resolution:)` (existing callers in `MirrorContentView.swift:66,221,314` already pass `detectedResolution`; the toolbar `modelName` is `spec.displayName`).

- [ ] **Step 1: Write the failing tests**

Create `MirrorKitTests/DeviceFrameProviderTests.swift`:

```swift
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
        let spec = DeviceFrameProvider.frameSpec(for: "iPhone15,2", resolution: CGSize(width: 1179, height: 2556))
        #expect(spec.displayName == "iPhone 14")
    }

    @Test func iPadResolutionStillProducesIPadSpec() {
        let spec = DeviceFrameProvider.frameSpec(for: generic, resolution: CGSize(width: 1668, height: 2388))
        #expect(spec.kind == .iPad)
    }
}
```

Note: `DeviceFrameSpec.NotchStyle` and `.Kind` must be `Equatable` for `#expect(... == ...)`. They are plain enums without associated values, so Swift synthesizes it once declared: add `: Equatable` to both enum declarations in `DeviceFrameProvider.swift` (`enum Kind: Equatable`, `enum NotchStyle: Equatable`).

- [ ] **Step 2: Run `xcodegen generate` then the tests to verify they fail**

Expected: `genericModelIDUsesResolutionForProMax` fails with `displayName == "iPhone"` (and 4 others fail the same way); `specificModelIDStillWins`, `unknownResolutionFallsBackToGenericIPhone` and `iPadResolutionStillProducesIPadSpec` pass already.

- [ ] **Step 3: Create the resolution catalog**

`MirrorKit/Utils/IPhoneResolutionCatalog.swift`:

```swift
import CoreGraphics

/// Maps native iPhone screen resolutions to a display name and bezel geometry.
///
/// AVFoundation reports `modelID = "iOS Device"` for USB screen-capture
/// devices, so the stream resolution is the only signal we have. Several
/// models share a panel; the entry names the most recent one and the notch
/// style shared by the whole group.
enum IPhoneResolutionCatalog {
    struct Entry {
        /// Native portrait panel size in pixels.
        let width: Int
        let height: Int
        let displayName: String
        let notchStyle: DeviceFrameSpec.NotchStyle
        let cornerRadius: CGFloat
        let bezelWidth: CGFloat
    }

    /// The capture stream can round an odd native width up to an even number
    /// (the 1179×2556 iPhone 14 Pro streams as 1180×2556), so the lookup
    /// accepts a small per-dimension slack.
    static let tolerance = 2

    private static let entries: [Entry] = [
        // Dynamic Island generation
        Entry(width: 1320, height: 2868, displayName: "iPhone 17 Pro Max", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 5), // 16 Pro Max
        Entry(width: 1206, height: 2622, displayName: "iPhone 17 Pro", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 5),     // 17, 16 Pro
        Entry(width: 1260, height: 2736, displayName: "iPhone Air", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 5),
        Entry(width: 1290, height: 2796, displayName: "iPhone 16 Plus", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 6),    // 15 Plus, 15 Pro Max, 14 Pro Max
        Entry(width: 1179, height: 2556, displayName: "iPhone 16", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 6),         // 15, 15 Pro, 14 Pro
        // Notch generation
        Entry(width: 1170, height: 2532, displayName: "iPhone 14", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),                 // 13, 12 (16e shares it)
        Entry(width: 1284, height: 2778, displayName: "iPhone 14 Plus", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),            // 13 Pro Max, 12 Pro Max
        Entry(width: 1080, height: 2340, displayName: "iPhone 13 mini", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),            // 12 mini
        Entry(width: 1125, height: 2436, displayName: "iPhone 11 Pro", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),             // XS, X
        Entry(width: 1242, height: 2688, displayName: "iPhone 11 Pro Max", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),         // XS Max
        Entry(width: 828, height: 1792, displayName: "iPhone 11", notchStyle: .notch, cornerRadius: 47, bezelWidth: 7),                  // XR
        // Home button generation
        Entry(width: 750, height: 1334, displayName: "iPhone SE", notchStyle: .none, cornerRadius: 40, bezelWidth: 8),                   // 8, 7, 6s
        Entry(width: 1080, height: 1920, displayName: "iPhone 8 Plus", notchStyle: .none, cornerRadius: 40, bezelWidth: 8),
    ]

    /// Orientation-insensitive lookup with `tolerance` px of slack per
    /// dimension. Returns `nil` for unknown sizes.
    static func match(_ resolution: CGSize) -> Entry? {
        let w = Int(min(resolution.width, resolution.height).rounded())
        let h = Int(max(resolution.width, resolution.height).rounded())
        return entries.first { abs($0.width - w) <= tolerance && abs($0.height - h) <= tolerance }
    }
}
```

- [ ] **Step 4: Use the catalog in `DeviceFrameProvider`**

In `DeviceFrameProvider.swift`, replace `frameSpec(for:resolution:)`:

```swift
    static func frameSpec(for modelID: String, resolution: CGSize? = nil) -> DeviceFrameSpec {
        let iPad = modelID.hasPrefix("iPad") || isIPadResolution(resolution)
        if iPad { return iPadSpec(for: modelID) }

        // A real identifier ("iPhone15,2") is authoritative. USB screen devices
        // report the generic "iOS Device", so fall back to the resolution table.
        if extractMajorVersion(from: modelID, prefix: "iPhone") > 0 {
            return iPhoneSpec(for: modelID)
        }
        if let resolution, let entry = IPhoneResolutionCatalog.match(resolution) {
            return DeviceFrameSpec(
                displayName: entry.displayName,
                kind: .iPhone,
                cornerRadius: entry.cornerRadius,
                bezelWidth: entry.bezelWidth,
                frameColor: .black,
                notchStyle: entry.notchStyle
            )
        }
        return iPhoneSpec(for: modelID)
    }
```

`extractMajorVersion` returns `0` for "iOS Device" (no digits after the prefix), so the existing `iPhoneSpec(for:)` `default` branch still serves the unknown case.

- [ ] **Step 5: Run tests to verify they pass**

Run the build + test command. Expected: the 8 new `DeviceFrameProvider` tests pass along with the existing suites (`TEST SUCCEEDED`).

- [ ] **Step 6: Verify on device**

Launch the Debug app with the iPhone 14 Pro (unlocked): toolbar shows "iPhone 16" under the device name (shared 1179×2556 panel streamed as 1180×2556 — expected), bezel has a Dynamic Island. With the 17 Pro Max: "iPhone 17 Pro Max".

- [ ] **Step 7: Commit**

```bash
git add MirrorKit/Utils/IPhoneResolutionCatalog.swift MirrorKit/Utils/DeviceFrameProvider.swift MirrorKitTests/DeviceFrameProviderTests.swift MirrorKit.xcodeproj/project.pbxproj
git commit -m "feat: derive iPhone model name and bezel from the stream resolution"
```

---

### Task 2: Dock icon reopens the mirror window

**Why:** `applicationShouldTerminateAfterLastWindowClosed` returns `false` so the app lives on in the menu bar, but nothing handles a Dock click: the window stays hidden.

**Files:**
- Modify: `MirrorKit/AppDelegate.swift` (after `applicationShouldTerminateAfterLastWindowClosed`)

**Interfaces:**
- Consumes: existing `@objc private func showMirrorWindow()` in `AppDelegate`.

- [ ] **Step 1: Implement the delegate method**

```swift
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock icon click (or `open -a MirrorKit`) after the window was closed:
        // bring the mirror window back instead of doing nothing.
        if !flag {
            showMirrorWindow()
        }
        return true
    }
```

- [ ] **Step 2: Build and verify manually**

Run the build + test command (expected SUCCEEDED). Launch the Debug app, close the window with the red dot, click the MirrorKit Dock icon: the window reappears, centered where it was. Also run `open -a MirrorKit` from a terminal with the window closed: same result.

- [ ] **Step 3: Commit**

```bash
git add MirrorKit/AppDelegate.swift
git commit -m "fix: reopen the mirror window from the Dock icon"
```

---

### Task 3: "Settings…" in the status item menu

**Files:**
- Modify: `MirrorKit/AppDelegate.swift` (`updateStatusMenu()`)

**Interfaces:**
- Consumes: existing `@objc private func openSettings()` (uses `MirrorActions.shared.openSettings`).

- [ ] **Step 1: Add the item**

In `updateStatusMenu()`, after the `alwaysOnTopItem` block and its `menu.addItem(.separator())`, before the Quit item:

```swift
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
```

Resulting order: Show Window · — · Always on Top · — · Settings… · — · Quit MirrorKit.

- [ ] **Step 2: Build and verify manually**

Run the build + test command (expected SUCCEEDED). Click the iPhone icon in the menu bar › Settings…: the "MirrorKit Settings" window opens and the app comes to the front (`openSettings()` calls `NSApp.activate`).

- [ ] **Step 3: Commit**

```bash
git add MirrorKit/AppDelegate.swift
git commit -m "feat: add Settings entry to the status item menu"
```

---

### Task 4: Accessibility labels on the floating toolbar

**Why:** The toolbar buttons are image-only `Button`s with `.buttonStyle(.plain)`; VoiceOver reads them as unnamed buttons. The window itself is exposed correctly (verified with the dump script).

**Files:**
- Modify: `MirrorKit/UI/FloatingToolbar.swift`

**Interfaces:**
- Produces: `ToolbarIconButton(system:tint:label:action:)` — new required `label: String` parameter.

- [ ] **Step 1: Label the traffic lights**

In `mainRow`, add labels to the three circle buttons:

```swift
                Button(action: { NSApp.keyWindow?.close() }) {
                    Circle().fill(Color.red).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close window")

                Button(action: { NSApp.keyWindow?.miniaturize(nil) }) {
                    Circle().fill(Color.yellow).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimize window")

                Button(action: { onExpand?() }) {
                    Circle().fill(Color.green).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle expanded mode")
```

- [ ] **Step 2: Add `label` to `ToolbarIconButton` and its call sites**

```swift
private struct ToolbarIconButton: View {
    let system: String
    let tint: Color
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.22 : 0.10))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
```

Call sites in `mainRow`:

```swift
                ToolbarIconButton(
                    system: isRecording ? "stop.circle.fill" : "record.circle",
                    tint: isRecording ? .red : .white,
                    label: isRecording ? "Stop recording" : "Start recording",
                    action: { onToggleRecording?() }
                )
                ToolbarIconButton(system: "camera", tint: .white, label: "Take snapshot", action: { onSnapshot?() })
                ToolbarIconButton(system: "rotate.left", tint: .white, label: "Rotate", action: { onToggleRotation?() })
                if let canvas {
                    ToolbarIconButton(
                        system: canvas.isAnnotationModeActive ? "pencil.and.outline" : "pencil",
                        tint: canvas.isAnnotationModeActive ? .accentColor : .white,
                        label: canvas.isAnnotationModeActive ? "Exit annotation mode" : "Annotate",
                        action: { canvas.isAnnotationModeActive.toggle() }
                    )
                }
```

- [ ] **Step 3: Label the device picker pill**

In `DevicePickerButton`, on the `Button(action: action) { … }` (after `.buttonStyle(.plain)`):

```swift
            .accessibilityLabel("Device and settings menu")
            .accessibilityValue(deviceName)
            .help("Choose device or open Settings")
```

- [ ] **Step 4: Build and verify with the dump script**

Run the build + test command (expected SUCCEEDED). Launch the Debug app with an iPhone connected (toolbar visible on hover — hover the window first), run `/tmp/ax`. Expected lines include `AXButton … desc='Close window'`, `desc='Take snapshot'`, `desc='Device and settings menu' value='<iPhone name>'`.

- [ ] **Step 5: Commit**

```bash
git add MirrorKit/UI/FloatingToolbar.swift
git commit -m "feat: accessibility labels for the floating toolbar"
```

---

### Task 5: Remember the last selected iPhone

**Why:** With two iPhones connected the app auto-selects nothing (only `devices.count == 1` auto-selects) and forgets the user's choice between launches.

**Rules:**
1. A device the user picks (`selectDevice`) is remembered by `uniqueID` in `UserDefaults` under `lastSelectedDeviceID`.
2. Auto-selection: one device → select it (unchanged). Several devices and none selected → select the remembered one if present.
3. When the remembered device appears later while another device was auto-selected (not user-picked this session), switch to it.
4. Fallback selection after a disconnect does not overwrite the preference.

**Files:**
- Modify: `MirrorKit/Core/DeviceManager.swift`
- Test: `MirrorKitTests/DeviceManagerTests.swift`

**Interfaces:**
- Produces: `DeviceManager.init(defaults: UserDefaults = .standard)`, `static let lastSelectedDeviceKey = "lastSelectedDeviceID"`, internal `func register(_ device: ConnectedDevice)` (adds + runs auto-selection), internal `func unregister(deviceID: String)`.
- Consumes: `ConnectedDevice(id:name:modelID:)`, `CaptureState.connected`.

- [ ] **Step 1: Write the failing tests**

Create `MirrorKitTests/DeviceManagerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run `xcodegen generate` then the tests to verify they fail**

Expected: compile errors `extra argument 'defaults' in call`, `has no member 'register'`.

- [ ] **Step 3: Implement in `DeviceManager`**

Add the stored properties and initializer (after `var state: CaptureState = .idle`):

```swift
    /// UserDefaults key holding the `uniqueID` of the iPhone the user picked last.
    static let lastSelectedDeviceKey = "lastSelectedDeviceID"

    @ObservationIgnored
    private let defaults: UserDefaults
    /// True once the user explicitly picked a device in this session; the
    /// remembered device must not override an explicit choice.
    @ObservationIgnored
    private var userPickedThisSession = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
```

Replace `selectDevice(_:)`:

```swift
    /// Selects a device for capture — user intent: remembered across launches.
    func selectDevice(_ device: ConnectedDevice) {
        userPickedThisSession = true
        defaults.set(device.id, forKey: Self.lastSelectedDeviceKey)
        activate(device)
    }

    /// Makes `device` the active one without touching the stored preference.
    private func activate(_ device: ConnectedDevice) {
        selectedDevice = device
        state = .connected(device)
    }
```

Replace `addDevice(from:)`, `handleDeviceDisconnected(_:)` and `autoSelectIfNeeded()`:

```swift
    private func addDevice(from avDevice: AVCaptureDevice) {
        register(ConnectedDevice(
            id: avDevice.uniqueID,
            name: avDevice.localizedName,
            modelID: avDevice.modelID
        ))
    }

    /// Adds a device (ignoring duplicates) and applies the auto-selection rules.
    /// Internal so tests can drive the manager without AVCaptureDevice.
    func register(_ device: ConnectedDevice) {
        guard !devices.contains(where: { $0.id == device.id }) else { return }
        devices.append(device)
        print("[MirrorKit] Device detected: \(device.name) (\(device.modelID))")
        autoSelectIfNeeded()
    }

    private func handleDeviceDisconnected(_ avDevice: AVCaptureDevice) {
        unregister(deviceID: avDevice.uniqueID)
    }

    /// Removes a device; falls back to another connected device or to detecting.
    func unregister(deviceID: String) {
        devices.removeAll { $0.id == deviceID }

        if selectedDevice?.id == deviceID {
            selectedDevice = nil
            if let next = devices.first {
                activate(next)   // fallback, not a user choice
            } else {
                state = .detecting
            }
        }
    }

    private func autoSelectIfNeeded() {
        let remembered = defaults.string(forKey: Self.lastSelectedDeviceKey)

        if selectedDevice == nil {
            if devices.count == 1 {
                activate(devices[0])
            } else if let match = devices.first(where: { $0.id == remembered }) {
                activate(match)
            }
            return
        }

        // Something is already active. If it was picked automatically and the
        // remembered device has just shown up, prefer the remembered one.
        if !userPickedThisSession,
           let remembered,
           selectedDevice?.id != remembered,
           let match = devices.first(where: { $0.id == remembered }) {
            activate(match)
        }
    }
```

Remove the now-unused `autoSelectIfNeeded()` calls in `rescanForDevices()`, `scanExistingDevices()` and `handleDeviceConnected(_:)` — `register(_:)` runs it. Keep the `stopRescanTimer()` call in `handleDeviceConnected`.

- [ ] **Step 4: Run tests to verify they pass**

Run the build + test command. Expected: `Test run with 43 tests in 8 suites passed` (37 from Task 1 + 6).

- [ ] **Step 5: Verify on device**

Two iPhones connected, pick the 17 Pro Max in the toolbar menu, quit, relaunch: the 17 Pro Max is active. Unplug it: the 14 Pro takes over. Re-plug it: it takes over again (no explicit pick this session).

- [ ] **Step 6: Commit**

```bash
git add MirrorKit/Core/DeviceManager.swift MirrorKitTests/DeviceManagerTests.swift MirrorKit.xcodeproj/project.pbxproj
git commit -m "feat: remember the last selected iPhone across launches"
```

---

### Task 6: Release bookkeeping

**Files:**
- Modify: `project.yml` (`MARKETING_VERSION: "1.2.0"`, `CURRENT_PROJECT_VERSION: "10"`)
- Modify: `ROADMAP.md` (move the 1.2 items under "Shipped › 1.2.0")

- [ ] **Step 1: Bump version, regenerate, build**

Edit the two settings in `project.yml`, run `xcodegen generate`, run the build + test command (expected SUCCEEDED).

- [ ] **Step 2: Update ROADMAP.md**

Rename "### 1.1.2 (unreleased)" to "### 1.2.0" and move the six bullets of "Next release — 1.2" under it; leave "Next release" pointing at the 1.3 list.

- [ ] **Step 3: Commit**

```bash
git add project.yml MirrorKit.xcodeproj/project.pbxproj ROADMAP.md
git commit -m "chore: bump version to 1.2.0 (build 10)"
```

Then `Product → Archive` in Xcode → Distribute App → App Store Connect (manual).
