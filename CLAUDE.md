# MirrorKit — Claude Code instructions

## Project
Native macOS app (SwiftUI + AppKit) that mirrors an iPhone screen connected via USB.
Uses CoreMediaIO + AVFoundation, the same pipeline as QuickTime Player.
Target: Mac App Store, single-purchase 9.99€.

## Tech
- macOS 14.0+ (Sonoma), Swift 5.9+, SwiftUI lifecycle
- 100% Apple frameworks, no external dependencies
- Project generated with `xcodegen` from `project.yml`
- Bundle ID: `com.achraftrabelsi.MirrorKit`
- Team ID: `QN66UQNDZR`

## Language convention
**Everything in English** — UI strings AND code comments.
The previous "comments in French" rule does NOT apply to this project — it ships English-only on the App Store.

## Architecture
```
MirrorKit/
├── MirrorKitApp.swift          # @main, SwiftUI App lifecycle
├── AppDelegate.swift           # CoreMediaIO setup, status item, main menu, Cmd+T
├── Info.plist                  # Bundle metadata, NSCameraUsageDescription
├── MirrorKit.entitlements      # Sandbox + camera + USB
├── Core/
│   ├── DeviceManager.swift     # @Observable — iPhone USB discovery
│   ├── CaptureEngine.swift     # Actor — AVCaptureSession pipeline
│   └── FrameRenderer.swift     # NSViewRepresentable + VideoDisplayLayer (CALayer)
├── UI/
│   ├── MirrorWindowController.swift  # NSWindowController + BorderlessWindow
│   ├── MirrorContentView.swift       # Main view, expand mode, capture states
│   ├── DeviceFrameView.swift         # iPhone bezel + Dynamic Island around video
│   ├── FloatingToolbar.swift         # Custom traffic lights + device label
│   ├── OnboardingView.swift          # 3-step first-run flow
│   ├── AboutView.swift               # About window
│   └── DevicePickerView.swift        # Multi-device picker
├── Models/
│   ├── ConnectedDevice.swift   # id / name / modelID / resolution
│   └── CaptureState.swift      # idle / detecting / connected / capturing / error
└── Utils/
    └── DeviceFrameProvider.swift     # Per-modelID DeviceFrameSpec lookup
```

## Build & run
```bash
xcodegen generate
xcodebuild -project MirrorKit.xcodeproj -scheme MirrorKit -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/MirrorKit-*/Build/Products/Debug/MirrorKit.app
```
After editing `project.yml`, always re-run `xcodegen generate`.

## Important constraints
- **Do NOT add `entitlements.path` back to project.yml** — xcodegen overwrites the entitlements file. The entitlements are referenced via `CODE_SIGN_ENTITLEMENTS` only.
- **Do NOT add `ENABLE_APP_SANDBOX` build setting** — same reason: it forces xcodegen to regenerate the entitlements file.
- **CMSampleBuffers must NOT be retained** — process and release immediately. `alwaysDiscardsLateVideoFrames = true` on the output.
- **CaptureEngine is an Actor** — call from `Task { await captureEngine.… }`.
- **Window is borderless** — `BorderlessWindow` overrides `canBecomeKey`/`canBecomeMain` so traffic lights stay clickable.
- **Aspect ratio is locked to the iPhone resolution** detected from the first frame.

## Workflow rules
- Always present a plan before writing code (user preference).
- Commit messages in English only.
- Don't ask Claude to generate docs unless explicitly requested.
- Test on a physical iPhone for any capture-pipeline change.

## App Store submission
- App ID created on developer.apple.com
- App created on App Store Connect
- `Product → Archive` in Xcode → Distribute App → App Store Connect
- Reviewer note: explain that MirrorKit uses the same public CoreMediaIO mechanism as QuickTime Player's iPhone screen recording.
