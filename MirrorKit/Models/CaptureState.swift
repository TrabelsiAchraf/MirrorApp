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
    /// Error encountered
    case error(String)

    static func == (lhs: CaptureState, rhs: CaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.detecting, .detecting), (.capturing, .capturing):
            return true
        case let (.connected(a), .connected(b)):
            return a.id == b.id
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}
