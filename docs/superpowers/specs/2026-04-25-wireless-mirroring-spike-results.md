# Wireless Mirroring Spike Results

**Date:** 2026-04-25
**Tested device:** iPhone (iPhone18,2 — iPhone 16 Pro Max, iOS 18+)
**Mac:** macOS 25.4.0 (Tahoe)
**Tested by:** Achraf Trabelsi
**Worktree:** `/Users/a.trabelsi/Workspace/Perso/MirrorApp-wireless` on `feature/wireless-mirroring`

## Setup

- iPhone paired to this Mac via USB
- "Show this iPhone when on Wi-Fi" checked in Finder
- iPhone successfully appears in Finder sidebar over Wi-Fi (without USB cable)
- Both devices on the same Wi-Fi network
- App launched via Xcode (Cmd+R) from the worktree project, after Clean Build Folder

## Observed values

- **USB connection:** `0x6F746872 ('othr')`
- **Wi-Fi connection:** **No event observed.** The iPhone is visible in Finder over Wi-Fi but does NOT appear in `AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: nil)`. No `WasConnected` notification fires. No `[SPIKE]` log line is emitted.

## Capture works over Wi-Fi: NO

The Wi-Fi paired iPhone never reaches the discovery layer in the first place. There is no `AVCaptureDevice` to call `AVCaptureDeviceInput(device:)` on.

## AVCaptureSession behavior

- Wi-Fi device appears in `DiscoverySession([.external])`: **NO**
- `hasMediaType(.muxed)`: N/A (no device to test)
- `AVCaptureDeviceInput(device:)` succeeds: N/A
- `startRunning()` produces frames: N/A

## Side observations

- The Continuity Camera (iPhone used as Mac webcam, `iPhone18,2`, `muxed=false video=true`) is correctly excluded by the existing `hasMediaType(.muxed)` filter and is irrelevant to this spike.
- The CMIO `kCMIODevicePropertyTransportType` for the USB iPhone returns `'othr'`, not `'usb '`. This is significant: even if Wi-Fi devices DID appear, this property would not have distinguished them — Apple's CMIO DAL plugin (`com.apple.cmio.DAL.iOSScreenCapture`) reports all iOS screen-capture devices as transport "other" regardless of physical link.
- The Xcode log includes `CMIO_Unit_Input_Device_DALPlugInProducer.cpp ... Apple bundleID com.apple.cmio.DAL.iOSScreenCapture is being tagged as kCameraType3rdParty` — a hint that the iOS screen capture pipeline is opaque to the standard CMIO transport-type discriminators.

## Go/no-go decision

**NO-GO.**

Two independent observations both invalidate the original design:

1. The Wi-Fi paired iPhone is not surfaced through `AVCaptureDevice.DiscoverySession([.external])` at all. The whole CoreMediaIO + AVFoundation pipeline that v1.0 uses for USB is not extended to Wi-Fi by Apple. This is consistent with QuickTime Player's behavior — it also requires USB for iPhone screen recording, and Finder's "Show this iPhone when on Wi-Fi" only enables file access, sync, and backup, not screen capture.

2. Even if (1) had succeeded, `kCMIODevicePropertyTransportType` returns `'othr'` for the iOS screen capture pipeline regardless of transport, so the design's `TransportDetector` would not have been able to distinguish USB from Wi-Fi.

## Implications

The full design at `2026-04-25-wireless-mirroring-design.md` is invalidated. The 16-task implementation plan at `../plans/2026-04-25-wireless-mirroring.md` is paused before any production code was written.

The original brainstorming framed three options:

- **A.** CoreMediaIO native Wi-Fi (this spike) — **invalidated**.
- **B.** Companion iOS app + WebRTC streaming — still viable, but a 2-3 month project of its own with a separate App Store submission. To be re-scoped via a fresh brainstorm if desired.
- **C.** AirPlay / private APIs — not viable for App Store.

Decision on next direction is pending user input post-spike.

## Cleanup actions taken

- Spike code in `MirrorKit/Core/DeviceManager.swift` reverted via `git restore` (uncommitted, no impact on history).
- This results document committed to `feature/wireless-mirroring` branch.
- Memory and design spec updated to reflect the no-go.
