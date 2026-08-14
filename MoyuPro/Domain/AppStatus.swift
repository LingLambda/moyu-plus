import Foundation

enum AppStatus: Equatable {
    case disabled
    case requestingPermission
    case running
    case suspected
    case triggered
    case paused
    case cameraUnavailable(String)
    case modelUnavailable(String)
    case error(String)

    var title: String {
        switch self {
        case .disabled: "尚未启用"
        case .requestingPermission: "正在请求权限"
        case .running: "保护运行中"
        case .suspected: "检测到第二人"
        case .triggered: "保护已触发"
        case .paused: "已暂停"
        case .cameraUnavailable: "摄像头不可用"
        case .modelUnavailable: "模型不可用"
        case .error: "运行异常"
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            "完成说明后手动启用摄像头检测"
        case .requestingPermission:
            "请在系统提示中允许摄像头和通知权限"
        case .running:
            "画面仅在本机内存中处理"
        case .suspected:
            "正在连续确认画面中的人体候选"
        case .triggered:
            "通知已发送，手动恢复后允许再次触发"
        case .paused:
            "摄像头采集与推理已停止"
        case let .cameraUnavailable(message),
             let .modelUnavailable(message),
             let .error(message):
            message
        }
    }

    var symbolName: String {
        switch self {
        case .running: "eye.fill"
        case .suspected: "person.2.fill"
        case .triggered: "shield.lefthalf.filled.badge.checkmark"
        case .paused, .disabled: "pause.circle.fill"
        case .requestingPermission: "hourglass"
        case .cameraUnavailable: "video.slash.fill"
        case .modelUnavailable, .error: "exclamationmark.triangle.fill"
        }
    }
}
