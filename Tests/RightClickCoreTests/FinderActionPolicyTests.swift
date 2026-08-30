import Testing
@testable import RightClickCore

struct FinderActionPolicyTests {
    @Test
    func onlyClipboardCreationDependsOnClipboardText() {
        for action in RightClickAction.allMenuActions {
            #expect(FinderActionPolicy.isSatisfied(action, hasClipboardText: true))
            #expect(
                FinderActionPolicy.isSatisfied(
                    action,
                    hasClipboardText: false
                ) == (action != .createFileFromClipboard)
            )
        }
    }

    @Test
    func onlyHostActionsRequireAuthentication() {
        for action in RightClickAction.allMenuActions {
            let expected: Bool
            switch action {
            case .copyPath, .copyFilename, .copyFileURL, .copyShellPath,
                 .copyParentPath, .copyRelativePath:
                expected = false
            case .openInVSCode, .openInCodex, .openInTerminal,
                 .runCodexCLI, .runClaudeCode, .openInCursor, .openInZed,
                 .openInSublimeText, .openInXcode, .openInJetBrains,
                 .openInDefaultApplication, .createFile, .createFolder,
                 .createFileFromClipboard:
                expected = true
            }
            #expect(
                FinderActionPolicy.requiresAuthenticatedHost(action)
                    == expected
            )
        }
    }

    @Test
    func hostActionsAreForwardedAndLocalActionsSucceed() {
        for action in RightClickAction.allMenuActions {
            let expected: LocalActionResult = FinderActionPolicy
                .requiresAuthenticatedHost(action) ? .forwarded : .succeeded
            #expect(FinderActionPolicy.successResult(for: action) == expected)
        }
    }

    @Test
    func mapsFinderFailuresToStableLogCategories() {
        let cases: [(FinderActionError, LocalActionErrorCategory)] = [
            (.invalidTarget, .invalidTarget),
            (.invalidWorkingDirectory, .invalidWorkingDirectory),
            (
                .tooManyOpenTargets(count: 129, maximum: 128),
                .tooManyTargets
            ),
            (.authenticationUnavailable, .authenticationUnavailable),
            (.configurationUnavailable, .configurationUnavailable),
            (.hostApplicationUnavailable, .hostApplicationUnavailable)
        ]

        for (error, category) in cases {
            #expect(FinderActionPolicy.errorCategory(for: error) == category)
        }
        #expect(
            FinderActionPolicy.errorCategory(for: TestFailure()) == .unknown
        )
    }

    @Test
    func everyFinderFailureHasAUsefulLocalizedDescription() {
        let errors: [FinderActionError] = [
            .invalidTarget,
            .invalidWorkingDirectory,
            .tooManyOpenTargets(count: 129, maximum: 128),
            .authenticationUnavailable,
            .configurationUnavailable,
            .hostApplicationUnavailable
        ]

        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
        let targetLimit = FinderActionError.tooManyOpenTargets(
            count: 129,
            maximum: 128
        ).errorDescription ?? ""
        #expect(targetLimit.contains("128"))
        #expect(targetLimit.contains("129"))
    }

    @Test
    func rejectsTargetCountsAboveTheLimitWithoutTruncating() {
        #expect(FinderActionPolicy.openTargetError(count: 128) == nil)
        #expect(
            FinderActionPolicy.openTargetError(count: 129)
                == .tooManyOpenTargets(count: 129, maximum: 128)
        )
    }

    @Test
    func onlyAnUnavailableHostSuppressesRecursiveReporting() {
        #expect(
            !FinderActionPolicy.shouldReportToHost(
                FinderActionError.hostApplicationUnavailable
            )
        )
        #expect(
            FinderActionPolicy.shouldReportToHost(
                FinderActionError.invalidTarget
            )
        )
        #expect(
            FinderActionPolicy.shouldReportToHost(
                FinderActionError.configurationUnavailable
            )
        )
        #expect(FinderActionPolicy.shouldReportToHost(TestFailure()))
    }
}

private struct TestFailure: Error {}
