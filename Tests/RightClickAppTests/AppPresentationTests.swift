import Testing

struct AppPresentationTests {
    @Test
    func explicitUITestEnvironmentIsClassifiedAsATestRun() {
        let environment = [AppEnvironment.uiTestingEnvironmentKey: "1"]

        #expect(AppEnvironment.isRunningUITests(in: environment))
        #expect(AppEnvironment.isRunningTests(in: environment))
        #expect(!AppEnvironment.isRunningTests(in: [:]))
    }

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
    func reopenOnlyTreatsTheMainWindowAsRestorable(
        hasMainWindow: Bool,
        hasVisibleWindows: Bool
    ) {
        let expected: ReopenAction = hasMainWindow
            ? .restoreMainWindow
            : .createMainWindow

        #expect(ReopenPolicy.action(
            hasMainWindow: hasMainWindow,
            hasVisibleWindows: hasVisibleWindows
        ) == expected)
    }
}
