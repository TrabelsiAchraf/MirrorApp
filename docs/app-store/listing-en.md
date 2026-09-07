# App Store listing — English (U.S.) — MirrorKit 1.2.0

Character limits: name 30, subtitle 30, promotional text 170, keywords 100, description 4000.

## Name (30)

MirrorKit – iPhone on Mac

## Subtitle (30)

Mirror your iPhone via USB

## Promotional text (170)

Show your iPhone screen on your Mac over USB, in real time, with a realistic bezel. Record, snapshot and annotate. Now in French.

## Keywords (100)

iphone,mirror,mirroring,screen,usb,record,screenshot,demo,presentation,quicktime,display,cast

## Description (4000)

MirrorKit displays the screen of your iPhone or iPad on your Mac through a simple USB cable. No Wi‑Fi, no pairing codes, no lag: the same low-latency pipeline QuickTime Player uses, wrapped in a window that looks like your device.

WHY MIRRORKIT
• Real time over USB — a wired connection means smooth video and no network setup.
• A realistic frame — MirrorKit detects your iPhone model from the video stream and draws the matching bezel and Dynamic Island. Choose black, silver or gold, or go frameless.
• Made for presentations — expand to fill the screen with a clean background, keep the window always on top, rotate to landscape with a keystroke.

CAPTURE
• Record your iPhone screen to a video file with one click or ⌘R.
• Take a snapshot with ⌘S, with the real camera shutter sound.
• Annotate live on top of the mirrored screen: pen, circles, undo, clear.
• Choose where recordings and snapshots are saved.

SEVERAL DEVICES
• Plug in more than one iPhone or iPad and switch between them from the toolbar.
• MirrorKit remembers the device you picked last time.

BUILT FOR THE MAC
• Native app, written in Swift with SwiftUI and AppKit. No Electron, no background services.
• Borderless window with its own traffic lights, hover toolbar, menu bar icon, Dock reopen.
• Full keyboard control: ⌘R record, ⌘S snapshot, ⌘T always on top, ⌘← ⌘→ rotate, ⌘0 reset zoom, A annotate.
• VoiceOver labels on every control.
• Available in English and French.

WHEN SOMETHING GOES WRONG
If an iPhone refuses to stream, MirrorKit tells you exactly what to check — restart the iPhone, unlock it, Screen Time restrictions, management profiles — instead of leaving you with a black screen.

HOW IT WORKS
MirrorKit relies on the public CoreMediaIO and AVFoundation frameworks that QuickTime Player uses for "New Movie Recording". macOS asks for camera permission because it presents the iPhone screen as a video source; MirrorKit never records or transmits anything without your action, and everything stays on your Mac.

REQUIREMENTS
• macOS 14 Sonoma or later.
• An iPhone or iPad connected with a USB cable and unlocked; tap "Trust This Computer" the first time.

MirrorKit is a one-time purchase. No subscription, no account, no tracking.

## What's New (4000)

• French localization
• Real iPhone model name and bezel, detected from the video stream
• Clear guidance when an iPhone refuses to mirror, instead of a black screen
• Remembers your last selected iPhone when several are connected
• Settings reachable from the device menu and the menu bar icon
• Dock icon reopens the mirror window
• VoiceOver labels on the toolbar
• Fixes: Settings window not opening on macOS 15+, stale frame when switching devices

## Review notes

MirrorKit displays the screen of a USB-connected iPhone using the same public CoreMediaIO / AVFoundation mechanism as QuickTime Player's "New Movie Recording" (kCMIOHardwarePropertyAllowScreenCaptureDevices). No private API. Camera permission is requested because macOS exposes the iPhone screen as a video capture device. To test: connect an iPhone via USB, unlock it, tap "Trust This Computer", grant camera access.

## App Privacy

Data not collected. The app has no network access, no analytics, no account.

## Screenshots to prepare (English UI)

1. iPhone home screen mirrored with the classic black bezel, toolbar visible.
2. Expanded mode on a gradient background (presentation).
3. Annotation mode with a drawn circle and the side tool panel.
4. Device menu open with two iPhones listed.
5. Settings window (save location, bezel style, background).
Sizes: 1280×800 or 2560×1600 minimum for Mac; capture the window on a solid desktop.
