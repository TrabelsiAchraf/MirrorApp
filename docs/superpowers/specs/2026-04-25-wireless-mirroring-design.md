# Wireless Mirroring (v1.1) — Design Spec

**Date**: 2026-04-25
**Author**: Achraf Trabelsi
**Status**: Draft — pending implementation
**Target release**: MirrorKit v1.1 (free update)

---

## 1. Goal

Allow MirrorKit users to mirror their iPhone wirelessly, using the same model as Xcode's "Connect via Network" feature: the iPhone must have been paired once over USB and trusted; afterwards, while iPhone and Mac are on the same Wi-Fi network with "Show this iPhone when on Wi-Fi" enabled in Finder, the device appears in MirrorKit and can be mirrored without a cable.

The feature is built on the **same CoreMediaIO + AVFoundation pipeline as USB capture** — Apple already supports wireless iOS device capture natively (this is what QuickTime's wireless screen recording uses). No reverse-engineered protocols, no third-party SDKs, no companion iOS app.

## 2. Non-goals

- Cable-free first-time setup. The first USB pairing is required by macOS itself (out of MirrorKit's control).
- Custom AirPlay / WebRTC / RTSP streaming protocols. These would require a companion iOS app and are deferred to a possible future v2.
- Bluetooth mirroring. Insufficient bandwidth for real-time video.
- Onboarding redesign. The 3-step `OnboardingView` stays USB-centric; wireless is discovered via a proactive nudge after first USB connection.
- Internationalization. MirrorKit ships English-only; all new strings are English.
- Pricing changes. v1.1 is a free update for v1.0 buyers; no StoreKit / IAP work.

## 3. Product decisions (locked)

| Dimension | Decision |
|---|---|
| Connection model | Xcode-like: USB pre-pairing required, then wireless |
| Transport visibility in UI | Explicit badge (USB icon / Wi-Fi icon) in picker and toolbar |
| Feature discoverability | Proactive sheet ("nudge") after first USB connection of a new device |
| Monetization | Free v1.1 update — no StoreKit code |
| Wi-Fi disconnect handling | Auto-retry overlay (~10 attempts × 1s), then error with manual retry |

## 4. Validation spike (step 0, blocking)

Before any production code, a time-boxed spike (~0.5–1 day) must validate the keystone technical assumption: that AVCaptureDevice / CoreMediaIO surface Wi-Fi paired iOS devices via the same APIs as USB devices.

### 4.1 What to validate

On a physical iPhone with "Show this iPhone when on Wi-Fi" enabled in Finder, both Mac and iPhone on the same Wi-Fi network:

1. The device appears in `AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: nil)`.
2. The device satisfies `hasMediaType(.muxed) == true` (current MirrorKit filter).
3. `AVCaptureDeviceInput(device:)` succeeds and `AVCaptureSession.startRunning()` produces frames.
4. The CoreMediaIO property `kCMIODevicePropertyTransportType` returns a fourCC that distinguishes USB from Wi-Fi (expected: `'usb '` = `0x75736220` for USB, and a different code such as `'wlan'` / `'wifi'` / `kIOAudioDeviceTransportTypeNetwork` for Wi-Fi — exact value to be observed empirically).

### 4.2 Spike deliverable

- A throwaway dev-only branch that adds verbose `print` of `transportType` fourCC for every device detected by `DeviceManager`.
- A `docs/superpowers/specs/2026-04-25-wireless-mirroring-spike-results.md` document with the observed fourCC values for USB and Wi-Fi devices, plus a screen recording showing wireless capture working end-to-end.
- Go/no-go decision recorded in that document.

### 4.3 No-go fallback

If any of the four validation points fails (in particular: Wi-Fi devices do not appear via the public `DiscoverySession` API), the design is invalidated. We return to brainstorming and reconsider option B (companion iOS app over WebRTC), which is a substantially larger project with its own App Store cycle.

## 5. Architecture

### 5.1 File layout

```
MirrorKit/
├── Core/
│   ├── DeviceManager.swift         [MODIFIED]
│   └── CaptureEngine.swift         [UNCHANGED]
├── Models/
│   ├── ConnectedDevice.swift       [MODIFIED]
│   ├── CaptureState.swift          [MODIFIED]
│   └── DeviceTransport.swift       [NEW]
├── UI/
│   ├── MirrorContentView.swift     [MODIFIED]
│   ├── DevicePickerView.swift      [MODIFIED]
│   ├── FloatingToolbar.swift       [MODIFIED]
│   ├── WifiNudgeView.swift         [NEW]
│   └── OnboardingView.swift        [UNCHANGED]
└── Utils/
    ├── DeviceFrameProvider.swift   [UNCHANGED]
    ├── TransportDetector.swift     [NEW]
    └── WifiNudgeManager.swift      [NEW]

MirrorKitTests/                     [NEW — test target]
├── TransportMappingTests.swift
├── WifiNudgeManagerTests.swift
└── CaptureStateTests.swift

docs/superpowers/specs/
├── 2026-04-25-wireless-mirroring-design.md         (this file)
├── 2026-04-25-wireless-mirroring-spike-results.md  (spike output)
└── 2026-04-25-wireless-mirroring-test-plan.md      (manual test checklist)
```

**Total**: 6 modified, 4 new production files, 3 new test files, 3 new docs.

### 5.2 Component boundaries

- **`DeviceTransport`** (Models): pure value type. Enum `.usb` / `.wifi` with `iconName: String` and `displayName: String` helpers. Equatable. No dependencies.
- **`TransportDetector`** (Utils): namespace enum with a single static function `detect(_ device: AVCaptureDevice) -> DeviceTransport`. Wraps the CoreMediaIO `kCMIODevicePropertyTransportType` lookup. Pure with respect to the device input — no side effects, no cached state.
- **`WifiNudgeManager`** (Utils): `@MainActor` final class. Init takes `UserDefaults` (defaults to `.standard`, override-able for tests). Exposes `shouldShowNudge(for: ConnectedDevice) -> Bool` and `markShown(for: ConnectedDevice)`. Stores per-device flags under key `hasShownWifiNudgeForDevice.<id>`.
- **`DeviceManager`** remains the single source of truth for discovery state. Consumes `TransportDetector` at device-instantiation time and `WifiNudgeManager` at first-USB-connection time.
- **`CaptureEngine`** is **unchanged** — the AVCaptureSession pipeline is transport-agnostic. This is the architectural payoff of building on CoreMediaIO native Wi-Fi support.

### 5.3 Concurrency

- `DeviceManager` and `WifiNudgeManager` stay on `@MainActor`.
- `TransportDetector` is `nonisolated` — it's a pure function callable from any context.
- `CaptureEngine` remains an `actor`.
- Conforms to `SWIFT_STRICT_CONCURRENCY = complete` (Swift 6.0 in `project.yml`).

## 6. Data model changes

### 6.1 `DeviceTransport` (new)

```swift
enum DeviceTransport: Equatable {
    case usb
    case wifi

    var iconName: String {
        switch self {
        case .usb:  return "cable.connector"
        case .wifi: return "wifi"
        }
    }

    var displayName: String {
        switch self {
        case .usb:  return "USB"
        case .wifi: return "Wi-Fi"
        }
    }
}
```

A failable initializer from a CoreMediaIO transport-type fourCC lives alongside (testable as a pure function):

```swift
extension DeviceTransport {
    init(fourCC: UInt32) {
        switch fourCC {
        case 0x75736220:                        // 'usb '
            self = .usb
        case 0x776C616E, 0x77696669:            // 'wlan', 'wifi' — placeholder values
            self = .wifi
        default:
            self = .usb                         // safe fallback — preserves v1.0 behavior
        }
    }
}
```

The exact Wi-Fi fourCC values above are placeholders — the spike (section 4) determines empirically what `kCMIODevicePropertyTransportType` returns for a Wi-Fi paired iPhone. The spike report updates these constants before implementation begins. Likely candidates beyond `'wlan'`/`'wifi'` are `kIOAudioDeviceTransportTypeNetwork` (`0x6E657477` = `'netw'`) or `kIOAudioDeviceTransportTypeAirPlay` (`0x61697270` = `'airp'`).

### 6.2 `ConnectedDevice` (modified)

```swift
struct ConnectedDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let modelID: String
    let transport: DeviceTransport          // ← new, set at construction time
    var resolution: CGSize?
}
```

Set once in `DeviceManager.addDevice(from:)` via `TransportDetector.detect(avDevice)`. Never mutated afterwards. If a device transitions transport (e.g. USB unplug → Wi-Fi reappear), CoreMediaIO emits a fresh `WasConnected` notification with potentially a new `uniqueID`, producing a new `ConnectedDevice` instance.

### 6.3 `CaptureState` (modified)

```swift
enum CaptureState: Equatable {
    case idle
    case detecting
    case connected(ConnectedDevice)
    case capturing
    case reconnecting(ConnectedDevice, attempt: Int)   // ← new
    case error(String)
}
```

Equatable extended with:

```swift
case let (.reconnecting(a, n1), .reconnecting(b, n2)):
    return a.id == b.id && n1 == n2
```

## 7. Discovery flow

### 7.1 Initial scan (existing path, unchanged)

`DeviceManager.scanExistingDevices()` and the polling rescan still call `AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: nil)` with the `hasMediaType(.muxed)` filter. The only difference is that the result set may now include Wi-Fi paired devices in addition to USB devices.

### 7.2 Device instantiation

`DeviceManager.addDevice(from avDevice: AVCaptureDevice)` is updated:

```swift
private func addDevice(from avDevice: AVCaptureDevice) {
    guard !devices.contains(where: { $0.id == avDevice.uniqueID }) else { return }

    let transport = TransportDetector.detect(avDevice)
    let device = ConnectedDevice(
        id: avDevice.uniqueID,
        name: avDevice.localizedName,
        modelID: avDevice.modelID,
        transport: transport
    )
    devices.append(device)

    if transport == .usb {
        nudgeManager.maybeShowNudge(for: device)
    }
}
```

`maybeShowNudge` schedules the nudge sheet **3 seconds** after detection (so the user sees mirroring start first, then the suggestion appears non-disruptively).

### 7.3 Updated empty-state error message

`DeviceManager.swift` line ~156 ("No iPhone detected" message) is replaced with:

```
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
```

## 8. Reconnection flow

### 8.1 Trigger conditions

In `DeviceManager.handleDeviceDisconnected(_:)`, when an `AVCaptureDeviceWasDisconnected` notification arrives:

```
if state == .capturing
   AND disconnected device.id == selectedDevice?.id
   AND selectedDevice.transport == .wifi:
       state = .reconnecting(selectedDevice, attempt: 1)
       startReconnectTimer()
else:
       (existing behavior — remove from devices, fall back to .detecting if list empty)
```

USB disconnects fall through to the existing path: a USB unplug is overwhelmingly intentional (user grabbed their phone), so showing a 10-second "reconnecting" overlay would be hostile UX.

### 8.2 Reconnect timer

A new private `nonisolated(unsafe) reconnectTimer: Timer?` on `DeviceManager`, mirroring the pattern of the existing `rescanTimer`.

- **Interval**: 1.0 second, repeating.
- **Max attempts**: 10 (≈ 10 seconds total).
- **On each tick**: re-run `DiscoverySession`. If a device with the same `id` reappears, call `handleDeviceConnected(_:)` directly, which restarts capture and transitions `state = .capturing`.
- **On attempt 10 without recovery**: `state = .error("Wi-Fi connection lost. Make sure your iPhone is on the same Wi-Fi network.")`. Timer stops. The device is removed from `devices`.
- **On user cancel** (button in overlay): `cancelReconnect()` stops the timer and sets `state = .detecting`. The device stays in `devices` only if it has reappeared in a discovery scan in the meantime; otherwise it is removed (consistent with the standard disconnect path).

### 8.3 Capture session lifecycle during `.reconnecting`

`CaptureEngine.stopCapture()` is **not** called while in `.reconnecting`. The session is left running but starved of frames. The `FrameRenderer`'s `VideoDisplayLayer` retains the last decoded frame, which is what we visually freeze under the overlay.

When the device is rediscovered, `DeviceManager` calls `CaptureEngine.startCapture(...)` again. The previous session is replaced (the engine's `stopCapture()` is the first thing `startCapture()` does internally — see `CaptureEngine.swift:60`).

If the timeout fires (state moves to `.error`), `CaptureEngine.stopCapture()` is called explicitly to tear down the session.

## 9. UI changes

### 9.1 Transport badge — `DevicePickerView`

Each device row gains a leading `Image(systemName: device.transport.iconName)` styled `.foregroundStyle(.secondary)`. No text label — the icon is the visual signal, matching Xcode/Finder/Photos conventions.

### 9.2 Transport badge — `FloatingToolbar`

To the right of the device name, append a separator and the transport badge with text:

```
iPhone d'Achraf  ·  [icon] Wi-Fi
```

This is the persistent indicator visible during the entire mirroring session — it justifies any perceived latency difference and gives the user immediate context.

### 9.3 Reconnecting overlay — `MirrorContentView`

A `ZStack` over the `FrameRenderer`, rendered when `state` is `.reconnecting`:

- Background: `Color.black.opacity(0.55)` over a `.blur(radius: 12)` of the underlying frame.
- Foreground (vertical stack, centered):
  - `ProgressView()` (indeterminate spinner)
  - `Text("Reconnecting…")` (system font, semibold)
  - `Text("Attempt \(attempt) of 10")` (caption, secondary color)
  - `Button("Cancel")` (bordered prominent style, calls `deviceManager.cancelReconnect()`)
- Smooth fade in/out via `.transition(.opacity)`.

### 9.4 Wi-Fi nudge sheet — `WifiNudgeView` (new)

A SwiftUI `View` presented as a `.sheet` from `MirrorContentView`, controlled by a `@State` flag bound to `WifiNudgeManager`'s pending-nudge signal.

Layout (vertical stack):
- SF Symbol `wifi` at large size, accent color
- Title: `Mirror Wirelessly Next Time` (title2, bold)
- Body: `To use MirrorKit without a USB cable, open Finder, select your iPhone in the sidebar, and check "Show this iPhone when on Wi-Fi".`
- Annotated screenshot asset (light + dark variants in `Assets.xcassets`)
- Two buttons: `[Open Finder]` (primary) and `[Got It]` (secondary)

Both buttons call `nudgeManager.markShown(for: device)` and dismiss the sheet. "Open Finder" additionally calls `NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))`, which is allowed under the App Sandbox without extra entitlements.

### 9.5 Untouched UI

`OnboardingView`, the menu bar, `Cmd+T` window-toggle, the About window, and `DeviceFrameView` are not modified.

## 10. Testing strategy

### 10.1 New test target — `MirrorKitTests`

The project has no tests today. We add a minimal Swift Testing target (~80 lines total) covering the pure-logic pieces where unit tests are cheap and high-value.

**`TransportMappingTests.swift`** — verifies `DeviceTransport.init(fourCC:)`:
- USB code (`0x75736220`) → `.usb`
- Wi-Fi codes confirmed by the spike → `.wifi`
- Unknown codes (`0x00000000`, random) → `.usb` (fallback)

**`WifiNudgeManagerTests.swift`** — verifies UserDefaults-backed state, with an injected `UserDefaults(suiteName: "test.\(UUID())")`:
- First call to `shouldShowNudge(for:)` returns `true`
- After `markShown(for:)`, `shouldShowNudge(for:)` returns `false`
- A different device id is independent (returns `true`)

**`CaptureStateTests.swift`** — verifies Equatable on the new case:
- Same device + same attempt → equal
- Same device + different attempts → not equal
- Different devices → not equal

**Not unit-tested** (deliberate): `DeviceManager`, `CaptureEngine`, `TransportDetector.detect(_:)` (the CMIO lookup itself). Too coupled to AVFoundation/CoreMediaIO/`NotificationCenter`/`Timer` to be worth mocking. Validated manually instead.

### 10.2 Manual test plan

A separate document `docs/superpowers/specs/2026-04-25-wireless-mirroring-test-plan.md` is produced as part of this work, with a checklist covering:

- USB regression (devices appear/disappear, capture works as v1.0)
- Wi-Fi happy path (device with badge, capture, subjective latency check)
- USB + Wi-Fi simultaneous discovery (one entry expected; behavior to confirm)
- Reconnect (Wi-Fi off mid-session, recovery within 10s, timeout, cancel)
- Nudge (first connection triggers sheet after 3s, "Got It" / "Open Finder" both dismiss permanently for that device, new device re-triggers)
- App Store / sandbox sanity (Release archive builds, signed binary launches, no private API in `nm -u` output)

### 10.3 What is not automated

- No UI tests (XCUITest on macOS SwiftUI: high pain, low ROI).
- No AVFoundation integration tests (would require a physical iPhone on CI).
- No latency benchmarks. Latency is judged subjectively during manual testing.

## 11. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Wi-Fi paired iOS does not appear in `AVCaptureDevice.DiscoverySession([.external])` | Low | Blocking | Validation spike (section 4) before any production code. |
| `kCMIODevicePropertyTransportType` returns a fourCC we can't map confidently | Medium | Medium | Spike captures actual fourCC values empirically; fallback is `.usb` (no functional regression). |
| Same iPhone appears twice (USB entry + Wi-Fi entry simultaneously) | Medium | Low | Spike validates; if duplication occurs, dedup by `(modelID, name)` and prefer `.usb` entry. |
| AVCaptureDeviceInput on Wi-Fi device fails with sandbox/entitlement error | Low | Blocking | Spike validates with the existing `com.apple.security.device.camera` entitlement. |
| App Store reviewer flags Wi-Fi capture as needing additional justification | Medium | Schedule slip | Reviewer note: "MirrorKit uses the same public CoreMediaIO API as QuickTime Player's wireless iPhone screen recording. No private API. Same code path as the existing approved USB feature." |
| Wi-Fi capture works but latency / framerate is unusable in practice | Medium | Feature value | Section 9.2 transport badge in toolbar makes the user aware of the transport. Future iteration could add a quality indicator. Out of scope for v1.1. |

## 12. Out of scope (deferred)

- **Quality indicator** (latency / framerate badge in the toolbar with green/orange/red state). Originally floated as option C of question 5; deferred to v1.2 if user feedback warrants it.
- **Persistent paired-device list** (showing offline-but-paired devices in the picker like Xcode does). Current design only shows currently-discoverable devices. Possible v1.2 addition.
- **Localization**. MirrorKit ships English-only.
- **Companion iOS app** (true cable-free experience, WebRTC-based). A separate, much larger project; deferred indefinitely.

## 13. Implementation order (suggested)

1. **Spike** (section 4) — branch `spike/wireless-transport-detection`, dev-only logging, document fourCC values, go/no-go gate.
2. **Models** — `DeviceTransport.swift`, `ConnectedDevice` field, `CaptureState.reconnecting` case + Equatable.
3. **Utils** — `TransportDetector.swift` (using fourCC values from the spike), `WifiNudgeManager.swift`.
4. **DeviceManager** — wire `TransportDetector` into `addDevice(from:)`, wire `WifiNudgeManager`, update error message, add reconnect timer + state transitions.
5. **UI** — badge in `DevicePickerView` and `FloatingToolbar`, reconnecting overlay in `MirrorContentView`, `WifiNudgeView` sheet.
6. **Tests** — add `MirrorKitTests` target via `project.yml`, write the three test files.
7. **Manual validation** — execute the test plan against a physical iPhone on USB and on Wi-Fi.
8. **App Store submission** — bump `CURRENT_PROJECT_VERSION`, update reviewer note to mention the wireless code path uses the same public CoreMediaIO API as QuickTime.

A detailed implementation plan with steps, dependencies, and review checkpoints is produced in a follow-up document by the `writing-plans` skill.
