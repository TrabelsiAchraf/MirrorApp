import AVFoundation
import Testing
@testable import MirrorKit

@Suite("CaptureFailure")
struct CaptureFailureTests {
    /// Reproduces the exact error AVFoundation delivers when the iOS screen
    /// capture assistant fails the Valeria handshake ('!dev').
    private func badDeviceRuntimeError() -> NSError {
        let underlying = NSError(
            domain: NSOSStatusErrorDomain,
            code: CaptureFailure.badDeviceOSStatus,
            userInfo: ["AVErrorFourCharCode": "!dev"]
        )
        return NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.unknown.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "The operation could not be completed",
                NSUnderlyingErrorKey: underlying,
            ]
        )
    }

    @Test func classifiesBadDeviceOSStatusAsRefused() {
        #expect(CaptureFailure.classify(badDeviceRuntimeError()) == .deviceRefused)
    }

    @Test func classifiesDisconnectedAndInUse() {
        let disconnected = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.deviceWasDisconnected.rawValue)
        let inUse = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.deviceInUseByAnotherApplication.rawValue)
        #expect(CaptureFailure.classify(disconnected) == .deviceDisconnected)
        #expect(CaptureFailure.classify(inUse) == .deviceInUse)
    }

    @Test func classifiesUnknownErrorsAsOther() {
        let error = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
        #expect(CaptureFailure.classify(error) == .other("boom"))
    }

    @Test func extractsErrorFromRuntimeNotification() {
        let notification = Notification(
            name: .AVCaptureSessionRuntimeError,
            object: nil,
            userInfo: [AVCaptureSessionErrorKey: badDeviceRuntimeError()]
        )
        let extracted = CaptureFailure.error(from: notification)
        #expect(extracted != nil)
        #expect(CaptureFailure.classify(extracted!) == .deviceRefused)
        #expect(CaptureFailure.error(from: Notification(name: .AVCaptureSessionRuntimeError)) == nil)
    }

    @Test func messagesNameTheDeviceAndGiveHints() {
        let refused = CaptureFailure.deviceRefused.message(deviceName: "Virus")
        #expect(refused.contains("Virus"))
        #expect(refused.contains("Screen Time"))

        let noFrames = CaptureFailure.noFrames(timeout: 10).message(deviceName: "Virus")
        #expect(noFrames.contains("10 seconds"))
        #expect(noFrames.contains("Unlock"))

        #expect(CaptureFailure.other("boom").message(deviceName: "Virus").contains("boom"))
    }
}
