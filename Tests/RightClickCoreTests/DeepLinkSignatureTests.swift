import CryptoKit
import Foundation
import Testing
@testable import RightClickCore

struct DeepLinkSignatureTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let nonce = "00000000-0000-4000-8000-000000000001"

    @Test
    func signsWithoutPuttingTheTokenInTheURL() throws {
        let token = ExtensionRequestTokenStore.makeToken()
        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: FileManager.default.temporaryDirectory,
            authenticationToken: token
        )
        let url = try #require(invocation.deepLink(now: now, nonce: nonce))
        let authentication = try #require(
            DeepLinkSignature.authentication(in: url)
        )
        guard case let .signed(signed) = authentication else {
            Issue.record("请求未使用签名认证")
            return
        }

        #expect(!url.absoluteString.contains("token="))
        #expect(!url.absoluteString.contains(token))
        #expect(
            DeepLinkSignature.verify(
                signed,
                deepLink: url,
                token: token,
                now: now
            )
        )
    }

    @Test
    func rejectsWrongKeyExpiredFutureAndTamperedRequests() throws {
        let token = ExtensionRequestTokenStore.makeToken()
        let wrongToken = ExtensionRequestTokenStore.makeToken()
        let invocation = CLIInvocation(
            command: .claude,
            workingDirectory: FileManager.default.temporaryDirectory,
            authenticationToken: token
        )
        let url = try #require(invocation.deepLink(now: now, nonce: nonce))
        let authentication = try #require(
            DeepLinkSignature.authentication(in: url)
        )
        guard case let .signed(signed) = authentication else {
            Issue.record("请求未使用签名认证")
            return
        }

        #expect(
            !DeepLinkSignature.verify(
                signed,
                deepLink: url,
                token: wrongToken,
                now: now
            )
        )
        for offset in [-31.0, 31.0] {
            #expect(
                !DeepLinkSignature.verify(
                    signed,
                    deepLink: url,
                    token: token,
                    now: now.addingTimeInterval(offset)
                )
            )
        }

        var components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let toolIndex = try #require(
            components.queryItems?.firstIndex { $0.name == "tool" }
        )
        components.queryItems?[toolIndex].value = "codex"
        #expect(
            !DeepLinkSignature.verify(
                signed,
                deepLink: try #require(components.url),
                token: token,
                now: now
            )
        )
    }

    @Test
    func parameterOrderIsAuthenticated() throws {
        let token = ExtensionRequestTokenStore.makeToken()
        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "run"
        components.queryItems = [
            URLQueryItem(name: "tool", value: "codex"),
            URLQueryItem(name: "cwd", value: "/tmp")
        ]
        let url = try #require(
            DeepLinkSignature.signedURL(
                components: components,
                token: token,
                now: now,
                nonce: nonce
            )
        )
        guard case let .signed(signed) = DeepLinkSignature.authentication(
            in: url
        ) else {
            Issue.record("请求未使用签名认证")
            return
        }
        var reordered = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let semantic = try #require(reordered.queryItems?.prefix(2))
        reordered.queryItems?.replaceSubrange(0..<2, with: semantic.reversed())

        #expect(
            !DeepLinkSignature.verify(
                signed,
                deepLink: try #require(reordered.url),
                token: token,
                now: now
            )
        )
    }

    @Test
    func signatureAuthenticatesTheProtocolVersion() throws {
        let token = ExtensionRequestTokenStore.makeToken()
        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "run"
        components.queryItems = [
            URLQueryItem(name: "tool", value: "codex"),
            URLQueryItem(name: "cwd", value: "/tmp")
        ]
        let url = try #require(
            DeepLinkSignature.signedURL(
                components: components,
                token: token,
                now: now,
                nonce: nonce
            )
        )
        let signedComponents = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let signature = try #require(
            signedComponents.queryItems?.first { $0.name == "sig" }?.value
        )
        let keyData = try #require(Data(base64Encoded: token))
        let semanticFields = ["v2", "run", "tool", "codex", "cwd", "/tmp"]
            + [String(Int64(now.timeIntervalSince1970)), nonce]
        let canonical = semanticFields.map {
            "\($0.utf8.count):\($0)"
        }.joined()
        let expected = Data(HMAC<SHA256>.authenticationCode(
            for: Data(canonical.utf8),
            using: SymmetricKey(data: keyData)
        )).base64EncodedString()

        #expect(signature == expected)
    }
}
