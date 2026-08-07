import AppKit
import RightClickCore

/// 把用户设置解析成当前机器上确定安装的终端。
@MainActor
struct TerminalResolver {
    func resolvedProfile(for configured: TerminalProfile) -> TerminalProfile {
        let workspace = NSWorkspace.shared
        let resolved = configured.resolved { application in
            application.url(
                bundleIdentifierLookup: {
                    workspace.urlForApplication(withBundleIdentifier: $0)
                }
            ) != nil
        }
        appLogger.notice("""
            终端已解析 设置=\(configured.rawValue, privacy: .public) \
            实际=\(resolved.rawValue, privacy: .public)
            """)
        return resolved
    }

    func resolvedApplication(
        for configured: TerminalProfile
    ) -> ExternalApplication {
        resolvedProfile(for: configured).resolvedApplication
    }
}
