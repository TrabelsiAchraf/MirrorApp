# MirrorKit Roadmap

Living document. Items move up as they get scheduled; shipped items move to
the changelog section at the bottom.

## Next release — 1.2 (in progress)

Tracked in `docs/superpowers/plans/2026-09-07-priority-1-batch.md`.

- Non-blocking "waiting for video" hint instead of a hard error when no frame
  arrives yet (locked iPhone, slow USB re-enumeration).
- Real model name and bezel per iPhone model, derived from the stream
  resolution (AVFoundation reports `modelID = "iOS Device"` for every USB
  iPhone, so the bezel currently falls back to the generic spec).
- Clicking the Dock icon reopens the mirror window after it was closed.
- "Settings…" entry in the menu bar (status item) menu.
- Accessibility labels on the custom toolbar (traffic lights, capture actions,
  device picker) for VoiceOver.
- Remember the last selected iPhone and re-select it automatically when
  several devices are connected.

## Later — 1.3

- **Audio in recordings.** The USB screen device is muxed video + audio, but
  `VideoRecorder` only writes the video track (H.264). Add the audio track and
  an HEVC option in Settings.
- **Recording indicator** in the floating toolbar: elapsed time, blinking red
  dot, visible stop control.
- **Snapshot export with bezel and background** (App Store-ready visuals), if
  not already fully covered by `AnnotationCompositor`.
- **Keyboard shortcuts sheet** (Cmd+/) listing R, S, T, 0, arrows, A.
- **French localization** — no string catalog yet; FR is the primary market.

## Backlog

- Persist window position and size across launches (verify current behavior).
- Richer "iPhone detected but refused to stream" error: "Retry after iPhone
  restart" button with countdown.
- "What's new" sheet on first launch of a new version.
- Model-specific bezel geometry for iPad (mini / Air / Pro 13") from the
  detected resolution.

## Shipped

### 1.1.2 (unreleased)

- Capture runtime errors (`'!dev'`, disconnected, in use) surface as an
  actionable error view instead of a black screen.
- Settings window opens again on macOS 15+ (`openSettings` environment action
  instead of the rejected `showSettingsWindow:` selector).
- "Settings…" entry at the top of the toolbar device menu.
