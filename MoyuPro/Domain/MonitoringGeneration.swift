import Foundation

struct MonitoringGeneration: Equatable, Sendable {
    private(set) var value: UInt64 = 0

    mutating func begin() -> UInt64 {
        value &+= 1
        return value
    }

    mutating func invalidate() {
        value &+= 1
    }

    func accepts(_ candidate: UInt64, isEnabled: Bool) -> Bool {
        isEnabled && candidate == value
    }
}
