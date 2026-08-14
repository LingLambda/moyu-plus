import Testing
@testable import MoyuPro

struct EnableAttemptTests {
    @Test func cancellationRejectsPendingPermissionResult() {
        var attempt = EnableAttempt()
        let candidate = attempt.begin()
        #expect(attempt.accepts(candidate))

        attempt.cancel()
        #expect(!attempt.accepts(candidate))
        #expect(!attempt.isPending)
    }

    @Test func newerAttemptRejectsOlderPermissionResult() {
        var attempt = EnableAttempt()
        let first = attempt.begin()
        let second = attempt.begin()

        #expect(!attempt.accepts(first))
        #expect(attempt.accepts(second))
        let didFinish = attempt.finish(second)
        #expect(didFinish)
        #expect(!attempt.accepts(second))
    }
}
