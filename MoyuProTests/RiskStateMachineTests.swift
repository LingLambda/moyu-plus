import Testing
@testable import MoyuPro

struct RiskStateMachineTests {
    @Test func defaultConfirmationDelayIs80Milliseconds() {
        #expect(RiskRules().confirmationDuration == .milliseconds(80))
    }

    @Test func defaultAutomaticRecoveryDelayIsFiveSeconds() {
        #expect(RiskRules().recoveryDuration == .seconds(5))
    }

    @Test func requiresContinuousConfirmation() {
        let clock = ContinuousClock()
        let start = clock.now
        var machine = RiskStateMachine()
        let rules = RiskRules(confirmationDuration: .milliseconds(800))

        let firstResult = machine.process(personCount: 2, at: start, rules: rules)
        #expect(firstResult == .none)
        #expect(machine.phase.isSuspected)
        let earlyResult = machine.process(personCount: 2, at: start.advanced(by: .milliseconds(799)), rules: rules)
        #expect(earlyResult == .none)
        let confirmedResult = machine.process(personCount: 2, at: start.advanced(by: .milliseconds(800)), rules: rules)
        #expect(confirmedResult == .triggered)
        #expect(machine.phase.isTriggered)
    }

    @Test func singlePersonResetsSuspicion() {
        let clock = ContinuousClock()
        let start = clock.now
        var machine = RiskStateMachine()
        let rules = RiskRules(confirmationDuration: .milliseconds(800))

        _ = machine.process(personCount: 2, at: start, rules: rules)
        _ = machine.process(personCount: 1, at: start.advanced(by: .milliseconds(500)), rules: rules)
        #expect(machine.phase == .normal)
        let restartedResult = machine.process(personCount: 2, at: start.advanced(by: .seconds(1)), rules: rules)
        #expect(restartedResult == .none)
    }

    @Test func triggeredStateDoesNotRepeatUntilRestore() {
        let clock = ContinuousClock()
        let start = clock.now
        var machine = RiskStateMachine()
        let rules = RiskRules(confirmationDuration: .milliseconds(100))

        _ = machine.process(personCount: 2, at: start, rules: rules)
        let triggeredResult = machine.process(personCount: 2, at: start.advanced(by: .milliseconds(100)), rules: rules)
        #expect(triggeredResult == .triggered)
        let repeatedResult = machine.process(personCount: 2, at: start.advanced(by: .seconds(1)), rules: rules)
        #expect(repeatedResult == .none)

        machine.restore()
        let restoredResult = machine.process(personCount: 2, at: start.advanced(by: .seconds(2)), rules: rules)
        #expect(restoredResult == .none)
    }

    @Test func automaticallyRestoresAfterConfiguredClearDuration() {
        let clock = ContinuousClock()
        let start = clock.now
        var machine = RiskStateMachine()
        let rules = RiskRules(
            triggerPersonCount: 3,
            recoveryPersonCount: 1,
            confirmationDuration: .milliseconds(100),
            manualRecovery: false,
            recoveryDuration: .seconds(3)
        )

        _ = machine.process(personCount: 3, at: start, rules: rules)
        #expect(machine.process(personCount: 3, at: start.advanced(by: .milliseconds(100)), rules: rules) == .triggered)
        #expect(machine.process(personCount: 1, at: start.advanced(by: .seconds(1)), rules: rules) == .none)
        #expect(machine.phase.isClearing)
        #expect(machine.process(personCount: 1, at: start.advanced(by: .seconds(3.9)), rules: rules) == .none)
        #expect(machine.process(personCount: 1, at: start.advanced(by: .seconds(4)), rules: rules) == .restored)
        #expect(machine.phase == .normal)
    }

    @Test func recoveryCountdownIsCancelledWhenPeopleReturn() {
        let clock = ContinuousClock()
        let start = clock.now
        var machine = RiskStateMachine()
        let rules = RiskRules(
            confirmationDuration: .milliseconds(100),
            manualRecovery: false,
            recoveryDuration: .seconds(3)
        )

        _ = machine.process(personCount: 2, at: start, rules: rules)
        _ = machine.process(personCount: 2, at: start.advanced(by: .milliseconds(100)), rules: rules)
        _ = machine.process(personCount: 1, at: start.advanced(by: .seconds(1)), rules: rules)
        #expect(machine.phase.isClearing)
        _ = machine.process(personCount: 2, at: start.advanced(by: .seconds(2)), rules: rules)
        #expect(machine.phase.isTriggered)
        _ = machine.process(personCount: 1, at: start.advanced(by: .seconds(3)), rules: rules)
        #expect(machine.process(personCount: 1, at: start.advanced(by: .seconds(5.9)), rules: rules) == .none)
        #expect(machine.process(personCount: 1, at: start.advanced(by: .seconds(6)), rules: rules) == .restored)
    }

    @Test func manualModeNeverStartsAutomaticRecovery() {
        let clock = ContinuousClock()
        let start = clock.now
        var machine = RiskStateMachine()
        let rules = RiskRules(confirmationDuration: .zero, manualRecovery: true, recoveryDuration: .seconds(1))

        _ = machine.process(personCount: 2, at: start, rules: rules)
        _ = machine.process(personCount: 2, at: start, rules: rules)
        _ = machine.process(personCount: 0, at: start.advanced(by: .seconds(30)), rules: rules)
        #expect(machine.phase.isTriggered)
    }

    @Test func rulesClampRecoveryBelowTrigger() {
        let rules = RiskRules(triggerPersonCount: 2, recoveryPersonCount: 5).normalized
        #expect(rules.triggerPersonCount == 2)
        #expect(rules.recoveryPersonCount == 1)
    }

    @Test func confirmationDelayCanBeCustomizedAndIsClamped() {
        #expect(RiskRules(confirmationDuration: .milliseconds(240)).normalized.confirmationDuration == .milliseconds(240))
        #expect(RiskRules(confirmationDuration: .zero).normalized.confirmationDuration == .zero)
        #expect(RiskRules(confirmationDuration: .seconds(5)).normalized.confirmationDuration == .seconds(2))
    }
}
