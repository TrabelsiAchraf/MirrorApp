# Wireless Mirroring (v1.1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add wireless iPhone mirroring to MirrorKit v1.1 using native CoreMediaIO Wi-Fi support — same Xcode-like model where the device must have been paired once over USB and "Show this iPhone when on Wi-Fi" enabled in Finder.

**Architecture:** Reuse the existing `AVCaptureSession` pipeline (transport-agnostic at the AVFoundation level). Add a `DeviceTransport` enum + `TransportDetector` that reads `kCMIODevicePropertyTransportType` to label each detected device as `.usb` or `.wifi`. Add a reconnect timer in `DeviceManager` for transient Wi-Fi drops, and a one-shot proactive sheet (`WifiNudgeView`) on first USB connection to teach the user how to enable Wi-Fi sync.

**Tech Stack:** Swift 6.0 strict concurrency, SwiftUI + AppKit, AVFoundation, CoreMediaIO, Swift Testing (new test target), xcodegen, Xcode 16.2, macOS 14.0+.

**Spec:** [`docs/superpowers/specs/2026-04-25-wireless-mirroring-design.md`](../specs/2026-04-25-wireless-mirroring-design.md)

---

## File Map

**Created (production):**
- `MirrorKit/Models/DeviceTransport.swift`
- `MirrorKit/Utils/TransportDetector.swift`
- `MirrorKit/Utils/WifiNudgeManager.swift`
- `MirrorKit/UI/WifiNudgeView.swift`

**Modified (production):**
- `MirrorKit/Models/ConnectedDevice.swift` — add `transport: DeviceTransport`
- `MirrorKit/Models/CaptureState.swift` — add `.reconnecting(ConnectedDevice, attempt: Int)` case
- `MirrorKit/Core/DeviceManager.swift` — wire `TransportDetector` + `WifiNudgeManager` + reconnect timer + updated empty-state message
- `MirrorKit/UI/DevicePickerView.swift` — transport icon per row
- `MirrorKit/UI/FloatingToolbar.swift` — transport badge next to device name
- `MirrorKit/UI/MirrorContentView.swift` — reconnecting overlay + nudge sheet wiring + new state in switch
- `project.yml` — add `MirrorKitTests` target
- `MirrorKit/Info.plist` — bump build number at the end (Task 16)

**Created (tests):**
- `MirrorKitTests/TransportMappingTests.swift`
- `MirrorKitTests/WifiNudgeManagerTests.swift`
- `MirrorKitTests/CaptureStateTests.swift`

**Created (docs):**
- `docs/superpowers/specs/2026-04-25-wireless-mirroring-spike-results.md`
- `docs/superpowers/specs/2026-04-25-wireless-mirroring-test-plan.md`

**Untouched:** `CaptureEngine.swift`, `OnboardingView.swift`, `DeviceFrameProvider.swift`, `MirrorKit.entitlements`, `AppDelegate.swift`, `MirrorKitApp.swift`.

---

## Phase A — Validation spike (blocking)

The entire design rests on the assumption that Wi-Fi paired iPhones surface via `AVCaptureDevice.DiscoverySession([.external])` and that `kCMIODevicePropertyTransportType` returns a distinguishable fourCC for USB vs Wi-Fi. Validate before writing any production code.

### Task 0: Spike — Transport detection on a physical iPhone

**Files:**
- Create: `docs/superpowers/specs/2026-04-25-wireless-mirroring-spike-results.md`
- Temp-modify: `MirrorKit/Core/DeviceManager.swift` (verbose logging, reverted at end)

**Prerequisites:** A physical iPhone, paired once over USB to this Mac, with "Show this iPhone when on Wi-Fi" checked in Finder. Both devices on the same Wi-Fi network.

- [ ] **Step 1: Create spike branch**

```bash
cd /Users/a.trabelsi/Workspace/Perso/MirrorApp
git checkout -b spike/wireless-transport-detection
```

- [ ] **Step 2: Add temporary logging in `DeviceManager.scanExistingDevices()` (around line 177)**

Insert the `print` call below right after the existing `print("[MirrorKit]   → ...")` line in the `for avDevice in discovery.devices` loop:

```swift
print("[SPIKE]      transportType fourCC = \(Self.spikeReadTransportType(for: avDevice))")
```

- [ ] **Step 3: Add the spike helper at the bottom of `DeviceManager`**

Just before the closing `}` of the class, add:

```swift
    // MARK: - SPIKE (REMOVE BEFORE COMMIT TO MAIN)

    /// Reads kCMIODevicePropertyTransportType for an AVCaptureDevice and returns
    /// the raw fourCC as a hex string + ASCII representation, e.g. "0x75736220 ('usb ')".
    static func spikeReadTransportType(for device: AVCaptureDevice) -> String {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyTransportType),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        // Find the CMIOObjectID matching this AVCaptureDevice.uniqueID
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &devicesAddress, 0, nil, &dataSize
        ) == 0 else { return "ERR: GetPropertyDataSize failed" }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &devicesAddress, 0, nil, dataSize, &dataUsed, &ids
        ) == 0 else { return "ERR: GetPropertyData (devices) failed" }

        var uidAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        for cmioID in ids {
            var cfStringRef: Unmanaged<CFString>? = nil
            var size = UInt32(MemoryLayout<CFString?>.size)
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                cmioID, &uidAddress, 0, nil, size, &used, &cfStringRef
            )
            guard status == 0, let cfString = cfStringRef?.takeRetainedValue() else { continue }
            if (cfString as String) == device.uniqueID {
                // Match — read transport type
                var fourCC: UInt32 = 0
                var ttSize = UInt32(MemoryLayout<UInt32>.size)
                var ttUsed: UInt32 = 0
                let ttStatus = CMIOObjectGetPropertyData(
                    cmioID, &address, 0, nil, ttSize, &ttUsed, &fourCC
                )
                guard ttStatus == 0 else { return "ERR: read transportType failed (status=\(ttStatus))" }
                return formatFourCC(fourCC)
            }
        }
        return "ERR: no matching CMIOObjectID for uniqueID \(device.uniqueID)"
    }

    private static func formatFourCC(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        let ascii = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "?"
        return String(format: "0x%08X ('%@')", value, ascii)
    }
```

- [ ] **Step 4: Build the app**

```bash
cd /Users/a.trabelsi/Workspace/Perso/MirrorApp
xcodegen generate
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`. If the import of `CoreMediaIO` is missing in `DeviceManager.swift`, it should already be present from the existing code (line 2). If not, add `import CoreMediaIO`.

- [ ] **Step 5: Run the app with iPhone connected via USB**

```bash
open ~/Library/Developer/Xcode/DerivedData/MirrorKit-*/Build/Products/Debug/MirrorKit.app
```

Watch the console (Console.app, filter by `[SPIKE]`). Expected output: a line like
```
[SPIKE]      transportType fourCC = 0x75736220 ('usb ')
```
Record the exact value.

- [ ] **Step 6: Disconnect USB, ensure "Show this iPhone when on Wi-Fi" is checked in Finder, ensure both devices are on the same Wi-Fi**

Wait until the iPhone re-appears in MirrorKit (could take 5-30 seconds). Watch the console for the `[SPIKE]` line.

Record the fourCC value for the Wi-Fi case. Likely candidates: `'wlan'`, `'wifi'`, `'netw'`, `'airp'`, or `'unkn'`.

- [ ] **Step 7: Test that capture actually works over Wi-Fi**

Click the iPhone in MirrorKit's picker, click "Start Mirroring". Verify frames are displayed. Note subjective latency.

- [ ] **Step 8: Document spike results**

Create `docs/superpowers/specs/2026-04-25-wireless-mirroring-spike-results.md` with:

```markdown
# Wireless Mirroring Spike Results

**Date:** YYYY-MM-DD
**Tested device:** iPhone <model> running iOS <version>
**Mac:** macOS <version>

## Observed fourCC values

- USB connection: `0x________ ('____')`
- Wi-Fi connection: `0x________ ('____')`

## Capture works over Wi-Fi: YES / NO

If YES:
- Subjective latency: __ ms (estimate)
- Framerate stable: YES / NO
- Resolution detected: ____ × ____

## AVCaptureSession behavior

- Wi-Fi device appears in `DiscoverySession([.external])`: YES / NO
- `hasMediaType(.muxed)`: YES / NO
- `AVCaptureDeviceInput(device:)` succeeds: YES / NO
- `startRunning()` produces frames: YES / NO

## Go/no-go decision

- **GO** if: Wi-Fi capture works AND fourCC distinguishes USB from Wi-Fi.
- **NO-GO** if: any of the above fails. Halt implementation, return to brainstorming.

Decision: ____
Notes: ____
```

Fill in the actual values from steps 5-7.

- [ ] **Step 9: Revert spike code (do not commit it to main)**

```bash
git checkout MirrorKit/Core/DeviceManager.swift
```

- [ ] **Step 10: Commit only the spike-results document on the spike branch, then merge / cherry-pick to main**

```bash
git add docs/superpowers/specs/2026-04-25-wireless-mirroring-spike-results.md
git commit -m "docs: spike results for wireless transport detection"
git checkout main
git cherry-pick spike/wireless-transport-detection
git branch -d spike/wireless-transport-detection
```

- [ ] **Step 11: Update the design spec with confirmed fourCC values**

Edit `docs/superpowers/specs/2026-04-25-wireless-mirroring-design.md` section 6.1: replace the placeholder fourCC constants in the `DeviceTransport.init(fourCC:)` snippet with the values observed in the spike. Commit:

```bash
git add docs/superpowers/specs/2026-04-25-wireless-mirroring-design.md
git commit -m "docs: lock fourCC constants from spike results"
```

**Gate:** if the spike result is no-go, **stop here**. The implementation phase below is invalidated and a new design is needed.

---

## Phase B — Test target setup

### Task 1: Add `MirrorKitTests` target via xcodegen

**Files:**
- Modify: `project.yml`
- Create: `MirrorKitTests/SmokeTests.swift`

- [ ] **Step 1: Add the test target to `project.yml`**

Edit `project.yml`. After the `MirrorKit:` target block (ends at the line containing `SWIFT_EMIT_LOC_STRINGS: YES`), append:

```yaml
  MirrorKitTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: MirrorKitTests
    dependencies:
      - target: MirrorKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.achraftrabelsi.MirrorKitTests
        BUNDLE_LOADER: $(TEST_HOST)
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/MirrorKit.app/Contents/MacOS/MirrorKit
        GENERATE_INFOPLIST_FILE: YES
        SWIFT_VERSION: "6.0"
        MACOSX_DEPLOYMENT_TARGET: "14.0"
```

- [ ] **Step 2: Create the smoke test file**

Create `MirrorKitTests/SmokeTests.swift`:

```swift
import Testing
@testable import MirrorKit

@Suite("Smoke")
struct SmokeTests {
    @Test func testTargetCompilesAndRuns() {
        #expect(true)
    }
}
```

- [ ] **Step 3: Regenerate the Xcode project**

```bash
cd /Users/a.trabelsi/Workspace/Perso/MirrorApp
xcodegen generate
```

Expected: no errors. The `MirrorKit.xcodeproj` now contains a `MirrorKitTests` target.

- [ ] **Step 4: Run the smoke test**

```bash
xcodebuild test \
  -project MirrorKit.xcodeproj \
  -scheme MirrorKit \
  -destination 'platform=macOS' \
  -only-testing:MirrorKitTests/SmokeTests/testTargetCompilesAndRuns \
  2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **` and the test count includes 1 passed.

If the scheme `MirrorKit` does not include the test target, run:

```bash
xcodebuild test -project MirrorKit.xcodeproj -scheme MirrorKitTests -destination 'platform=macOS' 2>&1 | tail -30
```

If neither works, the scheme needs an explicit test action — add to `project.yml`:

```yaml
schemes:
  MirrorKit:
    build:
      targets:
        MirrorKit: all
        MirrorKitTests: [test]
    test:
      targets:
        - MirrorKitTests
```

Re-run `xcodegen generate` and retry.

- [ ] **Step 5: Commit**

```bash
git add project.yml MirrorKitTests/SmokeTests.swift MirrorKit.xcodeproj
git commit -m "chore: add MirrorKitTests target with Swift Testing"
```

---

## Phase C — Pure-logic models (TDD)

### Task 2: `DeviceTransport` model

**Files:**
- Create: `MirrorKit/Models/DeviceTransport.swift`
- Create: `MirrorKitTests/TransportMappingTests.swift`

> **Note:** Replace the fourCC literals below (`0x77696669`, `0x776C616E`) with the actual Wi-Fi fourCC observed in Task 0 if it differs. The USB constant `0x75736220` is fixed by Apple's `kIOAudioDeviceTransportTypeUSB`.

- [ ] **Step 1: Write the failing test**

Create `MirrorKitTests/TransportMappingTests.swift`:

```swift
import Testing
@testable import MirrorKit

@Suite("DeviceTransport.init(fourCC:)")
struct TransportMappingTests {
    @Test("Maps USB fourCC 'usb ' to .usb")
    func mapsUSBCode() {
        #expect(DeviceTransport(fourCC: 0x75736220) == .usb)
    }

    @Test("Maps Wi-Fi fourCC to .wifi")
    func mapsWifiCode() {
        // Update these literals if the spike found different values.
        #expect(DeviceTransport(fourCC: 0x77696669) == .wifi)  // 'wifi'
        #expect(DeviceTransport(fourCC: 0x776C616E) == .wifi)  // 'wlan'
    }

    @Test("Unknown fourCC defaults to .usb (safe fallback)")
    func unknownDefaultsToUSB() {
        #expect(DeviceTransport(fourCC: 0x00000000) == .usb)
        #expect(DeviceTransport(fourCC: 0xDEADBEEF) == .usb)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project MirrorKit.xcodeproj -scheme MirrorKit \
  -destination 'platform=macOS' \
  -only-testing:MirrorKitTests/TransportMappingTests \
  2>&1 | tail -30
```

Expected: build error — `cannot find 'DeviceTransport' in scope`.

- [ ] **Step 3: Create `DeviceTransport.swift`**

Create `MirrorKit/Models/DeviceTransport.swift`:

```swift
import Foundation

/// Connection transport for a detected iPhone. Used to surface the right icon
/// in the picker/toolbar and to gate features (e.g. reconnect overlay only for Wi-Fi).
enum DeviceTransport: Equatable {
    case usb
    case wifi

    /// SF Symbol used in the picker row and the toolbar badge.
    var iconName: String {
        switch self {
        case .usb:  return "cable.connector"
        case .wifi: return "wifi"
        }
    }

    /// Short label shown next to the icon in the toolbar.
    var displayName: String {
        switch self {
        case .usb:  return "USB"
        case .wifi: return "Wi-Fi"
        }
    }
}

extension DeviceTransport {
    /// Maps a CoreMediaIO `kCMIODevicePropertyTransportType` fourCC value to a transport.
    /// Unknown values fall back to `.usb` (safe default — preserves v1.0 behavior).
    init(fourCC: UInt32) {
        switch fourCC {
        case 0x75736220:                        // 'usb '
            self = .usb
        case 0x77696669, 0x776C616E:            // 'wifi', 'wlan' — adjust if spike found other values
            self = .wifi
        default:
            self = .usb
        }
    }
}
```

- [ ] **Step 4: Re-add the file to the Xcode project**

```bash
xcodegen generate
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -project MirrorKit.xcodeproj -scheme MirrorKit \
  -destination 'platform=macOS' \
  -only-testing:MirrorKitTests/TransportMappingTests \
  2>&1 | tail -30
```

Expected: all 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add MirrorKit/Models/DeviceTransport.swift \
        MirrorKitTests/TransportMappingTests.swift \
        MirrorKit.xcodeproj
git commit -m "feat: add DeviceTransport enum with fourCC mapping"
```

---

### Task 3: `ConnectedDevice` gains a `transport` field

**Files:**
- Modify: `MirrorKit/Models/ConnectedDevice.swift`
- Modify: `MirrorKit/Core/DeviceManager.swift` (one line, temporary `.usb` literal)

- [ ] **Step 1: Modify `ConnectedDevice.swift`**

Replace the entire contents of `MirrorKit/Models/ConnectedDevice.swift` with:

```swift
import Foundation
import CoreGraphics

/// Represents an iPhone detected through CoreMediaIO (via USB or Wi-Fi pairing).
struct ConnectedDevice: Identifiable, Hashable {
    /// Unique device identifier (AVCaptureDevice.uniqueID).
    let id: String
    /// Localized device name (e.g. "Achraf's iPhone").
    let name: String
    /// Model identifier (e.g. "iPhone15,2").
    let modelID: String
    /// USB or Wi-Fi — set once at construction time, never mutated.
    let transport: DeviceTransport
    /// Native video stream resolution (set after capture starts).
    var resolution: CGSize?
}
```

- [ ] **Step 2: Patch `DeviceManager.addDevice(from:)` with a temporary `.usb` placeholder**

In `MirrorKit/Core/DeviceManager.swift`, find the `addDevice(from avDevice:)` method (around line 223). Replace its body with:

```swift
    private func addDevice(from avDevice: AVCaptureDevice) {
        // Avoid duplicates
        guard !devices.contains(where: { $0.id == avDevice.uniqueID }) else { return }

        let device = ConnectedDevice(
            id: avDevice.uniqueID,
            name: avDevice.localizedName,
            modelID: avDevice.modelID,
            transport: .usb,  // TEMP — replaced by TransportDetector in Task 5
            resolution: nil
        )
        devices.append(device)
        print("[MirrorKit] Device detected: \(device.name) (\(device.modelID))")
    }
```

- [ ] **Step 3: Build to verify nothing else broke**

```bash
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`. If any code constructs `ConnectedDevice` with the old initializer, fix it (search: `grep -rn "ConnectedDevice(" MirrorKit/`).

- [ ] **Step 4: Commit**

```bash
git add MirrorKit/Models/ConnectedDevice.swift MirrorKit/Core/DeviceManager.swift
git commit -m "feat: add transport field to ConnectedDevice (USB placeholder)"
```

---

### Task 4: `CaptureState.reconnecting` case (TDD)

**Files:**
- Modify: `MirrorKit/Models/CaptureState.swift`
- Create: `MirrorKitTests/CaptureStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MirrorKitTests/CaptureStateTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import MirrorKit

@Suite("CaptureState.reconnecting equality")
struct CaptureStateTests {
    private func device(_ id: String) -> ConnectedDevice {
        ConnectedDevice(id: id, name: "iPhone", modelID: "iPhone15,2", transport: .wifi)
    }

    @Test("Same device + same attempt are equal")
    func sameDeviceSameAttemptEqual() {
        let d = device("abc")
        #expect(CaptureState.reconnecting(d, attempt: 3) == CaptureState.reconnecting(d, attempt: 3))
    }

    @Test("Same device + different attempts are not equal")
    func sameDeviceDifferentAttemptsNotEqual() {
        let d = device("abc")
        #expect(CaptureState.reconnecting(d, attempt: 1) != CaptureState.reconnecting(d, attempt: 2))
    }

    @Test("Different devices are not equal")
    func differentDevicesNotEqual() {
        #expect(CaptureState.reconnecting(device("a"), attempt: 1)
                != CaptureState.reconnecting(device("b"), attempt: 1))
    }

    @Test("Reconnecting is not equal to capturing")
    func reconnectingNotCapturing() {
        #expect(CaptureState.reconnecting(device("a"), attempt: 1) != CaptureState.capturing)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project MirrorKit.xcodeproj -scheme MirrorKit \
  -destination 'platform=macOS' \
  -only-testing:MirrorKitTests/CaptureStateTests \
  2>&1 | tail -30
```

Expected: build error — `'reconnecting' is not a member of 'CaptureState'`.

- [ ] **Step 3: Add the new case + Equatable handling**

Replace the contents of `MirrorKit/Models/CaptureState.swift` with:

```swift
import Foundation

/// Possible states of the capture pipeline
enum CaptureState: Equatable {
    /// No activity — waiting for a device
    case idle
    /// Searching for devices
    case detecting
    /// Device connected, ready to capture
    case connected(ConnectedDevice)
    /// Capture in progress — video stream active
    case capturing
    /// Wi-Fi connection dropped during capture — auto-retry in progress
    case reconnecting(ConnectedDevice, attempt: Int)
    /// Error encountered
    case error(String)

    static func == (lhs: CaptureState, rhs: CaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.detecting, .detecting), (.capturing, .capturing):
            return true
        case let (.connected(a), .connected(b)):
            return a.id == b.id
        case let (.reconnecting(a, n1), .reconnecting(b, n2)):
            return a.id == b.id && n1 == n2
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Regenerate and run tests**

```bash
xcodegen generate
xcodebuild test -project MirrorKit.xcodeproj -scheme MirrorKit \
  -destination 'platform=macOS' \
  -only-testing:MirrorKitTests/CaptureStateTests \
  2>&1 | tail -30
```

Expected: all 4 tests pass.

- [ ] **Step 5: Build the full app to ensure nothing broke**

The exhaustive switch in `MirrorContentView.mainContent` (around line 183) does not yet handle `.reconnecting`. Swift 6 strict mode will warn or error on a non-exhaustive switch.

```bash
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -50
```

If the build fails on the switch, add a temporary placeholder branch in `MirrorContentView.mainContent` (line ~183, inside the `switch deviceManager.state {`):

```swift
            case .reconnecting:
                // Real overlay added in Task 12 — placeholder so the switch is exhaustive.
                detectingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
```

Re-run the build. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MirrorKit/Models/CaptureState.swift \
        MirrorKitTests/CaptureStateTests.swift \
        MirrorKit/UI/MirrorContentView.swift \
        MirrorKit.xcodeproj
git commit -m "feat: add CaptureState.reconnecting case"
```

---

## Phase D — Utilities

### Task 5: `TransportDetector` (CoreMediaIO lookup)

**Files:**
- Create: `MirrorKit/Utils/TransportDetector.swift`
- Modify: `MirrorKit/Core/DeviceManager.swift` (replace `.usb` placeholder)

No unit tests — this directly calls CoreMediaIO and is integration-only. Validation is via the spike + manual test plan.

- [ ] **Step 1: Create `TransportDetector.swift`**

Create `MirrorKit/Utils/TransportDetector.swift`:

```swift
import Foundation
import AVFoundation
import CoreMediaIO

/// Detects whether an `AVCaptureDevice` is connected via USB or Wi-Fi by reading
/// `kCMIODevicePropertyTransportType` on the matching `CMIOObjectID`. Falls back
/// to `.usb` if anything fails — that preserves v1.0 behavior.
enum TransportDetector {
    static func detect(_ device: AVCaptureDevice) -> DeviceTransport {
        guard let cmioID = findCMIOObjectID(matching: device.uniqueID) else {
            return .usb
        }
        guard let fourCC = readTransportType(cmioID) else {
            return .usb
        }
        return DeviceTransport(fourCC: fourCC)
    }

    // MARK: - Private

    /// Enumerates all CMIO devices and returns the one whose
    /// `kCMIODevicePropertyDeviceUID` matches the given AVFoundation uniqueID.
    private static func findCMIOObjectID(matching uniqueID: String) -> CMIOObjectID? {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &devicesAddress, 0, nil, &dataSize
        ) == 0, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &devicesAddress, 0, nil,
            dataSize, &dataUsed, &ids
        ) == 0 else { return nil }

        var uidAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        for cmioID in ids {
            var cfStringRef: Unmanaged<CFString>? = nil
            var size = UInt32(MemoryLayout<CFString?>.size)
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                cmioID, &uidAddress, 0, nil, size, &used, &cfStringRef
            )
            guard status == 0, let cfString = cfStringRef?.takeRetainedValue() else { continue }
            if (cfString as String) == uniqueID {
                return cmioID
            }
        }
        return nil
    }

    private static func readTransportType(_ cmioID: CMIOObjectID) -> UInt32? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyTransportType),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var fourCC: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            cmioID, &address, 0, nil, size, &used, &fourCC
        )
        guard status == 0 else { return nil }
        return fourCC
    }
}
```

- [ ] **Step 2: Wire it into `DeviceManager.addDevice(from:)`**

Replace the body of `addDevice(from:)` (the version with the `.usb` placeholder from Task 3) with:

```swift
    private func addDevice(from avDevice: AVCaptureDevice) {
        // Avoid duplicates
        guard !devices.contains(where: { $0.id == avDevice.uniqueID }) else { return }

        let transport = TransportDetector.detect(avDevice)
        let device = ConnectedDevice(
            id: avDevice.uniqueID,
            name: avDevice.localizedName,
            modelID: avDevice.modelID,
            transport: transport,
            resolution: nil
        )
        devices.append(device)
        print("[MirrorKit] Device detected: \(device.name) (\(device.modelID)) — transport=\(transport.displayName)")
    }
```

- [ ] **Step 3: Regenerate and build**

```bash
xcodegen generate
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke check (USB only — Wi-Fi covered in test plan)**

```bash
open ~/Library/Developer/Xcode/DerivedData/MirrorKit-*/Build/Products/Debug/MirrorKit.app
```

Connect an iPhone via USB. In Console.app (filter `[MirrorKit]`), expect a line like:
```
[MirrorKit] Device detected: iPhone d'Achraf (iPhone15,2) — transport=USB
```

- [ ] **Step 5: Commit**

```bash
git add MirrorKit/Utils/TransportDetector.swift \
        MirrorKit/Core/DeviceManager.swift \
        MirrorKit.xcodeproj
git commit -m "feat: TransportDetector reads kCMIODevicePropertyTransportType"
```

---

### Task 6: `WifiNudgeManager` (TDD)

**Files:**
- Create: `MirrorKit/Utils/WifiNudgeManager.swift`
- Create: `MirrorKitTests/WifiNudgeManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `MirrorKitTests/WifiNudgeManagerTests.swift`:

```swift
import Testing
import Foundation
@testable import MirrorKit

@Suite("WifiNudgeManager")
@MainActor
struct WifiNudgeManagerTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.WifiNudgeManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func device(_ id: String, transport: DeviceTransport = .usb) -> ConnectedDevice {
        ConnectedDevice(id: id, name: "iPhone", modelID: "iPhone15,2", transport: transport)
    }

    @Test("First call returns true for an unseen device")
    func firstCallReturnsTrue() {
        let manager = WifiNudgeManager(defaults: freshDefaults())
        #expect(manager.shouldShowNudge(for: device("dev-1")))
    }

    @Test("After markShown the same device returns false")
    func markShownPreventsRepeat() {
        let manager = WifiNudgeManager(defaults: freshDefaults())
        let dev = device("dev-1")
        manager.markShown(for: dev)
        #expect(!manager.shouldShowNudge(for: dev))
    }

    @Test("Different devices are independent")
    func differentDevicesAreIndependent() {
        let manager = WifiNudgeManager(defaults: freshDefaults())
        manager.markShown(for: device("dev-1"))
        #expect(manager.shouldShowNudge(for: device("dev-2")))
    }

    @Test("Wi-Fi devices never trigger the nudge")
    func wifiDevicesAreSkipped() {
        let manager = WifiNudgeManager(defaults: freshDefaults())
        let wifiDev = device("dev-wifi", transport: .wifi)
        #expect(!manager.shouldShowNudge(for: wifiDev))
    }

    @Test("Persistence across instances")
    func persistsAcrossInstances() {
        let defaults = freshDefaults()
        let m1 = WifiNudgeManager(defaults: defaults)
        m1.markShown(for: device("dev-1"))
        let m2 = WifiNudgeManager(defaults: defaults)
        #expect(!m2.shouldShowNudge(for: device("dev-1")))
    }
}
```

- [ ] **Step 2: Run to verify the build error**

```bash
xcodebuild test -project MirrorKit.xcodeproj -scheme MirrorKit \
  -destination 'platform=macOS' \
  -only-testing:MirrorKitTests/WifiNudgeManagerTests \
  2>&1 | tail -30
```

Expected: `cannot find 'WifiNudgeManager' in scope`.

- [ ] **Step 3: Create `WifiNudgeManager.swift`**

Create `MirrorKit/Utils/WifiNudgeManager.swift`:

```swift
import Foundation

/// Tracks whether the "enable Wi-Fi sync" nudge has been shown for each device,
/// and exposes a `pendingNudgeDevice` signal that the UI binds to.
///
/// Triggered when an iPhone connects via USB for the first time. Wi-Fi devices
/// never trigger the nudge — the user has already discovered the feature.
///
/// Uses `@Observable` (not `ObservableObject`) so it composes cleanly with
/// `DeviceManager`, which is also `@Observable`.
@MainActor
@Observable
final class WifiNudgeManager {
    var pendingNudgeDevice: ConnectedDevice?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keyPrefix = "hasShownWifiNudgeForDevice."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True if the nudge sheet should be presented for this device.
    func shouldShowNudge(for device: ConnectedDevice) -> Bool {
        guard device.transport == .usb else { return false }
        return !defaults.bool(forKey: key(for: device))
    }

    /// Records that the nudge has been shown (or dismissed). Subsequent
    /// `shouldShowNudge` calls for the same device return false.
    func markShown(for device: ConnectedDevice) {
        defaults.set(true, forKey: key(for: device))
    }

    /// Schedules the nudge sheet to appear after a 3-second delay so the user
    /// sees mirroring start successfully first.
    func scheduleNudge(for device: ConnectedDevice) {
        guard shouldShowNudge(for: device) else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            // Re-check in case the user dismissed it via another path
            if self.shouldShowNudge(for: device) {
                self.pendingNudgeDevice = device
            }
        }
    }

    /// Called by the view when the sheet is dismissed.
    func dismissNudge() {
        if let device = pendingNudgeDevice {
            markShown(for: device)
        }
        pendingNudgeDevice = nil
    }

    private func key(for device: ConnectedDevice) -> String {
        keyPrefix + device.id
    }
}
```

- [ ] **Step 4: Regenerate and run tests**

```bash
xcodegen generate
xcodebuild test -project MirrorKit.xcodeproj -scheme MirrorKit \
  -destination 'platform=macOS' \
  -only-testing:MirrorKitTests/WifiNudgeManagerTests \
  2>&1 | tail -30
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add MirrorKit/Utils/WifiNudgeManager.swift \
        MirrorKitTests/WifiNudgeManagerTests.swift \
        MirrorKit.xcodeproj
git commit -m "feat: add WifiNudgeManager with per-device UserDefaults flag"
```

---

## Phase E — DeviceManager wiring

### Task 7: Update no-device empty-state error message

**Files:**
- Modify: `MirrorKit/Core/DeviceManager.swift` (line ~156)

- [ ] **Step 1: Replace the error string**

In `MirrorKit/Core/DeviceManager.swift`, find the line (around 156):

```swift
            state = .error("No iPhone detected.\n\n• Make sure your iPhone is connected via USB\n• Unlock your iPhone and tap \"Trust This Computer\"\n• Try a different USB cable or port")
```

Replace it with:

```swift
            state = .error("""
                No iPhone detected.
                
                USB:
                • Connect your iPhone via USB
                • Unlock your iPhone and tap "Trust This Computer"
                • Try a different cable or port
                
                Wi-Fi:
                • Make sure your iPhone has been paired (connect once via USB first)
                • Open Finder, select your iPhone, and check
                  "Show this iPhone when on Wi-Fi"
                • Ensure both devices are on the same Wi-Fi network
                """)
```

- [ ] **Step 2: Build to confirm**

```bash
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MirrorKit/Core/DeviceManager.swift
git commit -m "feat: update no-device error message with Wi-Fi guidance"
```

---

### Task 8: Reconnect timer + state transitions in `DeviceManager`

**Files:**
- Modify: `MirrorKit/Core/DeviceManager.swift`

The reconnect logic is integration-coupled (Timer + AVFoundation notifications) — no unit tests; manual validation via the test plan in Task 14.

- [ ] **Step 1: Add the reconnect-related properties**

In `DeviceManager`, after the `rescanCount` property declaration (around line 31), add:

```swift
    @ObservationIgnored
    nonisolated(unsafe) private var reconnectTimer: Timer?
    @ObservationIgnored
    nonisolated(unsafe) private var reconnectAttempt: Int = 0

    private static let reconnectInterval: TimeInterval = 1.0
    private static let maxReconnectAttempts = 10
```

- [ ] **Step 2: Update `deinit` to invalidate the new timer**

In `deinit` (around line 33-43), after `rescanTimer?.invalidate()` add:

```swift
        reconnectTimer?.invalidate()
```

- [ ] **Step 3: Update `stopDiscovery()` to also stop reconnection**

Find `stopDiscovery()` (around line 110). After `stopRescanTimer()` add:

```swift
        stopReconnectTimer()
```

- [ ] **Step 4: Modify `handleDeviceDisconnected` to branch on transport**

Replace the existing `handleDeviceDisconnected(_:)` (around line 208) with:

```swift
    private func handleDeviceDisconnected(_ avDevice: AVCaptureDevice) {
        let deviceID = avDevice.uniqueID

        // If we're capturing this exact Wi-Fi device, attempt auto-reconnect
        // instead of dropping the session immediately.
        if case .capturing = state,
           selectedDevice?.id == deviceID,
           selectedDevice?.transport == .wifi {
            beginReconnect()
            return
        }

        devices.removeAll { $0.id == deviceID }

        if selectedDevice?.id == deviceID {
            selectedDevice = nil
            // Select the next available device or fall back to detecting
            if let next = devices.first {
                selectDevice(next)
            } else {
                state = .detecting
            }
        }
    }
```

- [ ] **Step 5: Add reconnect helpers at the bottom of `DeviceManager`**

Just before the closing brace of the class, add:

```swift
    // MARK: - Reconnect (Wi-Fi only)

    private func beginReconnect() {
        guard let device = selectedDevice else { return }
        reconnectAttempt = 1
        state = .reconnecting(device, attempt: reconnectAttempt)
        reconnectTimer = Timer.scheduledTimer(
            withTimeInterval: Self.reconnectInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickReconnect() }
        }
    }

    private func tickReconnect() {
        guard case .reconnecting(let device, _) = state else {
            stopReconnectTimer()
            return
        }

        // Try to find the device again
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: nil,
            position: .unspecified
        )
        if let avDevice = discovery.devices.first(where: {
            $0.uniqueID == device.id && Self.isIOSScreenCapture($0)
        }) {
            // Recovered — re-add and re-select. The view layer's onChange
            // observers will trigger a fresh startCapture from connectedView's
            // onAppear path.
            stopReconnectTimer()
            handleDeviceConnected(avDevice)
            selectDevice(device)
            return
        }

        reconnectAttempt += 1
        if reconnectAttempt > Self.maxReconnectAttempts {
            stopReconnectTimer()
            devices.removeAll { $0.id == device.id }
            selectedDevice = nil
            state = .error("Wi-Fi connection lost.\n\nMake sure your iPhone is on the same Wi-Fi network as this Mac.")
        } else {
            state = .reconnecting(device, attempt: reconnectAttempt)
        }
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempt = 0
    }

    /// Called by the UI when the user taps "Cancel" in the reconnecting overlay.
    func cancelReconnect() {
        guard case .reconnecting(let device, _) = state else { return }
        stopReconnectTimer()
        devices.removeAll { $0.id == device.id }
        selectedDevice = nil
        state = .detecting
    }
```

- [ ] **Step 6: Build**

```bash
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add MirrorKit/Core/DeviceManager.swift
git commit -m "feat: auto-reconnect Wi-Fi devices for up to 10s on disconnect"
```

---

### Task 9: Wire `WifiNudgeManager` into `DeviceManager`

**Files:**
- Modify: `MirrorKit/Core/DeviceManager.swift`

- [ ] **Step 1: Add the manager as a property**

In `DeviceManager` (after `var state: CaptureState = .idle`, around line 16), add:

```swift
    /// Tracks the "enable Wi-Fi sync" nudge state across launches.
    let wifiNudgeManager = WifiNudgeManager()
```

- [ ] **Step 2: Trigger the nudge in `addDevice(from:)`**

In `addDevice(from:)` (the version from Task 5), append after the `print(...)` line:

```swift
        if device.transport == .usb {
            wifiNudgeManager.scheduleNudge(for: device)
        }
```

So the full method body becomes:

```swift
    private func addDevice(from avDevice: AVCaptureDevice) {
        // Avoid duplicates
        guard !devices.contains(where: { $0.id == avDevice.uniqueID }) else { return }

        let transport = TransportDetector.detect(avDevice)
        let device = ConnectedDevice(
            id: avDevice.uniqueID,
            name: avDevice.localizedName,
            modelID: avDevice.modelID,
            transport: transport,
            resolution: nil
        )
        devices.append(device)
        print("[MirrorKit] Device detected: \(device.name) (\(device.modelID)) — transport=\(transport.displayName)")

        if device.transport == .usb {
            wifiNudgeManager.scheduleNudge(for: device)
        }
    }
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MirrorKit/Core/DeviceManager.swift
git commit -m "feat: schedule Wi-Fi nudge on first USB connection"
```

---

## Phase F — UI

### Task 10: Transport icon in `DevicePickerView`

**Files:**
- Modify: `MirrorKit/UI/DevicePickerView.swift`

- [ ] **Step 1: Replace the `iphone` icon with the transport icon**

In `MirrorKit/UI/DevicePickerView.swift`, find (line 18):

```swift
                        Image(systemName: "iphone")
                            .font(.title3)
```

Replace with:

```swift
                        Image(systemName: "iphone")
                            .font(.title3)

                        Image(systemName: device.transport.iconName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MirrorKit/UI/DevicePickerView.swift
git commit -m "feat: show transport icon next to each device in picker"
```

---

### Task 11: Transport badge in `FloatingToolbar`

**Files:**
- Modify: `MirrorKit/UI/FloatingToolbar.swift`

- [ ] **Step 1: Replace the device picker label block to include the transport badge**

In `FloatingToolbar.swift`, find the `VStack(alignment: .leading, spacing: 2)` block inside the device picker `Button` (around line 50-59):

```swift
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDevice?.name ?? "No device")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(modelName)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
```

Replace with:

```swift
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(selectedDevice?.name ?? "No device")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if let transport = selectedDevice?.transport {
                                HStack(spacing: 3) {
                                    Image(systemName: transport.iconName)
                                        .font(.system(size: 9, weight: .semibold))
                                    Text(transport.displayName)
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.white.opacity(0.12))
                                )
                            }
                        }
                        Text(modelName)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MirrorKit/UI/FloatingToolbar.swift
git commit -m "feat: transport badge next to device name in floating toolbar"
```

---

### Task 12: Reconnecting overlay in `MirrorContentView`

**Files:**
- Modify: `MirrorKit/UI/MirrorContentView.swift`

- [ ] **Step 1: Replace the placeholder `.reconnecting` branch with a real overlay**

In `MirrorContentView.swift`, in the `mainContent` switch (around line 183), find the temporary placeholder added in Task 4:

```swift
            case .reconnecting:
                // Real overlay added in Task 12 — placeholder so the switch is exhaustive.
                detectingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
```

Replace with:

```swift
            case .reconnecting(_, let attempt):
                reconnectingView(attempt: attempt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
```

- [ ] **Step 2: Add the `reconnectingView` helper**

In `MirrorContentView.swift`, find the `errorView(message:)` helper (around line 463) and add the new helper just above it:

```swift
    private func reconnectingView(attempt: Int) -> some View {
        ZStack {
            // Last frozen frame in the background (the FrameRenderer keeps the last decoded frame)
            FrameRenderer(displayLayer: displayLayer)
                .blur(radius: 12)

            Color.black.opacity(0.55)

            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)

                Text("Reconnecting…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text("Attempt \(attempt) of 10")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Button("Cancel") {
                    deviceManager.cancelReconnect()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
                .foregroundColor(.white)
                .padding(.top, 4)
            }
        }
        .transition(.opacity)
    }
```

- [ ] **Step 3: Update the `onChange(of: deviceManager.state)` handler so reconnect doesn't tear down the engine**

Find the `.onChange(of: deviceManager.state)` block (around line 89). Replace its body with:

```swift
        .onChange(of: deviceManager.state) { _, newState in
            // Do not tear down the engine while we're attempting reconnect —
            // we want to reuse the session if the device comes back quickly.
            switch newState {
            case .capturing, .reconnecting:
                return
            default:
                isCapturing = false
                detectedResolution = nil
                cachedPortraitSize = nil
                Task { await captureEngine.stopCapture() }
            }
        }
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MirrorKit/UI/MirrorContentView.swift
git commit -m "feat: reconnecting overlay with cancel button"
```

---

### Task 13: `WifiNudgeView` sheet

**Files:**
- Create: `MirrorKit/UI/WifiNudgeView.swift`
- Modify: `MirrorKit/UI/MirrorContentView.swift`

- [ ] **Step 1: Create `WifiNudgeView.swift`**

Create `MirrorKit/UI/WifiNudgeView.swift`:

```swift
import SwiftUI
import AppKit

/// Sheet shown after the first USB connection of a new device, suggesting
/// the user enable "Show this iPhone when on Wi-Fi" in Finder.
struct WifiNudgeView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .padding(.top, 24)

            Text("Mirror Wirelessly Next Time")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("To use MirrorKit without a USB cable, open Finder, select your iPhone in the sidebar, and check \"Show this iPhone when on Wi-Fi\".")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            // Visual hint: three SF Symbol steps. The full annotated screenshot
            // can replace this once it's added to Assets.xcassets.
            HStack(spacing: 14) {
                stepBadge(systemName: "folder", label: "Finder")
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                stepBadge(systemName: "iphone", label: "iPhone")
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                stepBadge(systemName: "wifi", label: "Enable")
            }
            .padding(.vertical, 8)

            HStack(spacing: 12) {
                Button("Got It") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Open Finder") {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
                    )
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 20)
        }
        .frame(width: 460)
        .padding(.horizontal, 24)
    }

    private func stepBadge(systemName: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .regular))
                .frame(width: 48, height: 48)
                .background(
                    Circle().fill(Color.secondary.opacity(0.15))
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    WifiNudgeView(onDismiss: {})
}
```

- [ ] **Step 2: Wire the sheet in `MirrorContentView`**

In `MirrorContentView.swift`, add a state observation for the nudge manager. Find the existing `@State private var showOnboarding = ...` line (around line 17) and add right after it:

```swift
    @State private var pendingNudgeDevice: ConnectedDevice?
```

Find the `.sheet(isPresented: $showOnboarding)` modifier near the bottom of the `body` (around line 146). Add a second sheet modifier right after it:

```swift
        .sheet(item: $pendingNudgeDevice) { _ in
            WifiNudgeView {
                deviceManager.wifiNudgeManager.dismissNudge()
                pendingNudgeDevice = nil
            }
        }
```

For the `sheet(item:)` to compile, `ConnectedDevice` already conforms to `Identifiable` (it has `id: String`), so this works directly.

In the `.onAppear` block (around line 138), append a subscription that copies the pending device from the manager:

```swift
        .onChange(of: deviceManager.wifiNudgeManager.pendingNudgeDevice) { _, newDevice in
            pendingNudgeDevice = newDevice
        }
```

This goes right after `.onChange(of: deviceManager.selectedDevice?.id)` (around line 130).

- [ ] **Step 3: Regenerate (new file added) and build**

```bash
xcodegen generate
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MirrorKit/UI/WifiNudgeView.swift \
        MirrorKit/UI/MirrorContentView.swift \
        MirrorKit.xcodeproj
git commit -m "feat: WifiNudgeView sheet + scheduling on first USB connection"
```

---

## Phase G — Validation & ship

### Task 14: Manual test plan document

**Files:**
- Create: `docs/superpowers/specs/2026-04-25-wireless-mirroring-test-plan.md`

- [ ] **Step 1: Create the test plan**

Create `docs/superpowers/specs/2026-04-25-wireless-mirroring-test-plan.md`:

```markdown
# Wireless Mirroring v1.1 — Manual Test Plan

**Prerequisites:**
- Physical iPhone (any model running iOS 17+)
- iPhone paired to this Mac at least once via USB, with "Show this iPhone when on Wi-Fi" checked in Finder
- Both Mac and iPhone on the same Wi-Fi network
- A second test iPhone for the multi-device scenarios (optional but recommended)

## Reset between runs

Before each session, clear stored nudge flags:
```bash
defaults delete com.achraftrabelsi.MirrorKit
```

## A. USB regression (must match v1.0)

- [ ] Plug iPhone via USB → device appears in picker with USB icon
- [ ] Click iPhone → mirroring starts, frames display
- [ ] Unplug iPhone → device disappears, app returns to detecting state
- [ ] Plug back → device reappears, no error sheet from a stale state

## B. Wi-Fi happy path (new)

- [ ] Without USB plugged, iPhone on Wi-Fi → device appears in picker with Wi-Fi icon
- [ ] Click iPhone → mirroring starts, frames display
- [ ] Subjective latency feels acceptable (< ~500ms)
- [ ] Floating toolbar shows "Wi-Fi" badge next to device name
- [ ] Resolution adapts correctly when rotating the iPhone

## C. Both transports simultaneously

- [ ] Plug iPhone via USB while it's also visible on Wi-Fi → only one entry in picker
- [ ] If two entries appear (with same modelID/name): file a bug — design assumed dedup; needs fix

## D. Reconnection (new)

- [ ] Start mirroring over Wi-Fi
- [ ] On iPhone: Settings > Wi-Fi > toggle off → reconnecting overlay appears within ~2s
- [ ] Toggle Wi-Fi back on within 10s → overlay dismisses, capture resumes
- [ ] Repeat, but leave Wi-Fi off for >10s → error sheet appears with "Wi-Fi connection lost" message
- [ ] Repeat, but click Cancel during overlay → returns to detecting state, no error
- [ ] Confirm: USB unplug does NOT trigger the reconnecting overlay (immediate disconnect, as v1.0)

## E. Wi-Fi nudge

- [ ] Reset nudge flags (see top)
- [ ] Plug iPhone via USB for the first time → after ~3s, sheet appears
- [ ] Click "Got It" → sheet dismisses
- [ ] Unplug, plug back same iPhone → sheet does NOT reappear
- [ ] Reset nudge flags, plug iPhone → sheet appears, click "Open Finder" → Finder opens, sheet dismisses
- [ ] Plug a different iPhone (different uniqueID) → sheet appears for the new device
- [ ] Wi-Fi-only device (paired but never plugged in this session) → sheet does NOT appear (transport == .wifi skipped)

## F. App Store / sandbox sanity

- [ ] `xcodebuild archive` produces a Release build with no entitlement errors
- [ ] Open the archived `.app` directly: launches without any Gatekeeper / sandbox alert
- [ ] Run `nm -u <archived-binary>` and verify no private API symbols (e.g. nothing with leading underscore that isn't a standard system symbol)
- [ ] All `MirrorKitTests` pass via `xcodebuild test`

## G. Cleanup

- [ ] No spike code remaining (search: `grep -rn "SPIKE" MirrorKit/`)
- [ ] No `print` statements added beyond the existing ones
- [ ] All TODO/FIXME comments addressed or filed as follow-up issues
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-04-25-wireless-mirroring-test-plan.md
git commit -m "docs: manual test plan for wireless mirroring v1.1"
```

- [ ] **Step 3: Execute the manual test plan**

Walk through every checkbox in the document above on a physical iPhone. Mark each `[x]` as it's confirmed.

If any item fails: stop, fix the underlying issue, re-test the affected section. Do not proceed to Task 15 until all checkboxes pass.

---

### Task 15: Final unit test sweep

**Files:** none

- [ ] **Step 1: Run the full test suite**

```bash
cd /Users/a.trabelsi/Workspace/Perso/MirrorApp
xcodebuild test -project MirrorKit.xcodeproj -scheme MirrorKit \
  -destination 'platform=macOS' 2>&1 | tail -40
```

Expected: all tests pass (~13 tests across `TransportMappingTests`, `CaptureStateTests`, `WifiNudgeManagerTests`, `SmokeTests`).

- [ ] **Step 2: Confirm clean working tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

### Task 16: Bump build number and final smoke build

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Bump `CURRENT_PROJECT_VERSION` in `project.yml`**

In `project.yml`, find:

```yaml
    CURRENT_PROJECT_VERSION: "7"
```

Change to:

```yaml
    CURRENT_PROJECT_VERSION: "8"
    MARKETING_VERSION: "1.1.0"
```

(`MARKETING_VERSION` was `"1.0.0"` — bumping to `1.1.0` to reflect the new feature release.)

- [ ] **Step 2: Regenerate the project**

```bash
xcodegen generate
```

- [ ] **Step 3: Release archive smoke test**

```bash
xcodebuild archive \
  -project MirrorKit.xcodeproj \
  -scheme MirrorKit \
  -configuration Release \
  -archivePath /tmp/MirrorKit-v1.1.xcarchive \
  2>&1 | tail -20
```

Expected: `** ARCHIVE SUCCEEDED **`. The archive is written to `/tmp/MirrorKit-v1.1.xcarchive`.

- [ ] **Step 4: Commit**

```bash
git add project.yml MirrorKit.xcodeproj
git commit -m "chore: bump to v1.1.0 (build 8) for wireless mirroring release"
```

- [ ] **Step 5: Tag the release**

```bash
git tag -a v1.1.0 -m "v1.1.0 — Wireless mirroring via CoreMediaIO Wi-Fi"
```

- [ ] **Step 6: Submit reminder**

The actual App Store submission (`Product → Archive → Distribute App` from Xcode UI) is a manual step the developer performs. The reviewer note for this submission should explicitly state:

> MirrorKit v1.1 adds wireless mirroring using the same public CoreMediaIO API as QuickTime Player's wireless iPhone screen recording (`kCMIODevicePropertyTransportType` to distinguish USB from Wi-Fi). No private API is used. The capture pipeline is identical to the v1.0 USB code path; only the transport detection and reconnection UX are new.
