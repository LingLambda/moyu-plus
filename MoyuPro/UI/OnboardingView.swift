import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("大墨鱼")
                        .font(.largeTitle.bold())
                    Text("本地旁观风险提示")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                OnboardingRow(symbol: "video.fill", title: "仅在本机检测", detail: "摄像头画面只在内存中交给 Core ML 推理，不上传、不录制。")
                OnboardingRow(symbol: "person.2.fill", title: "只计算人体候选", detail: "人体候选数量达到阈值后会快速复核，不识别人脸或身份。")
                OnboardingRow(symbol: "bell.fill", title: "执行低调动作", detail: "触发时可切换窗口并发送自定义本地通知，默认等待手动恢复。")
                OnboardingRow(symbol: "pause.fill", title: "随时暂停", detail: "暂停会停止摄像头采集与推理。")
            }

            Spacer()

            HStack {
                Text("启用时 macOS 将请求摄像头和通知权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("暂不启用") {
                    model.pauseProtection(userInitiated: true)
                    model.markOnboardingComplete()
                    onClose()
                }
                Button {
                    Task {
                        await model.completeOnboardingAndEnable()
                        if model.isEnabled { onClose() }
                    }
                } label: {
                    if model.isEnabling {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("同意并启用")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isEnabling)
            }
        }
        .padding(28)
        .frame(width: 560, height: 460)
    }
}

private struct OnboardingRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
