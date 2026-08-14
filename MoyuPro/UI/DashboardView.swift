import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel
    @State private var selectedSection = SettingsSection.defaultSection

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("运行") {
                    sidebarItem(.triggerActions)
                    sidebarItem(.monitoringAndCamera)
                    sidebarItem(.detectionRules)
                }
                Section("系统") {
                    sidebarItem(.startupAndPermissions)
                    sidebarItem(.privacy)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statusHeader
                    selectedSectionContent
                }
                .padding(24)
                .frame(maxWidth: 880, alignment: .leading)
            }
            .navigationTitle(selectedSection.title)
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            model.refreshDevices()
            model.refreshLoginItemStatus()
            Task { await model.refreshPermissionStates() }
        }
    }

    private var sidebarSelection: Binding<SettingsSection?> {
        Binding(
            get: { selectedSection },
            set: { selectedSection = SettingsSection.normalized($0) }
        )
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        Label(section.title, systemImage: section.symbolName)
            .tag(section)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .monitoringAndCamera:
            controlsSection
            previewSection
        case .detectionRules:
            ruleSection
        case .triggerActions:
            windowActionSection
            notificationSection
        case .startupAndPermissions:
            systemSection
        case .privacy:
            privacySection
        }
    }

    private var windowActionSection: some View {
        GroupBox("触发动作") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("触发时执行窗口/App 动作", isOn: $model.windowSwitchEnabled)
                Label(
                    "触发后按下方优先级尝试目标；前一个未配置或不可用时继续下一个。",
                    systemImage: "arrow.right.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                configurationTitle("辅助功能权限", systemImage: "hand.raised.fill")
                HStack {
                    Label(
                        model.accessibilityAuthorized ? "辅助功能已授权" : "辅助功能未授权",
                        systemImage: model.accessibilityAuthorized
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.accessibilityAuthorized ? .green : .orange)
                    Spacer()
                    if !model.accessibilityAuthorized {
                        Button {
                            model.requestAccessibilityAuthorization()
                        } label: {
                            Label("打开系统设置", systemImage: "gear")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Text(model.accessibilityAuthorized
                     ? "已可读取并聚焦窗口。"
                     : "窗口切换需要 macOS 辅助功能权限；授权完成后会自动刷新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                configurationTitle("窗口匹配方式", systemImage: "scope")
                VStack(alignment: .leading, spacing: 8) {
                    Picker("窗口匹配方式", selection: $model.windowTrackingMode) {
                        ForEach(WindowTrackingMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    Text(model.windowTrackingMode.detail)
                        .font(.caption)
                    .foregroundStyle(.secondary)
                    if model.windowTrackingMode == .strictWindowID,
                       [model.window1Target, model.window2Target]
                        .compactMap({ $0 })
                        .contains(where: { $0.windowID == nil }) {
                        Label("旧目标没有窗口 ID，请重新选择，或改用自动/标题模式。", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Divider()

                configurationTitle("触发动作优先级", systemImage: "arrow.triangle.2.circlepath")
                ForEach(Array(model.windowActionOrder.enumerated()), id: \.element) { index, role in
                    HStack {
                        Text("\(index + 1)")
                            .monospacedDigit()
                            .frame(width: 20, alignment: .leading)
                        Label(role.title, systemImage: role.symbolName)
                        Spacer()
                        Button {
                            model.moveWindowActionRole(role, by: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .help("上移")
                        Button {
                            model.moveWindowActionRole(role, by: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == model.windowActionOrder.count - 1)
                        .help("下移")
                    }
                }
                Text("未配置的目标会自动跳过。可将窗口或 App 移到第一位优先执行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                configurationTitle("窗口配置", systemImage: "macwindow")
                HStack {
                    Label(windowDiscoveryTitle, systemImage: windowDiscoverySymbol)
                        .foregroundStyle(windowDiscoveryColor)
                    Spacer()
                    Button {
                        model.refreshWindowTargets()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新当前 Space 中的窗口")
                }
                if model.availableWindowTargets.isEmpty {
                    Text(windowDiscoveryHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                windowTargetRow(.primaryWindow)
                windowTargetRow(.backupWindow)

                Divider()

                configurationTitle("App 配置（可跨 Space）", systemImage: "app.badge.checkmark")
                applicationTargetRow(.fallbackApp)
                applicationTargetRow(.secondApp)

                Divider()
                HStack {
                    Button {
                        model.testWindowAction()
                    } label: {
                        Label("测试切换", systemImage: "macwindow.on.rectangle")
                    }
                    .disabled(!model.windowSwitchEnabled)
                    .help("立即按当前优先级和匹配方式试运行一次")
                    if let action = model.lastWindowAction {
                        Text(action).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let warning = model.windowWarning {
                    Label(warning, systemImage: "macwindow.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 6)
        }
    }

    private func configurationTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func windowTargetRow(_ role: WindowActionPriority) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(role.title).font(.headline)
            Text("按上方匹配方式，在当前 Space 中定位并聚焦这个窗口。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Picker(role.title, selection: windowTargetBinding(for: role)) {
                    Text("未选择").tag(WindowTarget?.none)
                    ForEach(windowChoices) { target in
                        Text(target.displayName).tag(Optional(target))
                    }
                }
                .labelsHidden()
                .frame(width: windowPickerWidth, alignment: .leading)
                .clipped()
                Button {
                    windowTargetBinding(for: role).wrappedValue = nil
                } label: {
                    Image(systemName: "trash")
                }
                .help("清除\(role.title)")
                .disabled(windowTargetBinding(for: role).wrappedValue == nil)
            }
        }
    }

    private func applicationTargetRow(_ role: WindowActionPriority) -> some View {
        let target = applicationTarget(for: role)
        return HStack(spacing: 12) {
            Group {
                if let icon = applicationIcon(for: role) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(7)
                }
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(target?.applicationName ?? "未选择\(role.title)")
                    .font(.headline)
                Text(target?.bundleIdentifier ?? "按上方优先级激活正在运行的 App，或启动它；不依赖窗口标题。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                model.chooseApplication(for: role)
            } label: {
                Image(systemName: "folder")
            }
            .help("选择\(role.title)")
            Button {
                clearApplicationTarget(for: role)
            } label: {
                Image(systemName: "trash")
            }
            .help("清除\(role.title)")
            .disabled(target == nil)
        }
    }

    private func windowTargetBinding(for role: WindowActionPriority) -> Binding<WindowTarget?> {
        switch role {
        case .primaryWindow:
            $model.window1Target
        case .backupWindow:
            $model.window2Target
        case .fallbackApp, .secondApp:
            preconditionFailure("Only window roles have window targets")
        }
    }

    private func applicationTarget(for role: WindowActionPriority) -> ApplicationTarget? {
        switch role {
        case .fallbackApp:
            model.app1ApplicationTarget
        case .secondApp:
            model.app2ApplicationTarget
        case .primaryWindow, .backupWindow:
            nil
        }
    }

    private func applicationIcon(for role: WindowActionPriority) -> NSImage? {
        switch role {
        case .fallbackApp:
            model.app1ApplicationIcon
        case .secondApp:
            model.app2ApplicationIcon
        case .primaryWindow, .backupWindow:
            nil
        }
    }

    private func clearApplicationTarget(for role: WindowActionPriority) {
        switch role {
        case .fallbackApp:
            model.app1ApplicationTarget = nil
        case .secondApp:
            model.app2ApplicationTarget = nil
        case .primaryWindow, .backupWindow:
            return
        }
    }

    private var windowChoices: [WindowTarget] {
        var choices = Set(model.availableWindowTargets)
        if let window1 = model.window1Target { choices.insert(window1) }
        if let window2 = model.window2Target { choices.insert(window2) }
        return choices.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private let windowPickerWidth: CGFloat = 360

    private var windowDiscoveryTitle: String {
        switch model.windowDiscoveryState {
        case .unauthorized: "等待辅助功能授权"
        case .snapshotUnavailable: "窗口列表暂不可用"
        case .accessibilityUnavailable: "辅助功能已授权，等待窗口访问"
        case .noWindows: "当前 Space 暂无可选窗口"
        case .ready:
            "发现 \(model.availableWindowTargets.count) 个窗口"
        }
    }

    private var windowDiscoverySymbol: String {
        switch model.windowDiscoveryState {
        case .ready: "macwindow.on.rectangle"
        case .unauthorized: "lock.fill"
        case .noWindows, .snapshotUnavailable, .accessibilityUnavailable:
            "macwindow.badge.exclamationmark"
        }
    }

    private var windowDiscoveryColor: Color {
        switch model.windowDiscoveryState {
        case .ready: .secondary
        case .noWindows, .snapshotUnavailable, .accessibilityUnavailable, .unauthorized: .orange
        }
    }

    private var windowDiscoveryHelp: String {
        switch model.windowDiscoveryState {
        case .unauthorized:
            "请先授予辅助功能权限。"
        case .snapshotUnavailable:
            "macOS 暂时没有返回窗口快照，请切回目标 Space 后重试。"
        case .accessibilityUnavailable:
            "辅助功能已授权，但 macOS 暂时无法读取窗口；稍后可刷新窗口列表。"
        case .noWindows:
            "请在当前 Space 打开目标 App 的普通窗口。最小化窗口不会列出。"
        case .ready:
            "没有可选窗口。请打开目标 App 的普通窗口后刷新。"
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: model.statusSymbolName)
                .font(.system(size: 30))
                .foregroundStyle(statusColor)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.status.title).font(.title2.bold())
                Text(model.statusDetail).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.toggleProtection() }
            } label: {
                Label(
                    model.isProtectionRequested ? "取消" : "启用",
                    systemImage: model.isProtectionRequested ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            if model.phase.isTriggered {
                Button {
                    model.restoreTriggeredState()
                } label: {
                    Label("恢复", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("实时预览").font(.headline)
                Spacer()
                Toggle("显示预览", isOn: $model.previewEnabled)
                    .toggleStyle(.switch)
            }
            DetectionPreviewView(
                image: model.previewEnabled ? model.latestImage : nil,
                detections: model.validPeople,
                isRunning: model.isEnabled
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
        }
    }

    private var controlsSection: some View {
        GroupBox("摄像头与性能") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("摄像头")
                    Picker("", selection: $model.selectedCameraID) {
                        Text("系统首选").tag(String?.none)
                        ForEach(model.cameras) { camera in
                            Text(camera.isSystemPreferred ? "\(camera.name)（系统首选）" : camera.name)
                                .tag(Optional(camera.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    Button {
                        model.refreshDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新摄像头列表")
                }
                GridRow {
                    Text("权限")
                    Label(
                        model.cameraPermissionTitle,
                        systemImage: model.cameraPermissionAuthorized
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.cameraPermissionAuthorized ? .green : .orange)
                    if model.cameraPermissionAuthorized {
                        EmptyView()
                    } else {
                        Button("打开权限设置") { model.openCameraPrivacySettings() }
                    }
                }
                GridRow {
                    Text("有效人体")
                    Text("\(model.validPeople.count)")
                    EmptyView()
                }
                GridRow {
                    Text("推理耗时")
                    Text(String(format: "%.1f ms", model.snapshot.metrics.inferenceMilliseconds))
                    EmptyView()
                }
                GridRow {
                    Text("处理帧率")
                    Text(String(format: "%.1f FPS", model.snapshot.metrics.effectiveFPS))
                    EmptyView()
                }
            }
            .padding(.top, 6)
        }
    }

    private var ruleSection: some View {
        GroupBox("检测规则") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("触发后只能手动恢复", isOn: $model.manualRecovery)
                LabeledContent("触发人数") {
                    Stepper(value: $model.triggerPersonCount, in: 2...6) {
                        Text("\(model.triggerPersonCount) 人")
                            .monospacedDigit()
                    }
                    .frame(width: 150)
                }
                LabeledContent("恢复人数") {
                    Stepper(value: $model.recoveryPersonCount, in: 0...max(0, model.triggerPersonCount - 1)) {
                        Text("≤ \(model.recoveryPersonCount) 人")
                            .monospacedDigit()
                    }
                    .frame(width: 150)
                    .disabled(model.manualRecovery)
                }
                LabeledContent("自动恢复延迟") {
                    Stepper(value: $model.recoveryDelaySeconds, in: 1...30) {
                        Text("\(model.recoveryDelaySeconds) 秒")
                            .monospacedDigit()
                    }
                    .frame(width: 150)
                    .disabled(model.manualRecovery)
                }
                LabeledContent("人体置信度") {
                    HStack {
                        Slider(value: $model.confidenceThreshold, in: 0.1...0.8, step: 0.05)
                            .frame(width: 240)
                        Text(model.confidenceThreshold, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                LabeledContent("最小画面占比") {
                    HStack {
                        Slider(value: $model.minimumAreaRatio, in: 0.002...0.08, step: 0.002)
                            .frame(width: 240)
                        Text(model.minimumAreaRatio * 100, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                        Text("%")
                    }
                }
                LabeledContent("多人复核间隔") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(model.confirmationDelayMilliseconds) },
                                set: { model.confirmationDelayMilliseconds = Int($0) }
                            ),
                            in: 20...2_000,
                            step: 20
                        )
                        .frame(width: 240)
                        Text("\(model.confirmationDelayMilliseconds) 毫秒")
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                Text("首次检测到至少 \(model.triggerPersonCount) 人后，等待复核间隔再次扫描；人数仍达阈值才触发。触发人数与恢复人数始终保持独立阈值。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private var systemSection: some View {
        GroupBox("启动与权限") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("登录时启动大墨鱼", isOn: Binding(
                    get: { model.loginItemEnabled },
                    set: { model.setLoginItemEnabled($0) }
                ))
                if model.loginItemRequiresApproval {
                    HStack {
                        Text("需要在系统设置中批准登录项。")
                            .foregroundStyle(.orange)
                        Button("打开登录项设置") { model.openLoginItemSettings() }
                    }
                }
                if let error = model.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if case .cameraUnavailable = model.status {
                    Button("打开摄像头权限设置") { model.openCameraPrivacySettings() }
                }
                Button {
                    model.revealDiagnosticsLog()
                } label: {
                    Label("查看诊断日志", systemImage: "doc.text.magnifyingglass")
                }
                .help("在 Finder 中打开大墨鱼的摄像头、AX 和 Sandbox 诊断日志")
                if case .error = model.status {
                    Button("打开通知设置") { model.openNotificationSettings() }
                }
            }
            .padding(.top, 6)
        }
    }

    private var notificationSection: some View {
        GroupBox("触发通知") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("触发时发送通知", isOn: $model.notificationEnabled)
                HStack {
                    Label(
                        model.notificationPermissionTitle,
                        systemImage: model.notificationPermissionState == .authorized
                            ? "checkmark.circle.fill"
                            : "bell.slash.fill"
                    )
                    .foregroundStyle(model.notificationPermissionState == .authorized ? .green : .orange)
                    Spacer()
                    Button("打开通知设置") { model.openNotificationSettings() }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("通知标题").font(.headline)
                    TextField("新邮件", text: $model.notificationTitle)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("通知正文").font(.headline)
                    TextField("您有一条新邮件待查看", text: $model.notificationBody)
                }
                HStack {
                    Button("恢复默认文本") { model.resetNotificationContent() }
                    Button {
                        Task { await model.sendTestNotification() }
                    } label: {
                        if model.isSendingTestNotification {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("正在发送")
                            }
                        } else {
                            Label("发送测试通知", systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSendingTestNotification)
                }
                Text("测试通知会使用上面的标题和正文；即使关闭了“触发时发送通知”，仍可单独测试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let message = model.notificationTestMessage {
                    Label(
                        message,
                        systemImage: model.notificationTestSucceeded
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(model.notificationTestSucceeded ? .green : .orange)
                }
                if let warning = model.notificationWarning {
                    Label(warning, systemImage: "bell.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("隐私保护统计") {
                LabeledContent("已保护次数") {
                    Text("\(model.privacyProtectionCount)")
                        .font(.title2.monospacedDigit().bold())
                }
                .padding(.vertical, 6)
            }
            GroupBox("隐私说明") {
                Text("本应用仅通过本地环境运行，不会联网与保存摄像头数据，项目已开源至：[https://github.com/LingLambda/moyu-plus](https://github.com/LingLambda/moyu-plus)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .running: .green
        case .suspected: .orange
        case .triggered, .cameraUnavailable, .modelUnavailable, .error: .red
        case .requestingPermission: .blue
        case .disabled, .paused: .secondary
        }
    }
}

enum SettingsSection: String, CaseIterable, Hashable {
    case triggerActions
    case monitoringAndCamera
    case detectionRules
    case startupAndPermissions
    case privacy

    static let defaultSection: SettingsSection = .triggerActions

    static func normalized(_ section: SettingsSection?) -> SettingsSection {
        section ?? defaultSection
    }

    var title: String {
        switch self {
        case .triggerActions: "触发动作"
        case .monitoringAndCamera: "监测与摄像头"
        case .detectionRules: "检测规则"
        case .startupAndPermissions: "启动与权限"
        case .privacy: "隐私说明"
        }
    }

    var symbolName: String {
        switch self {
        case .triggerActions: "bolt.fill"
        case .monitoringAndCamera: "video"
        case .detectionRules: "person.2"
        case .startupAndPermissions: "gear"
        case .privacy: "hand.raised"
        }
    }
}
