import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.statusSymbolName)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.status.title)
                        .font(.headline)
                    Text(model.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Divider()

            LabeledContent("当前核心数", value: "\(model.validPeople.count)")
            LabeledContent("推理耗时", value: String(format: "%.1f ms", model.snapshot.metrics.inferenceMilliseconds))

            if let warning = model.notificationWarning {
                Label(warning, systemImage: "bell.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let warning = model.windowWarning {
                Label(warning, systemImage: "macwindow.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let action = model.lastWindowAction {
                Label(action, systemImage: "macwindow.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.phase.isTriggered {
                Button {
                    model.restoreTriggeredState()
                } label: {
                    Label("手动恢复", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button {
                Task { await model.toggleProtection() }
            } label: {
                Label(
                    model.isEnabled || model.isEnabling ? "取消保护" : "启用保护",
                    systemImage: model.isEnabled || model.isEnabling ? "pause.fill" : "play.fill"
                )
            }

            Button {
                if model.onboardingComplete {
                    openWindow(id: "dashboard")
                } else {
                    (NSApp.delegate as? AppDelegate)?.showOnboarding()
                }
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开控制台", systemImage: "slider.horizontal.3")
            }

            Divider()

            Button("退出程序") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 300)
        .task {
            if !model.onboardingComplete {
                (NSApp.delegate as? AppDelegate)?.showOnboarding()
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
