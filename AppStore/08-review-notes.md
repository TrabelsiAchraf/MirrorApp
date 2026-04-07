# App Review Information → Notes

## Sign-In Required
No

## Demo Account
Not applicable.

## Notes for the Reviewer

MirrorKit displays the screen of an iPhone connected to the Mac via a USB cable. It uses the public CoreMediaIO API (kCMIOHardwarePropertyAllowScreenCaptureDevices) combined with AVFoundation, which is the exact same mechanism that QuickTime Player uses for iOS screen recording. No private frameworks are used.

To test the app:
1. Launch MirrorKit on the Mac.
2. Connect an iPhone (iOS 13 or later) to the Mac with a USB or USB-C cable.
3. On the iPhone, tap "Trust" if prompted.
4. The iPhone screen will appear automatically inside the MirrorKit window after a few seconds.

The Camera permission requested at first launch is required because macOS exposes the connected iPhone as an AVCaptureDevice — this is a system-level requirement, not a real camera access.

The app does not collect, transmit, or store any user data. There is no network activity at all.

Thank you for reviewing MirrorKit.

## Contact Information
- First name: Achraf
- Last name: Trabelsi
- Phone: <your phone>
- Email: <your email>
