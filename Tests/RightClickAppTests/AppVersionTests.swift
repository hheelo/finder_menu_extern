import Testing

@MainActor
struct AppVersionTests {
    @Test
    func combinesShortVersionAndBuild() throws {
        let version = try #require(AppVersion.resolve(infoDictionary: [
            "CFBundleShortVersionString": "0.8.3",
            "CFBundleVersion": "803"
        ]))
        #expect(version.displayString == "0.8.3 (803)")
    }

    @Test
    func fallsBackToShortVersionWhenBuildIsMissing() throws {
        let version = try #require(AppVersion.resolve(infoDictionary: [
            "CFBundleShortVersionString": "0.8.3"
        ]))
        #expect(version.displayString == "0.8.3")
    }

    @Test
    func returnsNilWhenShortVersionIsMissing() {
        #expect(AppVersion.resolve(infoDictionary: [:]) == nil)
        #expect(AppVersion.resolve(infoDictionary: nil) == nil)
    }

    @Test
    func diagnosticsUsesTheSharedDisplayString() throws {
        let version = try #require(AppVersion.displayString)
        let report = AppDiagnostics.report(
            [],
            terminalProfile: .terminal,
            terminalWindowBehavior: .newTab
        )
        #expect(report.hasPrefix("RightClick \(version)\n"))
    }
}
