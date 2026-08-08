import Testing
@testable import RightClickCore

struct LoginShellArgumentsTests {
    @Test
    func dispatchesArgumentsForPosixFishAndNu() {
        #expect(
            LoginShellArguments.arguments(
                shellName: "zsh",
                script: "echo ok",
                interactive: false
            ) == ["-lc", "echo ok"]
        )
        #expect(
            LoginShellArguments.arguments(
                shellName: "/bin/bash",
                script: "echo ok",
                interactive: true
            ) == ["-lic", "echo ok"]
        )
        #expect(
            LoginShellArguments.arguments(
                shellName: "/opt/homebrew/bin/fish",
                script: "echo ok",
                interactive: true
            ) == ["-l", "-i", "-c", "echo ok"]
        )
        #expect(
            LoginShellArguments.arguments(
                shellName: "/opt/homebrew/bin/nu",
                script: "echo ok",
                interactive: false
            ) == ["-l", "-c", "echo ok"]
        )
    }

    @Test
    func usesStructuredNushellLookup() {
        #expect(
            LoginShellArguments.executableLookupScript(
                shellName: "nu",
                command: "codex"
            ) == "which codex | where type == external | get path | first | print"
        )
        #expect(!LoginShellArguments.supportsInteractiveFallback(shellName: "nu"))
        #expect(LoginShellArguments.supportsInteractiveFallback(shellName: "fish"))
    }
}
