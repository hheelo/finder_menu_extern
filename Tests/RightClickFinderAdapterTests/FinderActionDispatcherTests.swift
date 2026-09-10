import Foundation
import RightClickCore
import Testing
@testable import RightClickFinderAdapter

struct FinderActionDispatcherTests {
    private let token = ExtensionRequestTokenStore.makeToken()

    @Test
    func copyPlanUsesConfiguredSeparatorWithoutAuthentication() throws {
        let selected = [
            URL(fileURLWithPath: "/tmp/first file.txt"),
            URL(fileURLWithPath: "/tmp/second.txt")
        ]
        let payload = MenuItemPayload.action(RightClickMenuItemPayload(
            action: .copyPath,
            placement: .items
        ))
        var configuration = MenuConfiguration.default
        configuration.copySeparator = ClipboardSeparator.comma.rawValue

        #expect(!FinderActionDispatcher.requiresAuthentication(for: payload))
        let plan = try FinderActionDispatcher.plan(
            for: payload,
            context: SelectionContext(selectedURLs: selected, targetedURL: nil),
            configuration: configuration,
            authenticationToken: nil
        )

        #expect(plan.action == .copyPath)
        #expect(plan.successResult == .succeeded)
        #expect(plan.operation == .copy(selected.map(\.path).joined(separator: ", ")))
    }

    @Test(arguments: [
        RightClickAction.openInVSCode,
        .openInCodex,
        .openInCursor,
        .openInZed,
        .openInSublimeText,
        .openInXcode,
        .openInJetBrains,
        .openInDefaultApplication
    ])
    func everyOpenActionProducesAnAuthenticatedHostPlan(
        _ action: RightClickAction
    ) throws {
        try withDirectoryAndFile { directory, file in
            let payload = MenuItemPayload.action(RightClickMenuItemPayload(
                action: action,
                placement: .items
            ))
            let plan = try FinderActionDispatcher.plan(
                for: payload,
                context: SelectionContext(
                    selectedURLs: [file],
                    targetedURL: directory
                ),
                configuration: .default,
                authenticationToken: token
            )

            #expect(plan.successResult == .forwarded)
            let url = try hostURL(from: plan)
            #expect(url.host == "open")
            #expect(url.absoluteString.contains("sig="))
        }
    }

    @Test(arguments: [
        RightClickAction.openInTerminal,
        .runCodexCLI,
        .runClaudeCode,
        .createFolder,
        .createFileFromClipboard,
        .createFile(.text)
    ])
    func hostActionsRejectMissingAuthentication(_ action: RightClickAction) throws {
        try withDirectoryAndFile { directory, file in
            let payload = MenuItemPayload.action(RightClickMenuItemPayload(
                action: action,
                placement: .items
            ))
            #expect(FinderActionDispatcher.requiresAuthentication(for: payload))
            #expect(throws: FinderActionError.authenticationUnavailable) {
                try FinderActionDispatcher.plan(
                    for: payload,
                    context: SelectionContext(
                        selectedURLs: [file],
                        targetedURL: directory
                    ),
                    configuration: .default,
                    authenticationToken: nil
                )
            }
        }
    }

    @Test
    func terminalCLIAndCreationPlansUseTheirDedicatedRoutes() throws {
        try withDirectoryAndFile { directory, file in
            let context = SelectionContext(
                selectedURLs: [file],
                targetedURL: directory
            )
            let cases: [(RightClickAction, String)] = [
                (.openInTerminal, "terminal"),
                (.runCodexCLI, "run"),
                (.runClaudeCode, "run"),
                (.createFolder, "create"),
                (.createFileFromClipboard, "create"),
                (.createFile(.json), "create")
            ]

            for (action, expectedHost) in cases {
                let plan = try FinderActionDispatcher.plan(
                    for: .action(RightClickMenuItemPayload(
                        action: action,
                        placement: .items
                    )),
                    context: context,
                    configuration: .default,
                    authenticationToken: token
                )
                let url = try hostURL(from: plan)
                #expect(url.host == expectedHost)
            }
        }
    }

    @Test
    func dynamicRoutesResolveStableSlotsAndRejectStaleMenus() throws {
        try withDirectoryAndFile { directory, _ in
            let cli = CLIProfile(
                id: "gemini",
                title: "Gemini",
                executable: "gemini",
                menuSlot: 7
            )
            let template = CustomFileTemplate(
                id: "notes",
                title: "Notes",
                filename: "Notes.md",
                menuSlot: 9
            )
            let configuration = MenuConfiguration(
                cliProfiles: [cli],
                customTemplates: [template]
            )
            let context = SelectionContext(
                selectedURLs: [],
                targetedURL: directory
            )
            let cliPayload = MenuItemPayload.configuredCLI(
                ConfiguredCLIMenuItemPayload(menuSlot: 7, placement: .container)
            )
            let templatePayload = MenuItemPayload.customTemplate(
                CustomTemplateMenuItemPayload(menuSlot: 9, placement: .container)
            )

            let cliPlan = try FinderActionDispatcher.plan(
                for: cliPayload,
                context: context,
                configuration: configuration,
                authenticationToken: token
            )
            let templatePlan = try FinderActionDispatcher.plan(
                for: templatePayload,
                context: context,
                configuration: configuration,
                authenticationToken: token
            )
            let cliURL = try hostURL(from: cliPlan)
            let templateURL = try hostURL(from: templatePlan)
            #expect(cliURL.host == "run-configured")
            #expect(templateURL.host == "create")

            for payload in [cliPayload, templatePayload] {
                #expect(throws: FinderActionError.configurationUnavailable) {
                    try FinderActionDispatcher.plan(
                        for: payload,
                        context: context,
                        configuration: .default,
                        authenticationToken: token
                    )
                }
            }
        }
    }

    @Test
    func openPlanRejectsOversizedSelectionsBeforeBuildingAURL() throws {
        let urls = (0...OpenInvocation.maximumTargets).map {
            URL(fileURLWithPath: "/tmp/item-\($0)")
        }
        let payload = MenuItemPayload.action(RightClickMenuItemPayload(
            action: .openInVSCode,
            placement: .items
        ))

        #expect(throws: FinderActionError.tooManyOpenTargets(
            count: urls.count,
            maximum: OpenInvocation.maximumTargets
        )) {
            try FinderActionDispatcher.plan(
                for: payload,
                context: SelectionContext(selectedURLs: urls, targetedURL: nil),
                configuration: .default,
                authenticationToken: token
            )
        }
    }

    private func hostURL(from plan: FinderActionPlan) throws -> URL {
        guard case let .openHost(url) = plan.operation else {
            Issue.record("Expected a host-opening plan")
            throw FinderActionError.invalidTarget
        }
        return url
    }

    private func withDirectoryAndFile(
        _ body: (URL, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("selected.txt")
        try Data().write(to: file)
        try body(directory, file)
    }
}
