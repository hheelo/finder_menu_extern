import Foundation
import Testing
@testable import RightClickCore

struct ConfiguredCLIInvocationTests {
    @Test
    func signedLinkCarriesOnlyIDAndDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = ExtensionRequestTokenStore.makeToken()
        let invocation = ConfiguredCLIInvocation(
            profileID: "gemini-main",
            workingDirectory: directory,
            authenticationToken: token
        )

        let url = try #require(invocation.deepLink)
        #expect(url.host == "run-configured")
        #expect(url.absoluteString.contains("profile=gemini-main"))
        #expect(!url.absoluteString.contains("executable"))
        #expect(!url.absoluteString.contains("arguments"))
        #expect(ConfiguredCLIInvocation(deepLink: url) == invocation)
    }

    @Test
    func rejectsInvalidIDsAndPaths() {
        let invalid = ConfiguredCLIInvocation(
            profileID: "sh -c payload",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(invalid.deepLink == nil)
    }
}
