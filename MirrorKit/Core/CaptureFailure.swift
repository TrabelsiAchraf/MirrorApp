import AVFoundation
import Foundation

/// A capture session failure that happened *after* `startRunning()` succeeded.
///
/// AVFoundation reports these asynchronously through `AVCaptureSessionRuntimeError`
/// (or not at all — some iPhones silently never deliver a frame), so the engine
/// classifies them here and the UI turns them into an actionable error state
/// instead of a black screen.
enum CaptureFailure: Equatable, Sendable {
    /// The iPhone was detected but its screen-capture service refused to start
    /// the stream (OSStatus `'!dev'`). Seen when Screen Time / MDM restricts
    /// screen recording or when the on-device service is stuck.
    case deviceRefused
    /// The iPhone was unplugged while capturing.
    case deviceDisconnected
    /// Another app (QuickTime, another mirroring tool) owns the stream.
    case deviceInUse
    /// The session is running but no video frame arrived within the timeout.
    /// Non-fatal hint: the iPhone may simply be locked.
    case noFrames(timeout: TimeInterval)
    /// Still no frame after the long timeout and no runtime error either —
    /// the stream is dead (the assistant does not always report the refusal).
    case streamTimedOut(timeout: TimeInterval)
    /// Any other runtime error, with its localized description.
    case other(String)

    /// `'!dev'` — kCMIOHardwareBadDeviceError, surfaced by the iOS screen
    /// capture assistant when the Valeria handshake with the iPhone fails.
    static let badDeviceOSStatus = 560_227_702

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
        String(localized: "Waiting for video from \(deviceName)… Unlock the iPhone and keep its screen on.")
    }

    /// Maps an error delivered by `AVCaptureSessionRuntimeError` to a failure.
    static func classify(_ error: Error) -> CaptureFailure {
        if Self.containsOSStatus(badDeviceOSStatus, in: error as NSError) {
            return .deviceRefused
        }

        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain {
            switch AVError.Code(rawValue: nsError.code) {
            case .deviceWasDisconnected, .deviceNotConnected:
                return .deviceDisconnected
            case .deviceInUseByAnotherApplication, .deviceAlreadyUsedByAnotherSession:
                return .deviceInUse
            default:
                break
            }
        }

        return .other(error.localizedDescription)
    }

    /// Extracts the error stored under `AVCaptureSessionErrorKey` in a runtime
    /// error notification. Returns `nil` when the notification carries none.
    static func error(from notification: Notification) -> Error? {
        notification.userInfo?[AVCaptureSessionErrorKey] as? Error
    }

    /// User-facing message, in the same style as the discovery errors.
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
        case .streamTimedOut(let timeout):
            return String(localized: "\(deviceName) did not send any video for \(Int(timeout)) seconds.\n\n• Restart the iPhone, then reconnect it — this fixes most cases\n• Unlock the iPhone and keep its screen on\n• On the iPhone, check Screen Time › Content & Privacy Restrictions › Screen Recording is allowed")
        case .other(let description):
            return String(localized: "Capture failed: \(description)")
        }
    }

    // MARK: - Private

    /// Walks the `NSUnderlyingError` chain looking for an `NSOSStatusErrorDomain`
    /// error with the given code.
    private static func containsOSStatus(_ code: Int, in error: NSError) -> Bool {
        var current: NSError? = error
        var depth = 0
        while let candidate = current, depth < 8 {
            if candidate.domain == NSOSStatusErrorDomain && candidate.code == code {
                return true
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }
}
