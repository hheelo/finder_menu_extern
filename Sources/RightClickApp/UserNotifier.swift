@preconcurrency import UserNotifications
import Foundation
import RightClickCore

struct AppErrorRecord: Identifiable, Equatable {
    let id: UUID
    let message: String
    let date: Date

    init(
        id: UUID = UUID(),
        message: String,
        date: Date = Date()
    ) {
        self.id = id
        self.message = message
        self.date = date
    }
}

@MainActor
protocol UserNotifying {
    func report(_ message: String)
}

/// 用通知中心而不是 NSAlert：宿主是附属应用，弹模态会把它抢到前台，
/// 而用户此刻正在 Finder 里操作文件。
@MainActor
struct SystemUserNotifier: UserNotifying {
    func report(_ message: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var authorized = settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                authorized = (try? await center.requestAuthorization(
                    options: [.alert, .sound]
                )) == true
            }
            // 用户拒绝权限时，AppModel 仍会保留错误历史，不会丢失失败原因。
            guard authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = L10n.text(
                "notification.failure_title",
                fallback: "RightClick 操作失败"
            )
            content.body = message
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
