import Foundation
import Testing
@testable import RightClickCore

struct RequestStoreTests {
    @Test
    func requestRoundTripsAndIsConsumed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = RequestStore(rootURL: root)
        let request = ActionRequest(
            action: .runCodexCLI,
            selectedURLs: [URL(fileURLWithPath: "/tmp/project", isDirectory: true)],
            targetedURL: nil
        )

        try store.enqueue(request)
        #expect(try store.take(id: request.id) == request)
        #expect(throws: RequestStoreError.self) {
            try store.take(id: request.id)
        }
    }
}
