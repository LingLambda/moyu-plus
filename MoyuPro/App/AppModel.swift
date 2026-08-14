@preconcurrency import AVFoundation
import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private enum DefaultsKey {
        static let onboardingComplete = "onboardingComplete"
        static let protectionEnabled = "protectionEnabled"
        static let selectedCameraID = "selectedCameraID"
        static let previewEnabled = "previewEnabled"
        static let confidenceThreshold = "confidenceThreshold"
        static let minimumAreaRatio = "minimumAreaRatio"
        static let manualRecovery = "manualRecovery"
        static let triggerPersonCount = "triggerPersonCount"
        static let recoveryPersonCount = "recoveryPersonCount"
        static let recoveryDelaySeconds = "recoveryDelaySeconds"
        static let confirmationDelayMilliseconds = "confirmationDelayMilliseconds"
        static let notificationEnabled = "notificationEnabled"
        static let notificationTitle = "notificationTitle"
        static let notificationBody = "notificationBody"
        static let windowSwitchEnabled = "windowSwitchEnabled"
        static let window1Target = "primaryWindowTarget"
        static let window2Target = "backupWindowTarget"
        static let app1ApplicationTarget = "fallbackApplicationTarget"
        static let app2ApplicationTarget = "app2ApplicationTarget"
        static let windowTrackingMode = "windowTrackingMode"
        static let windowActionOrder = "windowActionOrder"
    }

    static let defaultNotificationTitle = "新邮件"
    static let defaultNotificationBody = "您有一条新邮件待查看"

    private let cameraService = CameraService()
    private let notificationService = NotificationService()
    private let windowSwitchService = WindowSwitchService()
    private let accessibilityService = AccessibilityAuthorizationService()
    private let configurationStore = AppConfigurationStore()
    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.ling.MoyuPro", category: "AppModel")
    private let accessibilityDiagnostics = DiagnosticsLog(category: "Accessibility")
    private let cameraDiagnostics = DiagnosticsLog(category: "Camera")
    private var riskMachine = RiskStateMachine()
    private var filter: DetectionFilter
    private var resumeAfterSystemWake = false
    private var monitoringGeneration = MonitoringGeneration()
    private var enableAttempt = EnableAttempt()
    private var lastEvaluationInstant: ContinuousClock.Instant?
    private var accessibilityAuthorizationTask: Task<Void, Never>?

    var status: AppStatus = .disabled
    var isEnabled = false
    var isEnabling: Bool { enableAttempt.isPending }
    var isProtectionRequested: Bool { isEnabled || isEnabling || wantsProtectionEnabled }
    private(set) var wantsProtectionEnabled: Bool
    var onboardingComplete: Bool
    var cameras: [CameraDeviceDescriptor] = []
    var selectedCameraID: String? {
        didSet {
            defaults.set(selectedCameraID, forKey: DefaultsKey.selectedCameraID)
            if isEnabled { cameraService.switchDevice(to: selectedCameraID) }
        }
    }
    var previewEnabled: Bool {
        didSet {
            defaults.set(previewEnabled, forKey: DefaultsKey.previewEnabled)
            cameraService.setPreviewEnabled(previewEnabled)
            if !previewEnabled { latestImage = nil }
        }
    }
    var latestImage: CGImage?
    var snapshot = DetectionSnapshot()
    var validPeople: [Detection] = []
    var loginItemEnabled = false
    var loginItemRequiresApproval = false
    var loginItemError: String?
    var notificationPermissionState: NotificationPermissionState = .notDetermined
    var notificationWarning: String?
    private(set) var cameraAuthorizationStatus = CameraService.authorizationStatus()
    var isSendingTestNotification = false
    var notificationTestMessage: String?
    var notificationTestSucceeded = false
    var accessibilityAuthorized = false
    var windowDiscoveryState: WindowDiscoveryState = .unauthorized
    var availableWindowTargets: [WindowTarget] = []
    var app1ApplicationIcon: NSImage?
    var app2ApplicationIcon: NSImage?
    var windowWarning: String?
    var lastWindowAction: String?
    private(set) var latestWindowQueryFailures: [WindowQueryFailure] = []
    private(set) var privacyProtectionCount: Int
    var confidenceThreshold: Double {
        didSet {
            filter.confidenceThreshold = confidenceThreshold
            defaults.set(confidenceThreshold, forKey: DefaultsKey.confidenceThreshold)
        }
    }
    var minimumAreaRatio: Double {
        didSet {
            filter.minimumAreaRatio = minimumAreaRatio
            defaults.set(minimumAreaRatio, forKey: DefaultsKey.minimumAreaRatio)
        }
    }
    var manualRecovery: Bool {
        didSet {
            defaults.set(manualRecovery, forKey: DefaultsKey.manualRecovery)
            reconfigureRiskMachine()
        }
    }
    var triggerPersonCount: Int {
        didSet {
            let normalized = min(6, max(2, triggerPersonCount))
            if triggerPersonCount != normalized {
                triggerPersonCount = normalized
                return
            }
            if recoveryPersonCount >= triggerPersonCount {
                recoveryPersonCount = triggerPersonCount - 1
            }
            defaults.set(triggerPersonCount, forKey: DefaultsKey.triggerPersonCount)
            reconfigureRiskMachine()
        }
    }
    var recoveryPersonCount: Int {
        didSet {
            let normalized = min(triggerPersonCount - 1, max(0, recoveryPersonCount))
            if recoveryPersonCount != normalized {
                recoveryPersonCount = normalized
                return
            }
            defaults.set(recoveryPersonCount, forKey: DefaultsKey.recoveryPersonCount)
            reconfigureRiskMachine()
        }
    }
    var recoveryDelaySeconds: Int {
        didSet {
            let normalized = min(30, max(1, recoveryDelaySeconds))
            if recoveryDelaySeconds != normalized {
                recoveryDelaySeconds = normalized
                return
            }
            defaults.set(recoveryDelaySeconds, forKey: DefaultsKey.recoveryDelaySeconds)
            reconfigureRiskMachine()
        }
    }
    var confirmationDelayMilliseconds: Int {
        didSet {
            let normalized = min(2_000, max(20, confirmationDelayMilliseconds))
            if confirmationDelayMilliseconds != normalized {
                confirmationDelayMilliseconds = normalized
                return
            }
            defaults.set(confirmationDelayMilliseconds, forKey: DefaultsKey.confirmationDelayMilliseconds)
            reconfigureRiskMachine()
        }
    }
    var notificationEnabled: Bool {
        didSet { defaults.set(notificationEnabled, forKey: DefaultsKey.notificationEnabled) }
    }
    var notificationTitle: String {
        didSet { defaults.set(notificationTitle, forKey: DefaultsKey.notificationTitle) }
    }
    var notificationBody: String {
        didSet { defaults.set(notificationBody, forKey: DefaultsKey.notificationBody) }
    }
    var windowSwitchEnabled: Bool {
        didSet {
            defaults.set(windowSwitchEnabled, forKey: DefaultsKey.windowSwitchEnabled)
            if windowSwitchEnabled {
                requestAccessibilityAuthorization()
            } else {
                accessibilityAuthorizationTask?.cancel()
                accessibilityAuthorizationTask = nil
                windowWarning = nil
                lastWindowAction = nil
            }
        }
    }
    var window1Target: WindowTarget? {
        didSet {
            persist(window1Target, forKey: DefaultsKey.window1Target)
            validateWindowTargets()
        }
    }
    var window2Target: WindowTarget? {
        didSet {
            persist(window2Target, forKey: DefaultsKey.window2Target)
            validateWindowTargets()
        }
    }
    var app1ApplicationTarget: ApplicationTarget? {
        didSet {
            persist(app1ApplicationTarget, forKey: DefaultsKey.app1ApplicationTarget)
            app1ApplicationIcon = app1ApplicationTarget.flatMap(windowSwitchService.icon)
        }
    }
    var app2ApplicationTarget: ApplicationTarget? {
        didSet {
            persist(app2ApplicationTarget, forKey: DefaultsKey.app2ApplicationTarget)
            app2ApplicationIcon = app2ApplicationTarget.flatMap(windowSwitchService.icon)
        }
    }
    var windowTrackingMode: WindowTrackingMode {
        didSet {
            defaults.set(windowTrackingMode.rawValue, forKey: DefaultsKey.windowTrackingMode)
            validateWindowTargets()
        }
    }
    var windowActionOrder: [WindowActionPriority] {
        didSet {
            let normalized = WindowActionOrder.normalized(windowActionOrder)
            if normalized != windowActionOrder {
                windowActionOrder = normalized
                return
            }
            defaults.set(
                windowActionOrder.map(\.rawValue),
                forKey: DefaultsKey.windowActionOrder
            )
        }
    }

    private init() {
        accessibilityDiagnostics.notice(
            "Runtime identity: bundleID=\(Bundle.main.bundleIdentifier ?? "<missing>") " +
            "path=\(Bundle.main.bundlePath) pid=\(ProcessInfo.processInfo.processIdentifier) " +
            "os=\(ProcessInfo.processInfo.operatingSystemVersionString) " +
            "arch=\(ProcessInfo.processInfo.environment["PROCESSOR_ARCHITECTURE"] ?? "native")"
        )
        onboardingComplete = defaults.bool(forKey: DefaultsKey.onboardingComplete)
        wantsProtectionEnabled = defaults.bool(forKey: DefaultsKey.protectionEnabled)
        selectedCameraID = defaults.string(forKey: DefaultsKey.selectedCameraID)
        previewEnabled = defaults.object(forKey: DefaultsKey.previewEnabled) as? Bool ?? true
        let confidence = defaults.object(forKey: DefaultsKey.confidenceThreshold) as? Double ?? 0.25
        let minimumArea = defaults.object(forKey: DefaultsKey.minimumAreaRatio) as? Double ?? 0.012
        confidenceThreshold = confidence
        minimumAreaRatio = minimumArea
        let savedTriggerCount = min(6, max(2, defaults.object(forKey: DefaultsKey.triggerPersonCount) as? Int ?? 2))
        let savedRecoveryCount = min(
            savedTriggerCount - 1,
            max(0, defaults.object(forKey: DefaultsKey.recoveryPersonCount) as? Int ?? 1)
        )
        manualRecovery = defaults.object(forKey: DefaultsKey.manualRecovery) as? Bool ?? true
        triggerPersonCount = savedTriggerCount
        recoveryPersonCount = savedRecoveryCount
        recoveryDelaySeconds = min(30, max(1, defaults.object(forKey: DefaultsKey.recoveryDelaySeconds) as? Int ?? 5))
        confirmationDelayMilliseconds = min(
            2_000,
            max(20, defaults.object(forKey: DefaultsKey.confirmationDelayMilliseconds) as? Int ?? 80)
        )
        notificationEnabled = defaults.object(forKey: DefaultsKey.notificationEnabled) as? Bool ?? true
        notificationTitle = defaults.string(forKey: DefaultsKey.notificationTitle) ?? Self.defaultNotificationTitle
        notificationBody = defaults.string(forKey: DefaultsKey.notificationBody) ?? Self.defaultNotificationBody
        windowSwitchEnabled = defaults.object(forKey: DefaultsKey.windowSwitchEnabled) as? Bool ?? false
        window1Target = Self.decode(WindowTarget.self, from: defaults, key: DefaultsKey.window1Target)
        window2Target = Self.decode(WindowTarget.self, from: defaults, key: DefaultsKey.window2Target)
        app1ApplicationTarget = Self.decode(
            ApplicationTarget.self,
            from: defaults,
            key: DefaultsKey.app1ApplicationTarget
        )
        app2ApplicationTarget = Self.decode(
            ApplicationTarget.self,
            from: defaults,
            key: DefaultsKey.app2ApplicationTarget
        )
        windowTrackingMode = defaults.string(forKey: DefaultsKey.windowTrackingMode)
            .flatMap(WindowTrackingMode.init(rawValue:)) ?? .automaticIDFirst
        windowActionOrder = WindowActionOrder.normalized(
            (defaults.array(forKey: DefaultsKey.windowActionOrder) as? [String] ?? [])
                .compactMap(WindowActionPriority.init(rawValue:))
        )
        privacyProtectionCount = configurationStore.privacyProtectionCount
        filter = DetectionFilter(
            confidenceThreshold: confidence,
            minimumAreaRatio: minimumArea
        )
        app1ApplicationIcon = app1ApplicationTarget.flatMap(windowSwitchService.icon)
        app2ApplicationIcon = app2ApplicationTarget.flatMap(windowSwitchService.icon)
        cameraService.setPreviewEnabled(previewEnabled)
        refreshDevices()
        refreshLoginItemStatus()
        accessibilityAuthorized = accessibilityService.isAuthorized
        if windowSwitchEnabled, accessibilityAuthorized {
            refreshWindowTargets()
        } else if windowSwitchEnabled {
            windowWarning = "辅助功能未授权，触发时不会切换窗口"
            startAccessibilityMonitoring()
        }
        if let modelError = cameraService.modelError {
            status = .modelUnavailable(modelError)
        }
    }

    var phase: GuardPhase { riskMachine.phase }

    var statusSymbolName: String {
        if phase.isTriggered {
            return manualRecovery ? "shield.lefthalf.filled.badge.checkmark" : "person.2.fill"
        }
        return status.symbolName
    }

    var statusDetail: String {
        if let recoverySecondsRemaining {
            return String(format: "风险正在解除，%.1f 秒后恢复", recoverySecondsRemaining)
        }
        if status == .triggered {
            return manualRecovery ? "保护已锁定，请手动恢复" : "等待人数降至恢复阈值"
        }
        return status.detail
    }

    var recoverySecondsRemaining: Double? {
        guard let now = lastEvaluationInstant,
              let remaining = riskMachine.recoveryRemaining(
                at: now,
                duration: .seconds(recoveryDelaySeconds)
              ) else { return nil }
        let components = remaining.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    var notificationPermissionTitle: String {
        switch notificationPermissionState {
        case .notDetermined: "通知权限尚未决定"
        case .authorized: "通知已授权"
        case .denied: "通知未授权"
        }
    }

    var cameraPermissionTitle: String {
        switch cameraAuthorizationStatus {
        case .authorized: "摄像头已授权"
        case .notDetermined: "摄像头权限尚未决定"
        case .denied: "摄像头未授权"
        case .restricted: "摄像头权限受限制"
        @unknown default: "摄像头权限未知"
        }
    }

    var cameraPermissionAuthorized: Bool {
        cameraAuthorizationStatus == .authorized
    }

    private var riskRules: RiskRules {
        RiskRules(
            triggerPersonCount: triggerPersonCount,
            recoveryPersonCount: recoveryPersonCount,
            confirmationDuration: .milliseconds(confirmationDelayMilliseconds),
            manualRecovery: manualRecovery,
            recoveryDuration: .seconds(recoveryDelaySeconds)
        )
    }

    var statusColorName: String {
        switch status {
        case .running: "green"
        case .suspected: "orange"
        case .triggered: "red"
        case .disabled, .paused: "secondary"
        case .requestingPermission: "blue"
        case .cameraUnavailable, .modelUnavailable, .error: "red"
        }
    }

    func completeOnboardingAndEnable() async {
        markOnboardingComplete()
        await enableProtection(userInitiated: true)
    }

    func markOnboardingComplete() {
        onboardingComplete = true
        defaults.set(true, forKey: DefaultsKey.onboardingComplete)
    }

    func enableProtection(userInitiated: Bool = true) async {
        guard !isEnabled, !isEnabling else { return }
        let attempt = enableAttempt.begin()
        if userInitiated {
            wantsProtectionEnabled = true
            defaults.set(true, forKey: DefaultsKey.protectionEnabled)
        }
        status = .requestingPermission

        let authorizationStatus = CameraService.authorizationStatus()
        cameraAuthorizationStatus = authorizationStatus
        cameraDiagnostics.notice(
            "Camera authorization check: status=\(cameraAuthorizationStatusName(authorizationStatus)) " +
            "raw=\(authorizationStatus.rawValue) userInitiated=\(userInitiated)"
        )
        let cameraGranted: Bool
        switch authorizationStatus {
        case .authorized:
            cameraGranted = true
        case .notDetermined:
            cameraGranted = await CameraService.requestAccess()
        default:
            cameraGranted = false
        }
        cameraAuthorizationStatus = CameraService.authorizationStatus()
        cameraDiagnostics.notice(
            "Camera authorization result: granted=\(cameraGranted) " +
            "status=\(cameraAuthorizationStatusName(CameraService.authorizationStatus()))"
        )
        guard enableAttempt.accepts(attempt) else { return }
        guard cameraGranted else {
            enableAttempt.cancel()
            status = .cameraUnavailable(cameraPermissionMessage)
            return
        }

        let notificationGranted = await notificationService.requestAuthorization()
        guard enableAttempt.accepts(attempt) else { return }
        notificationPermissionState = notificationGranted ? .authorized : .denied
        notificationWarning = notificationGranted ? nil : "通知未授权，检测与窗口动作仍会继续运行"
        guard cameraService.modelError == nil else {
            enableAttempt.cancel()
            wantsProtectionEnabled = false
            defaults.set(false, forKey: DefaultsKey.protectionEnabled)
            status = .modelUnavailable(cameraService.modelError ?? "Core ML 模型加载失败")
            return
        }

        guard enableAttempt.finish(attempt) else { return }
        isEnabled = true
        let generation = monitoringGeneration.begin()
        riskMachine.restore()
        lastEvaluationInstant = nil
        status = .running
        startCamera(generation: generation)
    }

    func pauseProtection(userInitiated: Bool = true) {
        guard isProtectionRequested else { return }
        if userInitiated {
            wantsProtectionEnabled = false
            defaults.set(false, forKey: DefaultsKey.protectionEnabled)
        }
        resumeAfterSystemWake = false
        enableAttempt.cancel()
        isEnabled = false
        monitoringGeneration.invalidate()
        cameraService.stop()
        latestImage = nil
        snapshot = DetectionSnapshot()
        validPeople = []
        riskMachine.restore()
        lastEvaluationInstant = nil
        status = .paused
    }

    func toggleProtection() async {
        if isProtectionRequested {
            pauseProtection(userInitiated: true)
        } else {
            await enableProtection(userInitiated: true)
        }
    }

    func restoreTriggeredState() {
        riskMachine.restore()
        lastEvaluationInstant = nil
        status = isEnabled ? .running : .paused
        cameraService.setTargetFPS(2)
    }

    func refreshDevices() {
        cameras = CameraService.availableDevices()
        if let selectedCameraID,
           !cameras.contains(where: { $0.id == selectedCameraID }) {
            self.selectedCameraID = nil
        }
    }

    func suspendForSystemEvent() {
        guard isEnabled || isEnabling else { return }
        resumeAfterSystemWake = true
        enableAttempt.cancel()
        isEnabled = false
        monitoringGeneration.invalidate()
        cameraService.stop()
        latestImage = nil
        snapshot = DetectionSnapshot()
        validPeople = []
        riskMachine.restore()
        lastEvaluationInstant = nil
        status = .paused
    }

    func resumeAfterSystemEvent() {
        guard resumeAfterSystemWake else { return }
        resumeAfterSystemWake = false
        Task { await enableProtection(userInitiated: false) }
    }

    func resumeSavedPreferenceIfNeeded() {
        guard onboardingComplete, wantsProtectionEnabled, !isEnabled, !isEnabling else { return }
        Task { await enableProtection(userInitiated: false) }
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }

    func refreshLoginItemStatus() {
        loginItemEnabled = LoginItemService.isEnabled
        loginItemRequiresApproval = LoginItemService.requiresApproval
    }

    func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    func openLoginItemSettings() {
        LoginItemService.openSettings()
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshNotificationPermission() async {
        notificationPermissionState = await notificationService.permissionState()
        notificationWarning = notificationPermissionState == .denied
            ? "通知未授权，检测与窗口动作仍会继续运行"
            : nil
    }

    func refreshPermissionStates() async {
        await refreshNotificationPermission()
        let cameraStatus = CameraService.authorizationStatus()
        cameraAuthorizationStatus = cameraStatus
        cameraDiagnostics.notice(
            "Permission refresh: camera=\(cameraAuthorizationStatusName(cameraStatus)) " +
            "raw=\(cameraStatus.rawValue) enabled=\(isEnabled) wantsProtection=\(wantsProtectionEnabled)"
        )
        if cameraStatus == .authorized, wantsProtectionEnabled, !isEnabled, !isEnabling {
            await enableProtection(userInitiated: false)
        } else if cameraStatus == .authorized,
                  !wantsProtectionEnabled,
                  case .cameraUnavailable = status {
            status = .paused
        } else if cameraStatus != .authorized, !isEnabled, wantsProtectionEnabled {
            status = .cameraUnavailable(cameraPermissionMessage)
        }
        if windowSwitchEnabled {
            refreshAccessibilityState()
            if accessibilityAuthorized, windowDiscoveryState == .accessibilityUnavailable {
                requestAccessibilityAuthorization()
            }
        } else {
            accessibilityAuthorized = accessibilityService.isAuthorized
        }
    }

    func resetNotificationContent() {
        notificationTitle = Self.defaultNotificationTitle
        notificationBody = Self.defaultNotificationBody
    }

    func sendTestNotification() async {
        guard !isSendingTestNotification else { return }
        isSendingTestNotification = true
        notificationTestMessage = nil
        notificationTestSucceeded = false
        defer { isSendingTestNotification = false }

        var permission = await notificationService.permissionState()
        if permission == .notDetermined {
            let granted = await notificationService.requestAuthorization()
            permission = granted ? .authorized : .denied
        }
        notificationPermissionState = permission
        guard permission == .authorized else {
            notificationWarning = "通知未授权，请先在系统设置中允许大墨鱼发送通知"
            notificationTestMessage = "测试通知未发送：缺少通知权限"
            return
        }

        let title = notificationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = notificationBody.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await notificationService.sendProtectionNotification(
                title: title.isEmpty ? Self.defaultNotificationTitle : title,
                body: body.isEmpty ? Self.defaultNotificationBody : body,
                identifier: "moyu-pro-test-\(UUID().uuidString)"
            )
            notificationWarning = nil
            notificationTestSucceeded = true
            notificationTestMessage = "测试通知已提交；若未看到横幅，请检查专注模式和通知样式。"
        } catch {
            notificationWarning = error.localizedDescription
            notificationTestMessage = "测试通知发送失败：\(error.localizedDescription)"
        }
    }

    func requestAccessibilityAuthorization() {
        accessibilityAuthorizationTask?.cancel()
        accessibilityAuthorized = accessibilityService.requestAccess()
        accessibilityDiagnostics.notice(
            "Authorization flow started: trusted=\(accessibilityAuthorized) windowSwitchEnabled=\(windowSwitchEnabled)"
        )
        refreshAccessibilityState()
        if accessibilityAuthorized, windowDiscoveryState != .accessibilityUnavailable {
            return
        }
        windowWarning = accessibilityAuthorized
            ? "辅助功能已授权，但 macOS 暂时无法读取窗口；应用会自动重试。"
            : "请在系统设置中允许大墨鱼；授权后会自动检测并刷新窗口。"
        startAccessibilityMonitoring()
    }

    private func startAccessibilityMonitoring() {
        accessibilityAuthorizationTask?.cancel()
        accessibilityAuthorizationTask = Task { @MainActor [weak self] in
            var attempts = 0
            while let self, !Task.isCancelled, self.windowSwitchEnabled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    self.accessibilityDiagnostics.notice("Authorization monitoring cancelled")
                    return
                }
                guard self.windowSwitchEnabled else {
                    self.accessibilityDiagnostics.notice("Authorization monitoring stopped: window switching disabled")
                    return
                }
                attempts += 1
                let trusted = self.accessibilityService.isAuthorized
                self.accessibilityDiagnostics.notice(
                    "Authorization poll: attempt=\(attempts) trusted=\(trusted)"
                )
                guard trusted else { continue }
                self.refreshWindowTargets()
                guard self.windowDiscoveryState == .accessibilityUnavailable else {
                    self.accessibilityDiagnostics.notice(
                        "Authorization monitoring complete: attempts=\(attempts) state=\(self.windowDiscoveryState)"
                    )
                    self.accessibilityAuthorizationTask = nil
                    return
                }
                self.windowWarning = self.windowWarningForCurrentTargets
                if attempts >= 15 {
                    self.windowWarning = self.accessibilityFailureMessage
                    self.accessibilityDiagnostics.error(
                        "Authorization monitoring stopped after repeated AX failures: " +
                        "attempts=\(attempts) failures=\(self.windowFailureSummary)"
                    )
                    self.accessibilityAuthorizationTask = nil
                    return
                }
            }
            self?.accessibilityAuthorizationTask = nil
        }
    }

    func observeAccessibilityChange() {
        guard windowSwitchEnabled else { return }
        requestAccessibilityAuthorization()
    }

    private func refreshAccessibilityState() {
        accessibilityAuthorized = accessibilityService.isAuthorized
        if accessibilityAuthorized {
            refreshWindowTargets()
            return
        }
        windowDiscoveryState = .unauthorized
        availableWindowTargets = []
        windowWarning = "请在系统设置中允许大墨鱼；授权后会自动检测并刷新窗口。"
    }

    private var windowWarningForCurrentTargets: String? {
        switch windowDiscoveryState {
        case .unauthorized:
            return "辅助功能未授权。"
        case .snapshotUnavailable:
            return "macOS 暂时无法读取窗口列表，请返回当前 Space 后重试。"
        case .noWindows:
            return "当前 Space 未发现可选择窗口。请先打开目标窗口，再点“刷新窗口”。"
        case .accessibilityUnavailable:
            return "辅助功能已授权，但 macOS 暂时无法读取窗口；应用会自动重试。"
        case .ready:
            return nil
        }
    }

    func refreshWindowTargets() {
        let result = windowSwitchService.discoverWindows()
        accessibilityAuthorized = accessibilityService.isAuthorized
        windowDiscoveryState = result.state
        availableWindowTargets = result.targets
        latestWindowQueryFailures = result.failures
        rebindWindowTargetsIfNeeded()

        switch result.state {
        case .unauthorized:
            windowWarning = windowSwitchEnabled
                ? "辅助功能未授权。授权后会自动刷新窗口。"
                : nil
        case .noWindows:
            windowWarning = "当前 Space 未发现可选择窗口。请先打开目标窗口，再点“刷新窗口”。"
        case .snapshotUnavailable:
            windowWarning = "macOS 暂时无法读取窗口列表，请返回当前 Space 后重试。"
        case .accessibilityUnavailable:
            windowWarning = accessibilityFailureMessage
        case .ready:
            validateWindowTargets()
        }
    }

    func chooseApplication(for role: WindowActionPriority) {
        guard role == .fallbackApp || role == .secondApp else { return }
        guard let application = windowSwitchService.chooseApplication() else { return }
        switch role {
        case .fallbackApp:
            app1ApplicationTarget = application
        case .secondApp:
            app2ApplicationTarget = application
        case .primaryWindow, .backupWindow:
            break
        }
    }

    func moveWindowActionRole(_ role: WindowActionPriority, by offset: Int) {
        guard let index = windowActionOrder.firstIndex(of: role) else { return }
        let destination = index + offset
        guard windowActionOrder.indices.contains(destination) else { return }
        var order = windowActionOrder
        order.swapAt(index, destination)
        windowActionOrder = order
    }

    func testWindowAction() {
        guard windowSwitchEnabled else {
            windowWarning = "请先开启触发时执行窗口/App 动作"
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.windowSwitchService.execute(
                window1: self.window1Target,
                window2: self.window2Target,
                app1: self.app1ApplicationTarget,
                app2: self.app2ApplicationTarget,
                order: self.windowActionOrder,
                trackingMode: self.windowTrackingMode
            )
            self.handleWindowActionResult(result)
        }
    }

    func openAccessibilitySettings() {
        accessibilityService.openSettings()
    }

    func revealDiagnosticsLog() {
        accessibilityDiagnostics.revealInFinder()
    }

    private var windowFailureSummary: String {
        let grouped = Dictionary(grouping: latestWindowQueryFailures, by: \.errorName)
        return grouped
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
    }

    private var accessibilityFailureMessage: String {
        if latestWindowQueryFailures.contains(where: { $0.errorCode == AXError.apiDisabled.rawValue }) {
            return "macOS 拒绝了辅助功能访问。请确认当前版本的大墨鱼已授权。"
        }
        if latestWindowQueryFailures.contains(where: { $0.errorCode == AXError.cannotComplete.rawValue }) {
            return "部分 App 暂时未响应窗口查询。大墨鱼会有限重试；详情见诊断日志。"
        }
        return "辅助功能已授权，但窗口查询失败。请查看诊断日志中的 AX 错误码。"
    }

    private func startCamera(generation: UInt64) {
        cameraDiagnostics.notice(
            "Camera start requested: deviceID=\(selectedCameraID ?? "system-preferred") " +
            "authorization=\(cameraAuthorizationStatusName(CameraService.authorizationStatus()))"
        )
        cameraService.start(
            deviceID: selectedCameraID,
            frameHandler: { [weak self] result in
                Task { @MainActor in
                    guard let self,
                          self.monitoringGeneration.accepts(generation, isEnabled: self.isEnabled) else {
                        return
                    }
                    self.handle(result, generation: generation)
                }
            },
            eventHandler: { [weak self] event in
                Task { @MainActor in
                    guard let self,
                          self.monitoringGeneration.accepts(generation, isEnabled: self.isEnabled) else {
                        return
                    }
                    switch event {
                    case let .interrupted(message):
                        self.cameraDiagnostics.notice("Camera interrupted: \(message)")
                        self.status = .cameraUnavailable(message)
                    case .resumed:
                        self.cameraDiagnostics.notice("Camera resumed")
                        self.status = self.riskMachine.phase.isTriggered ? .triggered : .running
                    case let .failed(message):
                        self.cameraDiagnostics.error("Camera failed: \(message)")
                        self.monitoringGeneration.invalidate()
                        self.cameraService.stop()
                        self.status = .cameraUnavailable(message)
                        self.isEnabled = false
                    }
                }
            }
        )
    }

    private var cameraPermissionMessage: String {
        "请在系统设置 > 隐私与安全性 > 摄像头中允许大墨鱼访问，然后返回应用重试"
    }

    private func cameraAuthorizationStatusName(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
    }

    private func handle(_ result: CameraFrameResult, generation: UInt64) {
        snapshot = result.snapshot
        if previewEnabled { latestImage = result.image }
        validPeople = filter.validPeople(in: result.snapshot.detections)

        let now = ContinuousClock().now
        lastEvaluationInstant = now
        let transition = riskMachine.process(
            personCount: validPeople.count,
            at: now,
            rules: riskRules
        )
        if transition == .triggered {
            status = .triggered
            cameraService.setTargetFPS(2)
            performTriggerActions(generation: generation)
        } else if transition == .restored {
            status = .running
            cameraService.setTargetFPS(2)
        } else if riskMachine.phase.isSuspected {
            status = .suspected
            cameraService.setTargetFPS(max(7, 1_000 / Double(confirmationDelayMilliseconds)))
        } else if riskMachine.phase.isClearing {
            status = .triggered
            cameraService.setTargetFPS(7)
        } else if riskMachine.phase.isTriggered {
            status = .triggered
            cameraService.setTargetFPS(2)
        } else {
            status = .running
            cameraService.setTargetFPS(2)
        }
    }

    private func reconfigureRiskMachine() {
        riskMachine.reconfigure(at: ContinuousClock().now)
        lastEvaluationInstant = nil
        if isEnabled {
            status = riskMachine.phase.isTriggered ? .triggered : .running
        }
    }

    private func sendConfiguredNotification(generation: UInt64?) async {
        let title = notificationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = notificationBody.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await notificationService.ensureAuthorized()
            if let generation,
               !monitoringGeneration.accepts(generation, isEnabled: isEnabled) {
                return
            }
            try await notificationService.sendProtectionNotification(
                title: title.isEmpty ? Self.defaultNotificationTitle : title,
                body: body.isEmpty ? Self.defaultNotificationBody : body
            )
            notificationPermissionState = .authorized
            notificationWarning = nil
        } catch {
            notificationPermissionState = .denied
            notificationWarning = error.localizedDescription
        }
    }

    private func performTriggerActions(generation: UInt64) {
        privacyProtectionCount = configurationStore.recordPrivacyProtection()
        if let error = configurationStore.lastErrorMessage {
            logger.error("无法保存隐私保护次数: \(error, privacy: .public)")
        }
        if windowSwitchEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await self.windowSwitchService.execute(
                    window1: self.window1Target,
                    window2: self.window2Target,
                    app1: self.app1ApplicationTarget,
                    app2: self.app2ApplicationTarget,
                    order: self.windowActionOrder,
                    trackingMode: self.windowTrackingMode
                )
                self.handleWindowActionResult(result)
            }
        }
        guard notificationEnabled else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  self.monitoringGeneration.accepts(generation, isEnabled: self.isEnabled) else { return }
            await self.sendConfiguredNotification(generation: generation)
        }
    }

    private func handleWindowActionResult(_ result: WindowActionResult) {
        switch result {
        case let .completed(role):
            lastWindowAction = role.isWindow ? "已切换到\(role.title)" : "已打开\(role.title)"
            windowWarning = nil
        case .noTargets:
            lastWindowAction = nil
            windowWarning = "尚未配置窗口或 App"
        case let .failed(message):
            lastWindowAction = nil
            windowWarning = message
        }
        if let windowWarning {
            logger.warning("\(windowWarning, privacy: .public)")
        }
    }

    private func validateWindowTargets() {
        guard windowSwitchEnabled, accessibilityAuthorized else { return }
        let missingWindow1 = window1Target.map {
            !$0.isResolvable(among: availableWindowTargets, mode: windowTrackingMode)
        } ?? false
        let missingWindow2 = window2Target.map {
            !$0.isResolvable(among: availableWindowTargets, mode: windowTrackingMode)
        } ?? false
        if missingWindow1 || missingWindow2 {
            windowWarning = "窗口目标需重新选择"
            logger.warning("窗口目标需重新选择")
        } else {
            windowWarning = nil
        }
    }

    private func rebindWindowTargetsIfNeeded() {
        guard windowTrackingMode != .exactTitle else { return }
        if let window1Target,
           let refreshed = refreshedTarget(for: window1Target) {
            self.window1Target = refreshed
        }
        if let window2Target,
           let refreshed = refreshedTarget(for: window2Target) {
            self.window2Target = refreshed
        }
    }

    private func refreshedTarget(for target: WindowTarget) -> WindowTarget? {
        target.refreshedCandidate(
            among: availableWindowTargets,
            allowTitleFallback: windowTrackingMode == .automaticIDFirst
        )
    }

    private func persist<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from defaults: UserDefaults,
        key: String
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
