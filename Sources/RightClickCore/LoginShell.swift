import Foundation

/// 登录 shell 的唯一解析入口。
public enum LoginShell {
    /// 当前会话的 `SHELL` 最贴近用户实际终端环境；Directory Services 中的
    /// `pw_shell` 作为冷启动时的第二来源。两个候选都必须是绝对且真实可执行的
    /// 路径，避免继承污染或已卸载的 Homebrew shell 进入执行路径。
    public static func resolve(
        environmentShell: String?,
        passwordEntryShell: String?,
        isExecutableFile: (String) -> Bool
    ) -> URL {
        for candidate in [environmentShell, passwordEntryShell] {
            guard let candidate,
                  candidate.hasPrefix("/"),
                  isExecutableFile(candidate) else {
                continue
            }
            return URL(fileURLWithPath: candidate)
        }
        return AppConstants.defaultShellURL
    }
}
