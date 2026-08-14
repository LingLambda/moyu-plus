import Foundation
import Testing
@testable import MoyuPro

struct WindowActionPlanTests {
    private let primary = WindowTarget(
        bundleIdentifier: "com.example.primary",
        applicationName: "Primary",
        windowTitle: "Main"
    )
    private let backup = WindowTarget(
        bundleIdentifier: "com.example.backup",
        applicationName: "Backup",
        windowTitle: "Alternate"
    )
    private let fallback = ApplicationTarget(
        bundleIdentifier: "com.example.fallback",
        applicationName: "Fallback"
    )
    private let secondApp = ApplicationTarget(
        bundleIdentifier: "com.example.second",
        applicationName: "Second"
    )

    @Test func ordersPrimaryBackupAndFallback() {
        #expect(WindowActionPlan.steps(
            window1: primary,
            window2: backup,
            app1: fallback,
            app2: secondApp
        ) == [
            .window(primary, .primaryWindow),
            .window(backup, .backupWindow),
            .application(fallback, .fallbackApp),
            .application(secondApp, .secondApp),
        ])
    }

    @Test func omitsUnconfiguredStepsWithoutChangingOrder() {
        #expect(WindowActionPlan.steps(
            window1: nil,
            window2: backup,
            app1: fallback,
            app2: nil
        ) == [
            .window(backup, .backupWindow),
            .application(fallback, .fallbackApp),
        ])
    }

    @Test func doesNotTryTheSameWindowTwice() {
        let sameApplicationDifferentName = ApplicationTarget(
            bundleIdentifier: fallback.bundleIdentifier,
            applicationName: "Renamed fallback"
        )
        #expect(WindowActionPlan.steps(
            window1: primary,
            window2: primary,
            app1: fallback,
            app2: sameApplicationDifferentName
        ) == [
            .window(primary, .primaryWindow),
            .application(fallback, .fallbackApp),
        ])
    }

    @Test func supportsFallbackAppFirst() {
        #expect(WindowActionPlan.steps(
            window1: primary,
            window2: backup,
            app1: fallback,
            app2: secondApp,
            order: [.secondApp, .fallbackApp, .primaryWindow, .backupWindow]
        ) == [
            .application(secondApp, .secondApp),
            .application(fallback, .fallbackApp),
            .window(primary, .primaryWindow),
            .window(backup, .backupWindow),
        ])
    }

    @Test func malformedActionOrderUsesDefault() {
        #expect(WindowActionOrder.normalized([.fallbackApp]) == WindowActionOrder.default)
        #expect(WindowActionOrder.normalized([.fallbackApp, .primaryWindow, .backupWindow]) == [
            .fallbackApp,
            .primaryWindow,
            .backupWindow,
            .secondApp,
        ])
        #expect(WindowActionOrder.normalized([
            .secondApp,
            .fallbackApp,
            .primaryWindow,
            .backupWindow,
        ]) == [
            .secondApp,
            .fallbackApp,
            .primaryWindow,
            .backupWindow,
        ])
    }

    @Test func automaticTrackingPrefersIDAndFallsBackToTitle() {
        let saved = WindowTarget(
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            windowTitle: "Old title",
            windowID: 42
        )
        #expect(saved.isResolvable(among: [
            WindowTarget(
                bundleIdentifier: "com.example.app",
                applicationName: "Example",
                windowTitle: "New title",
                windowID: 42
            )
        ], mode: .automaticIDFirst))
        #expect(!saved.isResolvable(among: [
            WindowTarget(
                bundleIdentifier: "com.example.app",
                applicationName: "Example",
                windowTitle: "New title",
                windowID: 7
            )
        ], mode: .strictWindowID))
        #expect(saved.isResolvable(among: [
            WindowTarget(
                bundleIdentifier: "com.example.app",
                applicationName: "Example",
                windowTitle: "Old title",
                windowID: 7
            )
        ], mode: .exactTitle))
    }

    @Test func automaticTrackingRejectsAmbiguousTitleFallback() {
        let saved = WindowTarget(
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            windowTitle: "Untitled",
            windowID: 42
        )
        let candidates = [1, 2].map { windowID in
            WindowTarget(
                bundleIdentifier: "com.example.app",
                applicationName: "Example",
                windowTitle: "Untitled",
                windowID: UInt32(windowID)
            )
        }

        #expect(!saved.isResolvable(among: candidates, mode: .automaticIDFirst))
        #expect(saved.refreshedCandidate(among: candidates, allowTitleFallback: true) == nil)
        #expect(saved.isResolvable(among: candidates, mode: .exactTitle))
    }

    @Test func legacyWindowTargetDecodesWithoutWindowID() throws {
        let data = #"{"bundleIdentifier":"com.example.app","applicationName":"Example","windowTitle":"Main"}"#
            .data(using: .utf8)!
        let target = try JSONDecoder().decode(WindowTarget.self, from: data)
        #expect(target.windowID == nil)

        let tracked = WindowTarget(
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            windowTitle: "Main",
            windowID: 42
        )
        let roundTrip = try JSONDecoder().decode(
            WindowTarget.self,
            from: JSONEncoder().encode(tracked)
        )
        #expect(roundTrip.windowID == 42)
    }

    @Test func duplicateTitlesRemainDistinctByWindowID() {
        let first = WindowTarget(
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            windowTitle: "Untitled",
            windowID: 1
        )
        let second = WindowTarget(
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            windowTitle: "Untitled",
            windowID: 2
        )
        #expect(first != second)
        #expect(first.id != second.id)
        #expect(Set([first, second]).count == 2)

        let legacy = WindowTarget(
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            windowTitle: "Untitled"
        )
        #expect(legacy.refreshedCandidate(among: [first], allowTitleFallback: true) == first)
        #expect(legacy.refreshedCandidate(among: [first, second], allowTitleFallback: true) == nil)
    }

    @Test func automaticTrackingRejectsDuplicateTitlesWithoutWindowIDs() {
        let saved = WindowTarget(
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            windowTitle: "Untitled"
        )

        #expect(!saved.isResolvable(among: [saved, saved], mode: .automaticIDFirst))
        #expect(saved.refreshedCandidate(
            among: [saved, saved],
            allowTitleFallback: true
        ) == nil)
        #expect(saved.isResolvable(among: [saved, saved], mode: .exactTitle))
    }

    @Test func knownWindowIDMustBelongToCurrentSpace() {
        #expect(CurrentSpaceWindowMatcher.isVisible(
            windowID: 12,
            visibleWindowIDs: [42],
            fallbackMatch: true
        ) == false)
        #expect(CurrentSpaceWindowMatcher.isVisible(
            windowID: 42,
            visibleWindowIDs: [42],
            fallbackMatch: false
        ))
    }

    @Test func missingWindowIDUsesCompatibilityFallback() {
        #expect(CurrentSpaceWindowMatcher.isVisible(
            windowID: nil,
            visibleWindowIDs: [],
            fallbackMatch: true
        ))
    }

    @Test func compatibilityMatcherOnlyAcceptsOneToOneFallbacks() {
        #expect(CurrentSpaceWindowMatcher.unambiguousFallbackIndexes(
            candidateToSignatureIndexes: [[0], [1]]
        ) == [0, 1])
        #expect(CurrentSpaceWindowMatcher.unambiguousFallbackIndexes(
            candidateToSignatureIndexes: [[0], [0]]
        ).isEmpty)
        #expect(CurrentSpaceWindowMatcher.unambiguousFallbackIndexes(
            candidateToSignatureIndexes: [[0, 1]]
        ).isEmpty)
    }

    @Test func discoveryStateDistinguishesPermissionLagFromNoWindows() {
        #expect(WindowDiscoveryState.resolve(
            hasCurrentSpaceSnapshot: true,
            targetCount: 0,
            attemptedApplicationCount: 3,
            successfulQueryCount: 0
        ) == .accessibilityUnavailable)
        #expect(WindowDiscoveryState.resolve(
            hasCurrentSpaceSnapshot: true,
            targetCount: 0,
            attemptedApplicationCount: 3,
            successfulQueryCount: 1
        ) == .noWindows)
        #expect(WindowDiscoveryState.resolve(
            hasCurrentSpaceSnapshot: true,
            targetCount: 0,
            attemptedApplicationCount: 3,
            successfulQueryCount: 3
        ) == .noWindows)
    }

    @Test func discoveryStateRequiresCurrentSpaceSnapshot() {
        #expect(WindowDiscoveryState.resolve(
            hasCurrentSpaceSnapshot: false,
            targetCount: 1,
            attemptedApplicationCount: 2,
            successfulQueryCount: 2
        ) == .snapshotUnavailable)
        #expect(WindowDiscoveryState.resolve(
            hasCurrentSpaceSnapshot: false,
            targetCount: 0,
            attemptedApplicationCount: 0,
            successfulQueryCount: 0
        ) == .snapshotUnavailable)
    }
}
