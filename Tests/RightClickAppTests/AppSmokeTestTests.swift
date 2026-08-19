import Foundation
import Testing

struct AppSmokeTestTests {
    @Test
    func readyMarkerIsLimitedToAnExistingChildOfTheTemporaryDirectory() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let smokeDirectory = temporaryRoot
            .appendingPathComponent("smoke", isDirectory: true)
        try FileManager.default.createDirectory(
            at: smokeDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let environment = [
            AppSmokeTest.directoryEnvironmentKey: smokeDirectory.path
        ]
        let readyFile = AppSmokeTest.readyFileURL(
            environment: environment,
            temporaryDirectory: FileManager.default.temporaryDirectory
        )
        #expect(readyFile == smokeDirectory.appendingPathComponent("ready"))

        AppSmokeTest.markReady(environment: environment)
        #expect(FileManager.default.fileExists(atPath: readyFile?.path ?? ""))

        #expect(AppSmokeTest.readyFileURL(
            environment: [AppSmokeTest.directoryEnvironmentKey: "/Applications"],
            temporaryDirectory: FileManager.default.temporaryDirectory
        ) == nil)

        let escapedDirectory = temporaryRoot
            .appendingPathComponent("escaped", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: escapedDirectory,
            withDestinationURL: URL(fileURLWithPath: "/Applications")
        )
        #expect(AppSmokeTest.readyFileURL(
            environment: [
                AppSmokeTest.directoryEnvironmentKey: escapedDirectory.path
            ],
            temporaryDirectory: FileManager.default.temporaryDirectory
        ) == nil)
    }
}
