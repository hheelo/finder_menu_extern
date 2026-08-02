import Foundation
import Testing
@testable import RightClickCore

struct ExecutablePathParserTests {
    @Test
    func readsPlainExecutablePath() {
        #expect(
            ExecutablePathParser.executablePath(in: "/opt/homebrew/bin/codex\n")
                == "/opt/homebrew/bin/codex"
        )
    }

    /// 交互式登录 shell 会 source rc 文件，横幅同样写到 stdout，
    /// 路径由 `command -v` 最后打印。
    @Test
    func ignoresLeadingNoiseFromLoginShell() {
        let output = """
        Welcome back!
        [oh-my-zsh] plugins updated

        /usr/local/bin/claude
        """
        #expect(
            ExecutablePathParser.executablePath(in: output)
                == "/usr/local/bin/claude"
        )
    }

    /// `command -v` 命中别名/函数/内建时打印定义本身而非路径，退出码仍是 0。
    /// 这些都不是路径，不能被当成「已安装」展示。实测样本见注释。
    @Test
    func rejectsAliasFunctionAndBuiltinDefinitions() {
        // 实测：zsh 中 `command -v ls` 的输出
        #expect(ExecutablePathParser.executablePath(in: "alias ls='ls -G'") == nil)
        // 实测：函数与内建命令只回显命令名
        #expect(ExecutablePathParser.executablePath(in: "myfunc") == nil)
        #expect(ExecutablePathParser.executablePath(in: "cd") == nil)
    }

    @Test
    func returnsNilForEmptyOutput() {
        #expect(ExecutablePathParser.executablePath(in: "") == nil)
        #expect(ExecutablePathParser.executablePath(in: "\n  \n") == nil)
    }

    /// 噪声出现在路径之后时也要能挑出路径。
    @Test
    func picksThePathEvenWhenTrailingNoiseFollows() {
        let output = """
        /opt/homebrew/bin/codex
        alias codex='codex --yolo'
        """
        #expect(
            ExecutablePathParser.executablePath(in: output)
                == "/opt/homebrew/bin/codex"
        )
    }

    @Test
    func trimsSurroundingWhitespace() {
        #expect(
            ExecutablePathParser.executablePath(in: "   /usr/bin/env   ")
                == "/usr/bin/env"
        )
    }
}
