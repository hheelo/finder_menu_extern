import Foundation
import Testing
@testable import RightClickCore

struct ErrorInvocationTests {
    @Test
    func authenticatedMessageRoundTrips() throws {
        let token = ExtensionRequestTokenStore.makeToken()
        let invocation = ErrorInvocation(
            message: "无法创建文件：权限不足。",
            authenticationToken: token
        )

        #expect(
            ErrorInvocation(deepLink: try #require(invocation.deepLink))
                == invocation
        )
    }

    @Test
    func configurationUnavailableMessageFitsAndRoundTrips() throws {
        let token = ExtensionRequestTokenStore.makeToken()
        let message = try #require(
            FinderActionError.configurationUnavailable.errorDescription
        )
        #expect(message.count <= ErrorInvocation.maximumMessageLength)

        let invocation = ErrorInvocation(
            message: message,
            authenticationToken: token
        )
        #expect(
            ErrorInvocation(deepLink: try #require(invocation.deepLink))
                == invocation
        )
    }

    @Test
    func rejectsEmptyLongAndForeignRequests() {
        let token = ExtensionRequestTokenStore.makeToken()
        #expect(ErrorInvocation(message: "").deepLink == nil)
        #expect(
            ErrorInvocation(
                message: String(repeating: "x", count: 301),
                authenticationToken: token
            ).deepLink == nil
        )
        #expect(
            ErrorInvocation(
                deepLink: URL(string: "rightclick://error?message=unsigned")!
            )?.message == "unsigned"
        )
        #expect(
            ErrorInvocation(
                deepLink: URL(
                    string: "https://error?message=nope&token=\(token)"
                )!
            ) == nil
        )
    }
}
