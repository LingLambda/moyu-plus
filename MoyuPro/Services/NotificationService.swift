@preconcurrency import UserNotifications
import Foundation

enum NotificationServiceError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "通知权限不可用，请在系统设置 > 通知 > 大墨鱼中允许通知"
    }
}

enum NotificationPermissionState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    func ensureAuthorized() async throws {
        guard await permissionState() == .authorized else {
            throw NotificationServiceError.permissionDenied
        }
    }

    func sendProtectionNotification(
        title: String,
        body: String,
        identifier: String = "moyu-pro-protection-trigger"
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
