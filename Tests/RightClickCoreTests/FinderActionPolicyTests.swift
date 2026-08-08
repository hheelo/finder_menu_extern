import Testing
@testable import RightClickCore

struct FinderActionPolicyTests {
    @Test
    func onlyHostActionsRequireAuthentication() {
        for action in RightClickAction.allMenuActions {
            let expected: Bool
            switch action {
            case .copyPath, .copyFilename, .copyFileURL, .copyShellPath,
                 .copyParentPath, .createFile:
                expected = false
            case .openInVSCode, .openInCodex, .openInTerminal,
                 .runCodexCLI, .runClaudeCode:
                expected = true
            }
            #expect(
                FinderActionPolicy.requiresAuthenticatedHost(action)
                    == expected
            )
        }
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
        #expect(FinderActionPolicy.shouldReportToHost(TestFailure()))
    }
}

private struct TestFailure: Error {}
