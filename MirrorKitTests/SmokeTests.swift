import Testing
@testable import MirrorKit

@Suite("Smoke")
struct SmokeTests {
    @Test func testTargetCompilesAndRuns() {
        #expect(true)
    }
}
