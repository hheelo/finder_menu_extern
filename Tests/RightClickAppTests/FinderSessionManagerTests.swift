import Foundation
import Testing

struct FinderSessionManagerTests {
    @Test
    func legacyDetectionLaunchFailureIsUnavailableAndLogged() async {
        let recorder = FailureRecorder()
        let result = await LegacyFinderExtensionStatus.isEnabled(
            executableURL: URL(
                fileURLWithPath: "/definitely/missing/rightclick-pluginkit"
            ),
            logFailure: { recorder.append($0) }
        )

        #expect(result == nil)
        #expect(recorder.messages.count == 1)
        #expect(recorder.messages.first?.contains("pluginkit") == true)
    }

    @Test
    func legacyDetectionHasABoundedTimeout() async {
        let recorder = FailureRecorder()
        let startedAt = ContinuousClock.now
        let result = await LegacyFinderExtensionStatus.isEnabled(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"],
            timeout: 0.05,
            logFailure: { recorder.append($0) }
        )

        #expect(result == nil)
        #expect(startedAt.duration(to: .now) < .seconds(1))
        #expect(recorder.messages.count == 1)
        #expect(recorder.messages.first?.contains("pluginkit") == true)
    }
}

private final class FailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var messages: [String] {
        lock.withLock { storage }
    }

    func append(_ message: String) {
        lock.withLock { storage.append(message) }
    }
}
