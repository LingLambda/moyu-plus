import Foundation
import CoreGraphics

struct WindowTarget: Codable, Hashable, Identifiable, Sendable {
    let bundleIdentifier: String
    let applicationName: String
    let windowTitle: String
    let windowID: CGWindowID?

    init(
        bundleIdentifier: String,
        applicationName: String,
        windowTitle: String,
        windowID: CGWindowID? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.windowID = windowID
    }

    var id: String {
        if let windowID {
            return "\(bundleIdentifier)\u{0}id:\(windowID)"
        }
        return "\(bundleIdentifier)\u{0}title:\(windowTitle)"
    }

    var displayName: String {
        guard let windowID else { return "\(applicationName) - \(windowTitle)" }
        return "\(applicationName) - \(windowTitle)（ID \(windowID)）"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.windowTitle == rhs.windowTitle &&
        lhs.windowID == rhs.windowID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
        hasher.combine(windowTitle)
        hasher.combine(windowID)
    }
}

struct ApplicationTarget: Codable, Hashable, Identifiable, Sendable {
    let bundleIdentifier: String
    let applicationName: String

    var id: String { bundleIdentifier }
}

enum WindowTrackingMode: String, CaseIterable, Codable, Sendable {
    case automaticIDFirst
    case strictWindowID
    case exactTitle

    var title: String {
        switch self {
        case .automaticIDFirst: "自动跟踪（ID 优先）"
        case .strictWindowID: "严格窗口 ID"
        case .exactTitle: "仅匹配标题"
        }
    }

    var detail: String {
        switch self {
        case .automaticIDFirst:
            "优先使用窗口 ID，标题变化仍可继续跟踪；窗口重建或 App 重启后按标题回退。"
        case .strictWindowID:
            "只跟踪保存的窗口 ID；窗口重建或 App 重启后需要重新选择。"
        case .exactTitle:
            "只匹配完整窗口标题；标题变化后需要重新选择。"
        }
    }
}

enum WindowActionPriority: String, CaseIterable, Codable, Hashable, Sendable {
    case primaryWindow
    case backupWindow
    case fallbackApp
    case secondApp

    var title: String {
        switch self {
        case .primaryWindow: "窗口 1"
        case .backupWindow: "窗口 2"
        case .fallbackApp: "App 1"
        case .secondApp: "App 2"
        }
    }

    var symbolName: String {
        switch self {
        case .primaryWindow: "1.circle"
        case .backupWindow: "2.circle"
        case .fallbackApp: "app"
        case .secondApp: "app.fill"
        }
    }

    var isWindow: Bool {
        self == .primaryWindow || self == .backupWindow
    }
}

enum WindowActionOrder {
    static let `default`: [WindowActionPriority] = [
        .primaryWindow,
        .backupWindow,
        .fallbackApp,
        .secondApp,
    ]

    static func normalized(_ order: [WindowActionPriority]) -> [WindowActionPriority] {
        let legacyRoles: Set<WindowActionPriority> = [
            .primaryWindow,
            .backupWindow,
            .fallbackApp,
        ]
        if order.count == legacyRoles.count, Set(order) == legacyRoles {
            return order + [.secondApp]
        }
        guard order.count == WindowActionPriority.allCases.count,
              Set(order) == Set(WindowActionPriority.allCases) else {
            return `default`
        }
        return order
    }
}

enum WindowDiscoveryState: Equatable, Sendable {
    case unauthorized
    case ready
    case noWindows
    case snapshotUnavailable
    case accessibilityUnavailable

    static func resolve(
        hasCurrentSpaceSnapshot: Bool,
        targetCount: Int,
        attemptedApplicationCount: Int,
        successfulQueryCount: Int
    ) -> Self {
        guard hasCurrentSpaceSnapshot else { return .snapshotUnavailable }
        if targetCount > 0 { return .ready }
        if attemptedApplicationCount > 0, successfulQueryCount == 0 {
            return .accessibilityUnavailable
        }
        return .noWindows
    }
}

struct WindowDiscoveryResult: Equatable, Sendable {
    let targets: [WindowTarget]
    let state: WindowDiscoveryState
    var failures: [WindowQueryFailure] = []
}

struct WindowQueryFailure: Equatable, Sendable {
    let bundleIdentifier: String
    let applicationName: String
    let processIdentifier: Int32
    let errorCode: Int32
    let errorName: String
}

enum WindowActionStep: Equatable, Sendable {
    case window(WindowTarget, WindowActionPriority)
    case application(ApplicationTarget, WindowActionPriority)
}

enum WindowActionPlan {
    static func steps(
        window1: WindowTarget?,
        window2: WindowTarget?,
        app1: ApplicationTarget?,
        app2: ApplicationTarget?,
        order: [WindowActionPriority] = WindowActionOrder.default
    ) -> [WindowActionStep] {
        var steps: [WindowActionStep] = []
        var addedWindows: Set<WindowTarget> = []
        var addedApplicationBundleIdentifiers: Set<String> = []
        for role in WindowActionOrder.normalized(order) {
            switch role {
            case .primaryWindow:
                if let window1, addedWindows.insert(window1).inserted {
                    steps.append(.window(window1, role))
                }
            case .backupWindow:
                if let window2, addedWindows.insert(window2).inserted {
                    steps.append(.window(window2, role))
                }
            case .fallbackApp:
                if let app1,
                   addedApplicationBundleIdentifiers.insert(app1.bundleIdentifier).inserted {
                    steps.append(.application(app1, role))
                }
            case .secondApp:
                if let app2,
                   addedApplicationBundleIdentifiers.insert(app2.bundleIdentifier).inserted {
                    steps.append(.application(app2, role))
                }
            }
        }
        return steps
    }
}

extension WindowTarget {
    func isResolvable(among targets: [WindowTarget], mode: WindowTrackingMode) -> Bool {
        let sameApplication = targets.filter { $0.bundleIdentifier == bundleIdentifier }
        return WindowTargetMatcher.match(
            windowID: windowID,
            windowTitle: windowTitle,
            in: sameApplication,
            mode: mode,
            candidateWindowID: \.windowID,
            candidateWindowTitle: \.windowTitle
        ) != nil
    }

    func refreshedCandidate(
        among targets: [WindowTarget],
        allowTitleFallback: Bool
    ) -> WindowTarget? {
        let sameApplication = targets.filter { $0.bundleIdentifier == bundleIdentifier }
        return WindowTargetMatcher.match(
            windowID: windowID,
            windowTitle: windowTitle,
            in: sameApplication,
            mode: allowTitleFallback ? .automaticIDFirst : .strictWindowID,
            candidateWindowID: \.windowID,
            candidateWindowTitle: \.windowTitle
        )
    }
}

enum WindowTargetMatcher {
    static func match<Candidate>(
        windowID: CGWindowID?,
        windowTitle: String,
        in candidates: [Candidate],
        mode: WindowTrackingMode,
        candidateWindowID: KeyPath<Candidate, CGWindowID?>,
        candidateWindowTitle: KeyPath<Candidate, String>
    ) -> Candidate? {
        switch mode {
        case .automaticIDFirst:
            if let windowID,
               let exact = candidates.first(where: { $0[keyPath: candidateWindowID] == windowID }) {
                return exact
            }
            let titleMatches = candidates.filter {
                $0[keyPath: candidateWindowTitle] == windowTitle
            }
            return titleMatches.count == 1 ? titleMatches[0] : nil
        case .strictWindowID:
            guard let windowID else { return nil }
            return candidates.first { $0[keyPath: candidateWindowID] == windowID }
        case .exactTitle:
            return candidates.first { $0[keyPath: candidateWindowTitle] == windowTitle }
        }
    }
}

enum WindowActionResult: Equatable, Sendable {
    case completed(WindowActionPriority)
    case noTargets
    case failed(String)
}

enum CurrentSpaceWindowMatcher {
    static func isVisible(
        windowID: CGWindowID?,
        visibleWindowIDs: Set<CGWindowID>,
        fallbackMatch: Bool
    ) -> Bool {
        if let windowID {
            return visibleWindowIDs.contains(windowID)
        }
        return fallbackMatch
    }

    static func unambiguousFallbackIndexes(
        candidateToSignatureIndexes: [[Int]]
    ) -> Set<Int> {
        var signatureUseCounts: [Int: Int] = [:]
        for matches in candidateToSignatureIndexes where matches.count == 1 {
            signatureUseCounts[matches[0], default: 0] += 1
        }

        return Set(candidateToSignatureIndexes.indices.filter { candidateIndex in
            let matches = candidateToSignatureIndexes[candidateIndex]
            guard matches.count == 1, let signatureIndex = matches.first else { return false }
            return signatureUseCounts[signatureIndex] == 1
        })
    }
}
