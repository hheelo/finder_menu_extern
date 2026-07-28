import Foundation
import Testing
@testable import RightClickCore

struct CLIInvocationTests {
    @Test
    func deepLinkRoundTripsSpecialCharacters() throws {
        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: URL(
                fileURLWithPath: "/tmp/Alice's 项目",
                isDirectory: true
            )
        )

        let deepLink = try #require(invocation.deepLink)
        #expect(CLIInvocation(deepLink: deepLink) == invocation)
    }

    @Test
    func rejectsUnrelatedURL() {
        let url = URL(string: "https://example.com")!
        #expect(CLIInvocation(deepLink: url) == nil)
    }
}
