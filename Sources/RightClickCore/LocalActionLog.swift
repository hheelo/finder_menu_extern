import Foundation

/// 本地动作日志只接受封闭的稳定标识，调用方无法把路径、文件名、命令参数或
/// 深链 URL 塞进记录。导出的日志因此可以直接附到 Issue，而不泄露操作目标。
public enum LocalActionLogSource: String, Codable, Sendable {
    case host
    case finderExtension = "finder-extension"
}
public enum LocalActionName: String, Codable, Sendable {
    case applicationSession = "application-session"
    case extensionErrorReport = "extension-error-report"
    case unknownMenuAction = "unknown-menu-action"
    case configuredCLI = "configured-cli"
    case customTemplate = "custom-template"
    case copyPath
    case copyFilename
    case copyFileURL
    case copyShellPath
    case copyParentPath
    case copyRelativePath
    case openInVSCode
    case openInCodex
    case openInTerminal
    case runCodexCLI
    case runClaudeCode
    case openInCursor
    case openInZed
    case openInSublimeText
    case openInXcode
    case openInJetBrains
    case openInDefaultApplication
    case createTextFile = "createFile(text)"
    case createMarkdownFile = "createFile(markdown)"
    case createPythonFile = "createFile(python)"
    case createShellFile = "createFile(shell)"
    case createHTMLFile = "createFile(html)"
    case createJSONFile = "createFile(json)"
    case createCSVFile = "createFile(csv)"
    case createFolder
    case createFileFromClipboard

    public init(_ action: RightClickAction) {
        switch action {
        case .copyPath: self = .copyPath
        case .copyFilename: self = .copyFilename
        case .copyFileURL: self = .copyFileURL
        case .copyShellPath: self = .copyShellPath
        case .copyParentPath: self = .copyParentPath
        case .copyRelativePath: self = .copyRelativePath
        case .openInVSCode: self = .openInVSCode
        case .openInCodex: self = .openInCodex
        case .openInTerminal: self = .openInTerminal
        case .runCodexCLI: self = .runCodexCLI
        case .runClaudeCode: self = .runClaudeCode
        case .openInCursor: self = .openInCursor
        case .openInZed: self = .openInZed
        case .openInSublimeText: self = .openInSublimeText
        case .openInXcode: self = .openInXcode
        case .openInJetBrains: self = .openInJetBrains
        case .openInDefaultApplication: self = .openInDefaultApplication
        case let .createFile(template):
            switch template {
            case .text: self = .createTextFile
            case .markdown: self = .createMarkdownFile
            case .python: self = .createPythonFile
            case .shell: self = .createShellFile
            case .html: self = .createHTMLFile
            case .json: self = .createJSONFile
            case .csv: self = .createCSVFile
            }
        case .createFolder: self = .createFolder
        case .createFileFromClipboard: self = .createFileFromClipboard
        }
    }

    public init(_ command: CLICommand) {
        switch command {
        case .codex: self = .runCodexCLI
        case .claude: self = .runClaudeCode
        }
    }

    public init(opening application: ExternalApplication) {
        switch application.identifier {
        case ExternalApplication.visualStudioCode.identifier:
            self = .openInVSCode
        case ExternalApplication.codex.identifier:
            self = .openInCodex
        case ExternalApplication.cursor.identifier:
            self = .openInCursor
        case ExternalApplication.zed.identifier:
            self = .openInZed
        case ExternalApplication.sublimeText.identifier:
            self = .openInSublimeText
        case ExternalApplication.xcode.identifier:
            self = .openInXcode
        case ExternalApplication.jetBrains.identifier:
            self = .openInJetBrains
        default:
            self = .openInDefaultApplication
        }
    }
}

public enum LocalActionResult: String, Codable, Sendable {
    case started
    case received
    case forwarded
    case succeeded
    case failed
}

public enum LocalActionErrorCategory: String, Codable, Sendable {
    case invalidRequest = "invalid-request"
    case invalidTarget = "invalid-target"
    case invalidWorkingDirectory = "invalid-working-directory"
    case tooManyTargets = "too-many-targets"
    case authenticationUnavailable = "authentication-unavailable"
    case configurationUnavailable = "configuration-unavailable"
    case hostApplicationUnavailable = "host-application-unavailable"
    case applicationNotFound = "application-not-found"
    case commandUnavailable = "command-unavailable"
    case unsupportedTerminal = "unsupported-terminal"
    case applicationLaunchFailed = "application-launch-failed"
    case executionFailed = "execution-failed"
    case fileSystem = "file-system"
    case extensionReported = "extension-reported"
    case unexpectedTermination = "unexpected-termination"
    case cancelled
    case unknown

    public init(_ error: Error) {
        if let finderError = error as? FinderActionError {
            switch finderError {
            case .invalidTarget: self = .invalidTarget
            case .invalidWorkingDirectory: self = .invalidWorkingDirectory
            case .tooManyOpenTargets: self = .tooManyTargets
            case .authenticationUnavailable: self = .authenticationUnavailable
            case .configurationUnavailable: self = .configurationUnavailable
            case .hostApplicationUnavailable: self = .hostApplicationUnavailable
            }
        } else if error is FileCreatorError || error is CocoaError {
            self = .fileSystem
        } else if error is CancellationError {
            self = .cancelled
        } else {
            self = .unknown
        }
    }
}

public struct LocalActionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let source: LocalActionLogSource
    public let action: LocalActionName
    public let result: LocalActionResult
    public let errorCategory: LocalActionErrorCategory?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        source: LocalActionLogSource,
        action: LocalActionName,
        result: LocalActionResult,
        errorCategory: LocalActionErrorCategory? = nil
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.action = action
        self.result = result
        self.errorCategory = errorCategory
    }
}
