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
    func rejectsEmptyLongUnsignedAndForeignRequests() {
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
            ) == nil
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
