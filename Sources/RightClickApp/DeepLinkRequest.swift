import Foundation
import RightClickCore

enum DeepLinkRequest: Equatable {
    case cli(CLIInvocation)
    case terminal(TerminalInvocation)
    case open(OpenInvocation)
    case error(ErrorInvocation)

    enum Authentication: Equatable {
        case authenticated
        /// 只用于升级过渡：新宿主可能暂时收到旧 Finder 扩展发出的无令牌
        /// terminal/open 请求。v0.7.0 移除该兼容分支。
        case legacyUnsigned
    }

    var authentication: Authentication {
        switch self {
        case .cli, .error:
            .authenticated
        case let .terminal(invocation):
            invocation.authenticationToken == nil
                ? .legacyUnsigned
                : .authenticated
        case let .open(invocation):
            invocation.authenticationToken == nil
                ? .legacyUnsigned
                : .authenticated
        }
    }

    init(
        deepLink url: URL,
        expectedAuthenticationToken: String?
    ) throws {
        guard url.scheme == AppConstants.deepLinkScheme else {
            throw DeepLinkRequestError.invalidScheme
        }

        switch url.host {
        case "run":
            guard let invocation = CLIInvocation(deepLink: url),
                  ExtensionRequestTokenStore.tokensMatch(
                      invocation.authenticationToken,
                      expectedAuthenticationToken
                  ) else {
                throw DeepLinkRequestError.invalidCLI
            }
            self = .cli(invocation)
        case "terminal":
            guard let invocation = TerminalInvocation(deepLink: url),
                  invocation.authenticationToken == nil ||
                    ExtensionRequestTokenStore.tokensMatch(
                        invocation.authenticationToken,
                        expectedAuthenticationToken
                    ) else {
                throw DeepLinkRequestError.invalidTerminal
            }
            self = .terminal(invocation)
        case "open":
            guard let invocation = OpenInvocation(deepLink: url),
                  invocation.authenticationToken == nil ||
                    ExtensionRequestTokenStore.tokensMatch(
                        invocation.authenticationToken,
                        expectedAuthenticationToken
                    ) else {
                throw DeepLinkRequestError.invalidOpen
            }
            self = .open(invocation)
        case "error":
            guard let invocation = ErrorInvocation(deepLink: url),
                  ExtensionRequestTokenStore.tokensMatch(
                      invocation.authenticationToken,
                      expectedAuthenticationToken
                  ) else {
                throw DeepLinkRequestError.invalidError
            }
            self = .error(invocation)
        default:
            throw DeepLinkRequestError.unknownAction(url.host)
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
