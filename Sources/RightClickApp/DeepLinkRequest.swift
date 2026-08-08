import Foundation
import RightClickCore

struct DeepLinkRequest: Equatable {
    enum Payload: Equatable {
        case cli(CLIInvocation)
        case terminal(TerminalInvocation)
        case open(OpenInvocation)
        case error(ErrorInvocation)
    }

    enum Authentication: Equatable {
        case authenticated
        /// v0.6.1 扩展仍会把令牌直接放进 URL。v0.7.0 与无签名
        /// terminal/open 过渡分支一起移除。
        case legacyToken
        /// 只用于升级过渡：新宿主可能暂时收到旧 Finder 扩展发出的无令牌
        /// terminal/open 请求。v0.7.0 移除该兼容分支。
        case legacyUnsigned
    }

    let payload: Payload
    let authentication: Authentication

    init(
        deepLink url: URL,
        expectedAuthenticationToken: String?,
        now: Date = Date(),
        consumeNonce: (String, Date) -> Bool = { _, _ in true }
    ) throws {
        guard url.scheme == AppConstants.deepLinkScheme else {
            throw DeepLinkRequestError.invalidScheme
        }

        switch url.host {
        case "run":
            guard let invocation = CLIInvocation(deepLink: url) else {
                throw DeepLinkRequestError.invalidCLI
            }
            payload = .cli(invocation)
        case "terminal":
            guard let invocation = TerminalInvocation(deepLink: url) else {
                throw DeepLinkRequestError.invalidTerminal
            }
            payload = .terminal(invocation)
        case "open":
            guard let invocation = OpenInvocation(deepLink: url) else {
                throw DeepLinkRequestError.invalidOpen
            }
            payload = .open(invocation)
        case "error":
            guard let invocation = ErrorInvocation(deepLink: url) else {
                throw DeepLinkRequestError.invalidError
            }
            payload = .error(invocation)
        default:
            throw DeepLinkRequestError.unknownAction(url.host)
        }

        guard let transportAuthentication = DeepLinkSignature.authentication(
            in: url
        ) else {
            throw Self.rejection(for: payload)
        }
        switch transportAuthentication {
        case let .signed(signed):
            guard let expectedAuthenticationToken,
                  DeepLinkSignature.verify(
                      signed,
                      deepLink: url,
                      token: expectedAuthenticationToken,
                      now: now
                  ), consumeNonce(signed.nonce, now) else {
                throw Self.rejection(for: payload)
            }
            authentication = .authenticated
        case let .legacyToken(token):
            guard ExtensionRequestTokenStore.tokensMatch(
                token,
                expectedAuthenticationToken
            ) else {
                throw Self.rejection(for: payload)
            }
            authentication = .legacyToken
        case .unsigned:
            switch payload {
            case .terminal, .open:
                authentication = .legacyUnsigned
            case .cli, .error:
                throw Self.rejection(for: payload)
            }
        }
    }

    private static func rejection(
        for payload: Payload
    ) -> DeepLinkRequestError {
        switch payload {
        case .cli: .invalidCLI
        case .terminal: .invalidTerminal
        case .open: .invalidOpen
        case .error: .invalidError
        }
    }
}

enum DeepLinkRequestError: Error, Equatable {
    case invalidScheme
    case invalidCLI
    case invalidTerminal
    case invalidOpen
    case invalidError
    case unknownAction(String?)

    var rejectionReason: String {
        switch self {
        case .invalidScheme:
            "链接协议不是 rightclick。"
        case .invalidCLI:
            "CLI 请求无效或未通过本机 Finder 扩展认证。"
        case .invalidTerminal:
            "终端请求无效、未通过认证，或工作目录不是现有的绝对文件夹路径。"
        case .invalidOpen:
            "打开请求无效或未通过认证：应用必须在白名单中，目标必须是现有的绝对路径。"
        case .invalidError:
            "错误报告无效或未通过本机 Finder 扩展认证。"
        case let .unknownAction(host):
            "未知的 RightClick 操作：\(host ?? "缺少操作名")。"
        }
    }
}
