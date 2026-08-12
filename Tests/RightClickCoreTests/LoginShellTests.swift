import Foundation
import Testing
@testable import RightClickCore

struct LoginShellTests {
    @Test
    func validEnvironmentShellWins() {
        let resolved = LoginShell.resolve(
            environmentShell: "/opt/homebrew/bin/fish",
            passwordEntryShell: "/bin/bash",
            isExecutableFile: { ["/opt/homebrew/bin/fish", "/bin/bash"].contains($0) }
        )
        #expect(resolved.path == "/opt/homebrew/bin/fish")
    }

    @Test
    func relativeEnvironmentShellFallsBackToPasswordEntry() {
        let resolved = LoginShell.resolve(
            environmentShell: "bin/fish",
            passwordEntryShell: "/bin/bash",
            isExecutableFile: { $0 == "/bin/bash" }
        )
        #expect(resolved.path == "/bin/bash")
    }

    @Test
    func nonExecutableEnvironmentShellFallsBackToPasswordEntry() {
        let resolved = LoginShell.resolve(
            environmentShell: "/missing/fish",
            passwordEntryShell: "/bin/bash",
            isExecutableFile: { $0 == "/bin/bash" }
        )
        #expect(resolved.path == "/bin/bash")
    }

    @Test
    func invalidCandidatesFallBackToZsh() {
        let resolved = LoginShell.resolve(
            environmentShell: "/missing/fish",
            passwordEntryShell: "relative/bash",
            isExecutableFile: { _ in false }
        )
        #expect(resolved.path == "/bin/zsh")
    }
}
