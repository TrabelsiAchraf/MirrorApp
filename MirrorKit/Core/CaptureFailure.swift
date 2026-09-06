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
    case noFrames(timeout: TimeInterval)
    /// Any other runtime error, with its localized description.
    case other(String)

    /// `'!dev'` — kCMIOHardwareBadDeviceError, surfaced by the iOS screen
    /// capture assistant when the Valeria handshake with the iPhone fails.
    static let badDeviceOSStatus = 560_227_702

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
            return """
            \(deviceName) was detected but refused to stream its screen.

            • Restart the iPhone, then reconnect it — this fixes most cases
            • On the iPhone, check Screen Time › Content & Privacy Restrictions › Screen Recording is allowed
            • Check for a management (MDM) profile that restricts screen recording
            """
        case .deviceDisconnected:
            return "\(deviceName) was disconnected.\n\nReconnect the USB cable and try again."
        case .deviceInUse:
            return "\(deviceName) is already being captured by another app.\n\nQuit QuickTime Player or any other mirroring app, then retry."
        case .noFrames(let timeout):
            return """
            No video received from \(deviceName) after \(Int(timeout)) seconds.

            • Unlock the iPhone and keep its screen on
            • Unplug and reconnect the iPhone
            • Try a different USB cable or port
            """
        case .other(let description):
            return "Capture failed: \(description)"
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
