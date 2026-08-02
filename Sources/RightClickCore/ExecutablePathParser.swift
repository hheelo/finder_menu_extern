import Foundation

/// 解析 `command -v` 在登录 shell 中的输出。
///
/// 单独放在 Core 而不是留在宿主的诊断代码里，是因为这段解析有两个容易踩空的
/// 地方，需要能脱离 AppKit 单独测试：
///
/// 1. 交互式登录 shell 会 source 用户的 rc 文件，其中的横幅、提示同样写到
///    stdout，所以整段输出不能直接当路径。
/// 2. `command -v` 命中别名、函数或内建命令时打印的是**定义本身**而非路径
///    （实测 `command -v ls` 输出 `alias ls='ls -G'`，函数和内建则回显命令名），
///    且退出码仍是 0。只按「最后一行非空内容」取值，诊断里就会出现一行明显
///    不是路径的内容，还被标成「已安装」。
public enum ExecutablePathParser {
    /// 从输出中取出可执行文件的绝对路径；没有则返回 `nil`。
    ///
    /// 只认以 `/` 开头的行，并取最后一条——真正的路径由 `command -v` 最后打印，
    /// 之前的行都是 rc 文件的噪声。
    public static func executablePath(in output: String) -> String? {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
    }
}
