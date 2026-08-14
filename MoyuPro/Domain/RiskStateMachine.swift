import Foundation

enum GuardPhase: Equatable, Sendable {
    case normal
    case suspected(startedAt: ContinuousClock.Instant)
    case triggered(triggeredAt: ContinuousClock.Instant)
    case clearing(startedAt: ContinuousClock.Instant)

    var isTriggered: Bool {
        switch self {
        case .triggered, .clearing: true
        default: false
        }
    }

    var isSuspected: Bool {
        if case .suspected = self { return true }
        return false
    }

    var isClearing: Bool {
        if case .clearing = self { return true }
        return false
    }
}

enum RiskTransition: Equatable, Sendable {
    case none
    case triggered
    case restored
}

struct RiskRules: Equatable, Sendable {
    var triggerPersonCount = 2
    var recoveryPersonCount = 1
    var confirmationDuration: Duration = .milliseconds(80)
    var manualRecovery = true
    var recoveryDuration: Duration = .seconds(5)

    var normalized: RiskRules {
        var copy = self
        copy.triggerPersonCount = min(6, max(2, triggerPersonCount))
        copy.recoveryPersonCount = min(copy.triggerPersonCount - 1, max(0, recoveryPersonCount))
        copy.confirmationDuration = max(.zero, min(.seconds(2), confirmationDuration))
        return copy
    }
}

struct RiskStateMachine: Sendable {
    private(set) var phase: GuardPhase = .normal

    mutating func process(
        personCount: Int,
        at now: ContinuousClock.Instant,
        rules rawRules: RiskRules = RiskRules()
    ) -> RiskTransition {
        let rules = rawRules.normalized
        switch phase {
        case .normal:
            if personCount >= rules.triggerPersonCount {
                phase = .suspected(startedAt: now)
            }
            return .none
        case let .suspected(startedAt):
            guard personCount >= rules.triggerPersonCount else {
                phase = .normal
                return .none
            }
            guard startedAt.duration(to: now) >= rules.confirmationDuration else {
                return .none
            }
            phase = .triggered(triggeredAt: now)
            return .triggered
        case .triggered:
            guard !rules.manualRecovery,
                  personCount <= rules.recoveryPersonCount else {
                return .none
            }
            phase = .clearing(startedAt: now)
            return .none
        case let .clearing(startedAt):
            guard !rules.manualRecovery else {
                phase = .triggered(triggeredAt: now)
                return .none
            }
            guard personCount <= rules.recoveryPersonCount else {
                phase = .triggered(triggeredAt: now)
                return .none
            }
            guard startedAt.duration(to: now) >= rules.recoveryDuration else {
                return .none
            }
            phase = .normal
            return .restored
        }
    }

    func recoveryRemaining(at now: ContinuousClock.Instant, duration: Duration) -> Duration? {
        guard case let .clearing(startedAt) = phase else { return nil }
        return max(.zero, duration - startedAt.duration(to: now))
    }

    mutating func reconfigure(at now: ContinuousClock.Instant) {
        switch phase {
        case .suspected:
            phase = .normal
        case .clearing:
            phase = .triggered(triggeredAt: now)
        case .normal, .triggered:
            break
        }
    }

    mutating func restore() {
        phase = .normal
    }
}
