import Foundation

/// 不同登录 Shell 的命令行参数与可执行文件查找语法。
public enum LoginShellArguments {
    public static func arguments(
        shellName: String,
        script: String,
        interactive: Bool
    ) -> [String] {
        switch normalized(shellName) {
        case "fish":
            return interactive
                ? ["-l", "-i", "-c", script]
                : ["-l", "-c", script]
        case "nu":
            // Nushell 的 command-string 模式只有加 -l 才会读取 env.nu、
            // config.nu 与 login.nu；它没有用于该场景的 POSIX -i 语义。
            return ["-l", "-c", script]
        default:
            return [interactive ? "-lic" : "-lc", script]
        }
    }

    public static func executableLookupScript(
        shellName: String,
        command: String
    ) -> String {
        if normalized(shellName) == "nu" {
            // `which` 返回表；只接受 external，避免把 alias/custom command
            // 当成磁盘上的 CLI。command 来自 CLICommand 枚举，不含用户输入。
            return "which \(command) | where type == external | get path | first | print"
        }
        return "command -v -- \(command) 2>/dev/null"
    }

    public static func supportsInteractiveFallback(shellName: String) -> Bool {
        normalized(shellName) != "nu"
    }

    private static func normalized(_ shellName: String) -> String {
        URL(fileURLWithPath: shellName).lastPathComponent.lowercased()
    }
}
