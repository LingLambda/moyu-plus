import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class WindowSwitchService {
    private let diagnostics = DiagnosticsLog(category: "WindowDiscovery")
    private var isAccessibilityAuthorized: Bool { AXIsProcessTrustedWithOptions(nil) }

    func discoverWindows() -> WindowDiscoveryResult {
        let trusted = isAccessibilityAuthorized
        guard trusted else {
            diagnostics.notice("Window scan skipped: AXIsProcessTrusted=false")
            return WindowDiscoveryResult(targets: [], state: .unauthorized)
        }

        let snapshot = currentSpaceSnapshot()
        guard snapshot.hasCurrentSpaceSnapshot else {
            diagnostics.error("Window scan failed: Core Graphics current-Space snapshot unavailable")
            return WindowDiscoveryResult(targets: [], state: .snapshotUnavailable)
        }
        var targets: [WindowTarget] = []
        var attemptedApplicationCount = 0
        var successfulQueryCount = 0
        var failures: [WindowQueryFailure] = []

        for entry in runningWindowApplications() {
            let application = entry.application
            guard snapshot.allowsWindows(for: application.processIdentifier) else { continue }
            attemptedApplicationCount += 1
            let signatures = snapshot.signatures(for: application.processIdentifier)
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            let timeoutError = AXUIElementSetMessagingTimeout(appElement, 1)
            if timeoutError != .success {
                diagnostics.error(
                    "Failed to set AX timeout: app=\(entry.applicationName) " +
                    "bundle=\(entry.bundleIdentifier) pid=\(application.processIdentifier) " +
                    "error=\(Self.errorName(timeoutError))(\(timeoutError.rawValue))"
                )
            }
            let query = axWindows(for: appElement)
            guard case let .success(windows) = query else {
                if case let .failure(error) = query {
                    let failure = WindowQueryFailure(
                        bundleIdentifier: entry.bundleIdentifier,
                        applicationName: entry.applicationName,
                        processIdentifier: application.processIdentifier,
                        errorCode: error.rawValue,
                        errorName: Self.errorName(error)
                    )
                    failures.append(failure)
                    diagnostics.error(
                        "AX windows query failed: app=\(failure.applicationName) " +
                        "bundle=\(failure.bundleIdentifier) pid=\(failure.processIdentifier) " +
                        "error=\(failure.errorName)(\(failure.errorCode))"
                    )
                }
                continue
            }
            successfulQueryCount += 1
            let candidates = windows.compactMap(windowDescriptor)
            for candidate in currentSpaceWindows(from: candidates, matching: signatures) {
                targets.append(WindowTarget(
                    bundleIdentifier: entry.bundleIdentifier,
                    applicationName: application.localizedName ?? entry.bundleIdentifier,
                    windowTitle: candidate.title,
                    windowID: candidate.windowID
                ))
            }
        }

        let sortedTargets = sorted(targets)
        let state = WindowDiscoveryState.resolve(
            hasCurrentSpaceSnapshot: snapshot.hasCurrentSpaceSnapshot,
            targetCount: sortedTargets.count,
            attemptedApplicationCount: attemptedApplicationCount,
            successfulQueryCount: successfulQueryCount
        )
        let failureSummary = Dictionary(grouping: failures, by: \.errorName)
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
        diagnostics.notice(
            "Window scan complete: trusted=\(trusted) attempted=\(attemptedApplicationCount) " +
            "successful=\(successfulQueryCount) targets=\(sortedTargets.count) state=\(state) " +
            "failures=[\(failureSummary)]"
        )
        return WindowDiscoveryResult(targets: sortedTargets, state: state, failures: failures)
    }

    func icon(for target: ApplicationTarget) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: target.bundleIdentifier
        ) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func sorted(_ targets: [WindowTarget]) -> [WindowTarget] {
        targets.sorted {
            if $0.applicationName == $1.applicationName {
                return $0.windowTitle.localizedStandardCompare($1.windowTitle) == .orderedAscending
            }
            return $0.applicationName.localizedStandardCompare($1.applicationName) == .orderedAscending
        }
    }

    func chooseApplication() -> ApplicationTarget? {
        let panel = NSOpenPanel()
        panel.title = "选择 App"
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return ApplicationTarget(bundleIdentifier: bundleIdentifier, applicationName: name)
    }

    func execute(
        window1: WindowTarget?,
        window2: WindowTarget?,
        app1: ApplicationTarget?,
        app2: ApplicationTarget?,
        order: [WindowActionPriority] = WindowActionOrder.default,
        trackingMode: WindowTrackingMode = .automaticIDFirst
    ) async -> WindowActionResult {
        let steps = WindowActionPlan.steps(
            window1: window1,
            window2: window2,
            app1: app1,
            app2: app2,
            order: order
        )
        diagnostics.notice(
            "Window action started: trackingMode=\(trackingMode.rawValue) " +
            "order=\(WindowActionOrder.normalized(order).map(\.rawValue).joined(separator: ","))"
        )
        guard !steps.isEmpty else { return .noTargets }
        var failures: [String] = []

        for step in steps {
            switch step {
            case let .window(target, role):
                if activateWindow(target, trackingMode: trackingMode) {
                    return .completed(role)
                }
                failures.append("\(role.title)“\(target.windowTitle)”当前不可用")
            case let .application(target, role):
                if await activateApplication(target) {
                    return .completed(role)
                }
                failures.append("无法打开\(role.title)“\(target.applicationName)”")
            }
        }

        return .failed(failures.joined(separator: "；"))
    }

    private func activateWindow(_ target: WindowTarget, trackingMode: WindowTrackingMode) -> Bool {
        guard isAccessibilityAuthorized else { return false }
        let snapshot = currentSpaceSnapshot()
        var candidates: [AXWindowActivationCandidate] = []
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: target.bundleIdentifier
        ) where snapshot.allowsWindows(for: application.processIdentifier) {
            let visibleWindows = snapshot.signatures(for: application.processIdentifier)
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 1)
            let query = axWindows(for: appElement)
            guard case let .success(windows) = query else {
                if case let .failure(error) = query {
                    diagnostics.error(
                        "AX activation query failed: bundle=\(target.bundleIdentifier) " +
                        "pid=\(application.processIdentifier) " +
                        "error=\(Self.errorName(error))(\(error.rawValue))"
                    )
                }
                continue
            }
            let descriptors = currentSpaceWindows(
                from: windows.compactMap(windowDescriptor),
                matching: visibleWindows
            )
            candidates.append(contentsOf: descriptors.map {
                AXWindowActivationCandidate(application: application, descriptor: $0)
            })
        }

        guard let candidate = matchingWindow(
            target,
            in: candidates,
            trackingMode: trackingMode
        ) else { return false }
        let window = candidate.descriptor.element

        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        let activated = candidate.application.activate(options: [])
        return raised && activated
    }

    private func matchingWindow(
        _ target: WindowTarget,
        in candidates: [AXWindowActivationCandidate],
        trackingMode: WindowTrackingMode
    ) -> AXWindowActivationCandidate? {
        WindowTargetMatcher.match(
            windowID: target.windowID,
            windowTitle: target.windowTitle,
            in: candidates,
            mode: trackingMode,
            candidateWindowID: \.windowID,
            candidateWindowTitle: \.title
        )
    }

    private func activateApplication(_ target: ApplicationTarget) async -> Bool {
        if let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: target.bundleIdentifier
        ).first {
            return application.activate(options: [.activateAllWindows])
        }
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: target.bundleIdentifier
        ) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) {
                application,
                error in
                continuation.resume(returning: application != nil && error == nil)
            }
        }
    }

    private func axWindows(for application: AXUIElement) -> AXWindowsQueryResult {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        )
        guard error == .success else { return .failure(error) }
        return .success(value as? [AXUIElement] ?? [])
    }

    private func windowTitle(for window: AXUIElement) -> String? {
        guard let title = stringAttribute(kAXTitleAttribute, from: window)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }

    private func windowDescriptor(for window: AXUIElement) -> AXWindowDescriptor? {
        guard let title = windowTitle(for: window) else { return nil }
        return AXWindowDescriptor(
            element: window,
            windowID: windowID(of: window),
            title: title,
            frame: frame(of: window)
        )
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return CGWindowID(number.uint32Value)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func currentSpaceSnapshot() -> WindowSnapshot {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return .unavailable }
        let layerZeroWindows = windows.filter { info in
            (info[kCGWindowLayer as String] as? Int) == 0
        }
        let signatures: [VisibleWindowSignature] = layerZeroWindows.compactMap { info -> VisibleWindowSignature? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width > 0,
                  bounds.height > 0 else { return nil }
            return VisibleWindowSignature(
                windowID: CGWindowID(windowNumber.uint32Value),
                pid: pid,
                title: info[kCGWindowName as String] as? String,
                frame: bounds
            )
        }
        guard layerZeroWindows.isEmpty || !signatures.isEmpty else { return .unavailable }
        return .currentSpace(signatures)
    }

    private func runningWindowApplications() -> [(
        application: NSRunningApplication,
        bundleIdentifier: String,
        applicationName: String
    )] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.activationPolicy == .regular,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let bundleIdentifier = application.bundleIdentifier else { return nil }
            return (
                application: application,
                bundleIdentifier: bundleIdentifier,
                applicationName: application.localizedName ?? bundleIdentifier
            )
        }
    }

    private static func errorName(_ error: AXError) -> String {
        switch error {
        case .success: "success"
        case .failure: "failure"
        case .illegalArgument: "illegalArgument"
        case .invalidUIElement: "invalidUIElement"
        case .invalidUIElementObserver: "invalidUIElementObserver"
        case .cannotComplete: "cannotComplete"
        case .attributeUnsupported: "attributeUnsupported"
        case .actionUnsupported: "actionUnsupported"
        case .notificationUnsupported: "notificationUnsupported"
        case .notImplemented: "notImplemented"
        case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
        case .notificationNotRegistered: "notificationNotRegistered"
        case .apiDisabled: "apiDisabled"
        case .noValue: "noValue"
        case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: "notEnoughPrecision"
        @unknown default: "unknown"
        }
    }

    private func currentSpaceWindows(
        from candidates: [AXWindowDescriptor],
        matching signatures: [VisibleWindowSignature]
    ) -> [AXWindowDescriptor] {
        let visibleWindowIDs = Set(signatures.map(\.windowID))
        let exactIndexes = Set(candidates.indices.filter { index in
            candidates[index].windowID.map(visibleWindowIDs.contains) ?? false
        })
        let exactWindowIDs = Set(exactIndexes.compactMap { candidates[$0].windowID })
        let fallbackCandidateIndexes = candidates.indices.filter { candidates[$0].windowID == nil }
        let fallbackSignatures = signatures.enumerated().filter { !exactWindowIDs.contains($0.element.windowID) }
        let candidateMatches = fallbackCandidateIndexes.map { candidateIndex in
            fallbackSignatures.compactMap { signatureIndex, signature in
                fallbackMatches(candidates[candidateIndex], signature) ? signatureIndex : nil
            }
        }
        let acceptedFallbackOffsets = CurrentSpaceWindowMatcher.unambiguousFallbackIndexes(
            candidateToSignatureIndexes: candidateMatches
        )
        let acceptedFallbackIndexes = Set(
            acceptedFallbackOffsets.map { fallbackCandidateIndexes[$0] }
        )
        return candidates.indices.filter { index in
            CurrentSpaceWindowMatcher.isVisible(
                windowID: candidates[index].windowID,
                visibleWindowIDs: visibleWindowIDs,
                fallbackMatch: acceptedFallbackIndexes.contains(index)
            )
        }.map { candidates[$0] }
    }

    private func fallbackMatches(
        _ candidate: AXWindowDescriptor,
        _ signature: VisibleWindowSignature
    ) -> Bool {
        if let candidateFrame = candidate.frame {
            return substantiallyOverlaps(candidateFrame, signature.frame)
        }
        guard let signatureTitle = signature.title, !signatureTitle.isEmpty else { return false }
        return candidate.title == signatureTitle
    }

    private func substantiallyOverlaps(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return false }
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard smallerArea > 0 else { return false }
        return intersection.width * intersection.height / smallerArea >= 0.75
    }
}

private enum AXWindowsQueryResult {
    case success([AXUIElement])
    case failure(AXError)
}

private struct AXWindowDescriptor {
    let element: AXUIElement
    let windowID: CGWindowID?
    let title: String
    let frame: CGRect?
}

private struct AXWindowActivationCandidate {
    let application: NSRunningApplication
    let descriptor: AXWindowDescriptor

    var windowID: CGWindowID? { descriptor.windowID }
    var title: String { descriptor.title }
}

private enum WindowSnapshot {
    case unavailable
    case currentSpace([VisibleWindowSignature])

    var hasCurrentSpaceSnapshot: Bool {
        if case .currentSpace = self { return true }
        return false
    }

    func signatures(for pid: pid_t) -> [VisibleWindowSignature] {
        guard case let .currentSpace(signatures) = self else { return [] }
        return signatures.filter { $0.pid == pid }
    }

    func allowsWindows(for pid: pid_t) -> Bool {
        switch self {
        case .unavailable:
            return false
        case let .currentSpace(signatures):
            return signatures.contains { $0.pid == pid }
        }
    }
}

private struct VisibleWindowSignature {
    let windowID: CGWindowID
    let pid: pid_t
    let title: String?
    let frame: CGRect
}
