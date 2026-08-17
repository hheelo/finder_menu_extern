import AppKit
import FinderSync
import RightClickCore

enum FinderSessionError: LocalizedError {
    case unableToTerminate
    case terminationTimedOut
    case unableToReopen(String)

    var errorDescription: String? {
        switch self {
        case .unableToTerminate:
            L10n.text(
                "error.finder_restart",
                fallback: "无法重启 Finder，请退出登录后重试。"
            )
        case .terminationTimedOut:
            L10n.text(
                "error.finder_timeout",
                fallback: "Finder 未能退出，请退出登录后重试。"
            )
        case let .unableToReopen(message):
            L10n.format(
                "error.finder_reopen",
                fallback: "无法重新打开 Finder：%@",
                message
            )
        }
    }
}

@MainActor
final class FinderSessionManager {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func extensionIsEnabled() async -> Bool? {
        if #available(macOS 14.4, *) {
            return FIFinderSyncController.isExtensionEnabled
        }
        return await LegacyFinderExtensionStatus.isEnabled()
    }

    /// 返回 true 时已经先落盘本版本标记，调用方随后只尝试一次自动重启。
    func consumeRequiredRefresh() -> Bool {
        guard let version = Self.bundleVersion,
              settings.finderSessionBuild != version else {
            return false
        }

        // 先落标记再重启：这一步只应在每次升级后尝试一次。如果标记留到重启
        // 成功后才写，重启路径上的任何崩溃或挂起都会在下次启动时原样重演，
        // 把 App 变成永远打不开的死循环（0.2.6 就是这样）。重启真的失败时
        // 用户仍可用界面上的「重启 Finder」按钮手动重试。
        settings.finderSessionBuild = version
        return true
    }

    func restartFinder() async throws {
        let finder = NSWorkspace.shared.runningApplications.first(
            where: { $0.bundleIdentifier == "com.apple.finder" }
        )
        if let finder, !finder.terminate() {
            throw FinderSessionError.unableToTerminate
        }

        if let finder {
            for _ in 0..<30 where !finder.isTerminated {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard finder.isTerminated else {
                throw FinderSessionError.terminationTimedOut
            }
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let finderURL = URL(
            fileURLWithPath: "/System/Library/CoreServices/Finder.app",
            isDirectory: true
        )

        do {
            // 必须用 async API：completionHandler 版本的闭包会继承
            // @MainActor 隔离，而 LaunchServices 在自己的队列上回调，Swift 6
            // 的运行时隔离断言会直接让进程 SIGTRAP。
            _ = try await NSWorkspace.shared.openApplication(
                at: finderURL,
                configuration: configuration
            )
        } catch {
            throw FinderSessionError.unableToReopen(error.localizedDescription)
        }
    }

    /// 同时包含短版本号和构建号：只看其中一个都可能漏掉本地构建或发布升级，
    /// 让 Finder 继续加载旧扩展。拼装由 `AppVersion` 与界面、诊断共用。
    private static var bundleVersion: String? {
        AppVersion.displayString
    }
}

/// macOS 14.0–14.3 的 Finder 扩展状态检测。
enum LegacyFinderExtensionStatus {
    static func isEnabled(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/pluginkit"),
        logFailure: @escaping @Sendable (String) -> Void = { message in
            appLogger.error("\(message, privacy: .public)")
        }
    ) async -> Bool? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = [
                "-m", "-A", "-D", "-i",
                AppConstants.finderExtensionBundleIdentifier
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                logFailure(
                    "无法启动 pluginkit 检测 Finder 扩展状态："
                        + error.localizedDescription
                )
                return nil
            }

            // 查询结果很小；先读到 EOF 可避免未来 verbose 输出增大后堵住管道。
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                logFailure(
                    "pluginkit 检测 Finder 扩展状态失败，退出码："
                        + String(process.terminationStatus)
                )
                return nil
            }

            return AppConstants.plugInKitOutputIndicatesEnabled(
                String(decoding: data, as: UTF8.self)
            )
        }.value
    }
}
