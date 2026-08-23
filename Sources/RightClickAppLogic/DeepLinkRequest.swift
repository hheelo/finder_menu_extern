import Foundation
import RightClickCore

public struct DeepLinkRequest: Equatable {
    public enum Payload: Equatable {
        case cli(CLIInvocation)
        case configuredCLI(ConfiguredCLIInvocation)
        case terminal(TerminalInvocation)
        case open(OpenInvocation)
        case error(ErrorInvocation)
    }

    public let payload: Payload

    public init(
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
        case "run-configured":
            guard let invocation = ConfiguredCLIInvocation(deepLink: url) else {
                throw DeepLinkRequestError.invalidCLI
            }
            payload = .configuredCLI(invocation)
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

        guard let authentication = DeepLinkSignature.authentication(in: url)
        else {
            throw Self.rejection(for: payload)
        }
        switch authentication {
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
        case .unsigned:
            throw Self.rejection(for: payload)
        }
    }

    private static func rejection(for payload: Payload) -> DeepLinkRequestError {
        switch payload {
        case .cli, .configuredCLI: .invalidCLI
        case .terminal: .invalidTerminal
        case .open: .invalidOpen
        case .error: .invalidError
        }
    }
}

public enum DeepLinkRequestError: Error, Equatable {
    case invalidScheme
    case invalidCLI
    case invalidTerminal
    case invalidOpen
    case invalidError
    case unknownAction(String?)

    public var rejectionReason: String {
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
