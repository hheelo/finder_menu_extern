import Foundation
import RightClickCore

/// A side-effect-free description of the work requested by a Finder menu item.
/// FinderSync remains responsible for AppKit calls, logging, and user-visible errors.
public struct FinderActionPlan: Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case copy(String)
        case openHost(URL)
    }

    public let action: LocalActionName
    public let successResult: LocalActionResult
    public let operation: Operation

    public init(
        action: LocalActionName,
        successResult: LocalActionResult,
        operation: Operation
    ) {
        self.action = action
        self.successResult = successResult
        self.operation = operation
    }
}

/// Converts stable menu payloads and a selection snapshot into an executable plan.
/// Keeping URL construction and stale-configuration handling here makes the real
/// Finder extension a thin AppKit boundary and lets every action route run in tests.
public enum FinderActionDispatcher {
    public static func plan(
        for payload: MenuItemPayload,
        context: SelectionContext,
        configuration: MenuConfiguration,
        authenticationToken: String?
    ) throws -> FinderActionPlan {
        switch payload {
        case let .action(payload):
            return try plan(
                for: payload.action,
                context: context,
                configuration: configuration,
                authenticationToken: authenticationToken
            )
        case let .configuredCLI(payload):
            return try configuredCLIPlan(
                payload,
                context: context,
                configuration: configuration,
                authenticationToken: authenticationToken
            )
        case let .customTemplate(payload):
            return try customTemplatePlan(
                payload,
                context: context,
                configuration: configuration,
                authenticationToken: authenticationToken
            )
        }
    }

    public static func requiresAuthentication(
        for payload: MenuItemPayload
    ) -> Bool {
        switch payload {
        case let .action(payload):
            FinderActionPolicy.requiresAuthenticatedHost(payload.action)
        case .configuredCLI, .customTemplate:
            true
        }
    }

    public static func actionName(for payload: MenuItemPayload) -> LocalActionName {
        switch payload {
        case let .action(payload): LocalActionName(payload.action)
        case .configuredCLI: .configuredCLI
        case .customTemplate: .customTemplate
        }
    }

    private static func plan(
        for action: RightClickAction,
        context: SelectionContext,
        configuration: MenuConfiguration,
        authenticationToken: String?
    ) throws -> FinderActionPlan {
        let actionName = LocalActionName(action)
        let successResult = FinderActionPolicy.successResult(for: action)

        switch action {
        case .copyPath, .copyFilename, .copyFileURL, .copyShellPath,
             .copyParentPath, .copyRelativePath:
            // Repository discovery is intentionally delayed until the click. Doing
            // filesystem traversal while building the menu adds visible latency.
            let base = action == .copyRelativePath
                ? RelativePathResolver.base(for: context)
                : nil
            guard let text = ClipboardText.text(
                for: action,
                urls: context.effectiveURLs,
                base: base,
                separator: configuration.clipboardSeparator
            ), !text.isEmpty else {
                throw FinderActionError.invalidTarget
            }
            return FinderActionPlan(
                action: actionName,
                successResult: successResult,
                operation: .copy(text)
            )

        case .openInVSCode, .openInCodex, .openInCursor, .openInZed,
             .openInSublimeText, .openInXcode, .openInJetBrains,
             .openInDefaultApplication:
            if let error = FinderActionPolicy.openTargetError(
                count: context.effectiveURLs.count
            ) {
                throw error
            }
            guard let application = ExternalApplication.forOpenAction(action),
                  let token = authenticationToken,
                  let deepLink = OpenInvocation(
                      application: application,
                      targets: context.effectiveURLs,
                      authenticationToken: token
                  ).deepLink else {
                throw authenticationToken == nil
                    ? FinderActionError.authenticationUnavailable
                    : FinderActionError.invalidTarget
            }
            return FinderActionPlan(
                action: actionName,
                successResult: successResult,
                operation: .openHost(deepLink)
            )

        case let .createFile(template):
            return try creationPlan(
                request: .builtInTemplate(template),
                action: actionName,
                context: context,
                authenticationToken: authenticationToken
            )
        case .createFolder:
            return try creationPlan(
                request: .folder,
                action: actionName,
                context: context,
                authenticationToken: authenticationToken
            )
        case .createFileFromClipboard:
            return try creationPlan(
                request: .clipboardText,
                action: actionName,
                context: context,
                authenticationToken: authenticationToken
            )
        case .openInTerminal:
            guard let token = authenticationToken else {
                throw FinderActionError.authenticationUnavailable
            }
            guard let directory = context.workingDirectory,
                  let deepLink = TerminalInvocation(
                      workingDirectory: directory,
                      authenticationToken: token
                  ).deepLink else {
                throw FinderActionError.invalidWorkingDirectory
            }
            return FinderActionPlan(
                action: actionName,
                successResult: successResult,
                operation: .openHost(deepLink)
            )
        case .runCodexCLI:
            return try cliPlan(
                command: .codex,
                context: context,
                authenticationToken: authenticationToken
            )
        case .runClaudeCode:
            return try cliPlan(
                command: .claude,
                context: context,
                authenticationToken: authenticationToken
            )
        }
    }

    private static func cliPlan(
        command: CLICommand,
        context: SelectionContext,
        authenticationToken: String?
    ) throws -> FinderActionPlan {
        guard let token = authenticationToken else {
            throw FinderActionError.authenticationUnavailable
        }
        guard let directory = context.workingDirectory,
              let deepLink = CLIInvocation(
                  command: command,
                  workingDirectory: directory,
                  authenticationToken: token
              ).deepLink else {
            throw FinderActionError.invalidWorkingDirectory
        }
        return FinderActionPlan(
            action: LocalActionName(command),
            successResult: .forwarded,
            operation: .openHost(deepLink)
        )
    }

    private static func configuredCLIPlan(
        _ payload: ConfiguredCLIMenuItemPayload,
        context: SelectionContext,
        configuration: MenuConfiguration,
        authenticationToken: String?
    ) throws -> FinderActionPlan {
        guard let profile = configuration.cliProfile(forSlot: payload.menuSlot)
        else {
            throw FinderActionError.configurationUnavailable
        }
        guard let token = authenticationToken else {
            throw FinderActionError.authenticationUnavailable
        }
        guard let directory = context.workingDirectory,
              let deepLink = ConfiguredCLIInvocation(
                  profileID: profile.id,
                  workingDirectory: directory,
                  authenticationToken: token
              ).deepLink else {
            throw FinderActionError.invalidWorkingDirectory
        }
        return FinderActionPlan(
            action: .configuredCLI,
            successResult: .forwarded,
            operation: .openHost(deepLink)
        )
    }

    private static func customTemplatePlan(
        _ payload: CustomTemplateMenuItemPayload,
        context: SelectionContext,
        configuration: MenuConfiguration,
        authenticationToken: String?
    ) throws -> FinderActionPlan {
        guard let template = configuration.customTemplate(
            forSlot: payload.menuSlot
        ) else {
            throw FinderActionError.configurationUnavailable
        }
        return try creationPlan(
            request: .customTemplate(menuSlot: template.menuSlot),
            action: .customTemplate,
            context: context,
            authenticationToken: authenticationToken
        )
    }

    private static func creationPlan(
        request: FileCreationInvocation.Request,
        action: LocalActionName,
        context: SelectionContext,
        authenticationToken: String?
    ) throws -> FinderActionPlan {
        guard let token = authenticationToken else {
            throw FinderActionError.authenticationUnavailable
        }
        guard let directory = context.creationDirectory,
              let deepLink = FileCreationInvocation(
                  request: request,
                  directory: directory,
                  authenticationToken: token
              ).deepLink else {
            throw FinderActionError.invalidTarget
        }
        return FinderActionPlan(
            action: action,
            successResult: .forwarded,
            operation: .openHost(deepLink)
        )
    }
}
