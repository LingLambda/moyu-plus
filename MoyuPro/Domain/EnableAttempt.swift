import Foundation

struct EnableAttempt: Equatable, Sendable {
    private(set) var value: UInt64 = 0
    private(set) var isPending = false

    mutating func begin() -> UInt64 {
        value &+= 1
        isPending = true
        return value
    }

    mutating func cancel() {
        value &+= 1
        isPending = false
    }

    mutating func finish(_ candidate: UInt64) -> Bool {
        guard accepts(candidate) else { return false }
        isPending = false
        return true
    }

    func accepts(_ candidate: UInt64) -> Bool {
        isPending && candidate == value
    }
}
