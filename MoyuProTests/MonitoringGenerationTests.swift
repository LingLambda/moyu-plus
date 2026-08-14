import Testing
@testable import MoyuPro

struct MonitoringGenerationTests {
    @Test func rejectsFramesAfterPauseOrNewSession() {
        var generation = MonitoringGeneration()
        let first = generation.begin()
        #expect(generation.accepts(first, isEnabled: true))
        #expect(!generation.accepts(first, isEnabled: false))

        generation.invalidate()
        #expect(!generation.accepts(first, isEnabled: true))

        let second = generation.begin()
        #expect(second != first)
        #expect(generation.accepts(second, isEnabled: true))
    }
}
