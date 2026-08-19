import Foundation

/// 发布脚本专用的最小 UI 就绪探针。
///
/// 只有显式传入临时目录时才生效，并且目录必须位于系统临时目录之下。主视图
/// `onAppear` 后写入固定的 ready 文件，让打包验证可以确认签名后的 App 不只是
/// 进程存活，而是已经完成 SwiftUI 首屏呈现。
enum AppSmokeTest {
    static let directoryEnvironmentKey = "RIGHTCLICK_SMOKE_TEST_DIRECTORY"

    static func markReady(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        guard let readyFileURL = readyFileURL(
            environment: environment,
            temporaryDirectory: temporaryDirectory
        ) else { return }

        try? Data("ready\n".utf8).write(to: readyFileURL, options: .atomic)
    }

    static func readyFileURL(
        environment: [String: String],
        temporaryDirectory: URL
    ) -> URL? {
        guard let path = environment[directoryEnvironmentKey], !path.isEmpty else {
            return nil
        }

        let temporaryRoot = temporaryDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let directory = URL(fileURLWithPath: path, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard directory.path.hasPrefix(temporaryRoot.path + "/") else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return nil
        }
        return directory.appendingPathComponent("ready", isDirectory: false)
    }
}
