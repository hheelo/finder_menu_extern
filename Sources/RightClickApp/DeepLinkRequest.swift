import Foundation
import RightClickCore

enum DeepLinkRequest: Equatable {
    case cli(CLIInvocation)
    case terminal(TerminalInvocation)
    case open(OpenInvocation)

    init(
        deepLink url: URL,
        expectedCLIAuthenticationToken: String?
    ) throws {
        guard url.scheme == AppConstants.deepLinkScheme else {
            throw DeepLinkRequestError.invalidScheme
        }

        switch url.host {
        case "run":
            guard let invocation = CLIInvocation(deepLink: url),
                  ExtensionRequestTokenStore.tokensMatch(
                      invocation.authenticationToken,
                      expectedCLIAuthenticationToken
                  ) else {
                throw DeepLinkRequestError.invalidCLI
            }
            self = .cli(invocation)
        case "terminal":
            guard let invocation = TerminalInvocation(deepLink: url) else {
                throw DeepLinkRequestError.invalidTerminal
            }
            self = .terminal(invocation)
        case "open":
            guard let invocation = OpenInvocation(deepLink: url) else {
                throw DeepLinkRequestError.invalidOpen
            }
            self = .open(invocation)
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
    case unknownAction(String?)

    var rejectionReason: String {
        switch self {
        case .invalidScheme:
            "链接协议不是 rightclick。"
        case .invalidCLI:
            "CLI 请求无效或未通过本机 Finder 扩展认证。"
        case .invalidTerminal:
            "终端请求无效：工作目录必须是现有的绝对文件夹路径。"
        case .invalidOpen:
            "打开请求无效：应用必须在白名单中，目标必须是现有的绝对路径。"
        case let .unknownAction(host):
            "未知的 RightClick 操作：\(host ?? "缺少操作名")。"
        }
    }
}
