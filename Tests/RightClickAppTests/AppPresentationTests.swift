import Testing

struct AppPresentationTests {
    @Test(arguments: [true, false], [true, false])
    func visibilityIncludesUserLaunchAndExplicitPresentation(
        isUserLaunch: Bool,
        isPresentationRequested: Bool
    ) {
        #expect(
            AppPresentation.isUserVisible(
                isUserLaunch: isUserLaunch,
                isPresentationRequested: isPresentationRequested
            ) == (isUserLaunch || isPresentationRequested)
        )
    }

    @Test
    func launchDeepLinkImmediatelyMakesColdLaunchHeadless() {
        var state = AppLaunchState()
        #expect(state.isUserLaunch)

        let shouldHideLaunchWindow = state.receiveDeepLink()
        #expect(shouldHideLaunchWindow)
        #expect(!state.isUserLaunch)

        state.finish(isDefaultLaunch: true)
        #expect(!state.isUserLaunch)
        #expect(state.hasFinishedLaunching)
    }

    @Test(arguments: [true, false])
    func finishClassifiesLaunchWithoutADeepLink(
        isDefaultLaunch: Bool
    ) {
        var state = AppLaunchState()

        state.finish(isDefaultLaunch: isDefaultLaunch)

        #expect(state.isUserLaunch == isDefaultLaunch)
        #expect(state.hasFinishedLaunching)
    }

    @Test
    func postLaunchDeepLinkDoesNotReclassifyTheSession() {
        var state = AppLaunchState()
        state.finish(isDefaultLaunch: true)

        let shouldHideLaunchWindow = state.receiveDeepLink()
        #expect(!shouldHideLaunchWindow)
        #expect(state.isUserLaunch)
    }

    @Test(arguments: [true, false], [true, false])
    func reopenChoosesTheExpectedWindowAction(
        hasVisibleWindows: Bool,
        hasPresentableWindow: Bool
    ) {
        let expected: ReopenAction
        if hasPresentableWindow {
            expected = .restoreExisting
        } else if hasVisibleWindows {
            expected = .keepVisible
        } else {
            expected = .createWindow
        }

        #expect(ReopenPolicy.action(
            hasVisibleWindows: hasVisibleWindows,
            hasPresentableWindow: hasPresentableWindow
        ) == expected)
    }
}
