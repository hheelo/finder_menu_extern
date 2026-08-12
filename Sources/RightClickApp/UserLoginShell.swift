import Darwin
import Foundation
import RightClickCore

/// App 层负责读取进程环境和 Directory Services；候选优先级与校验规则由 Core
/// 的 `LoginShell` 统一决定，诊断和实际执行必须调用同一个入口。
enum UserLoginShell {
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        passwordEntryShell: String? = currentPasswordEntryShell(),
        fileManager: FileManager = .default
    ) -> URL {
        LoginShell.resolve(
            environmentShell: environment["SHELL"],
            passwordEntryShell: passwordEntryShell,
            isExecutableFile: fileManager.isExecutableFile(atPath:)
        )
    }

    private static func currentPasswordEntryShell() -> String? {
        guard let user = getpwuid(getuid()),
              let shell = user.pointee.pw_shell,
              shell.pointee != 0 else {
            return nil
        }
        return String(cString: shell)
    }
}
