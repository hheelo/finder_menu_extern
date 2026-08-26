import Foundation
import Testing
@testable import RightClickCore

struct FileCreationInvocationTests {
    @Test(arguments: [
        FileCreationInvocation.Request.builtInTemplate(.markdown),
        .folder,
        .clipboardText,
        .customTemplate(menuSlot: 7)
    ])
    func roundTripsEveryCreationRequest(
        _ request: FileCreationInvocation.Request
    ) throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = ExtensionRequestTokenStore.makeToken()
        let invocation = FileCreationInvocation(
            request: request,
            directory: directory,
            authenticationToken: token
        )

        let deepLink = try #require(invocation.deepLink)
        let parsed = try #require(FileCreationInvocation(deepLink: deepLink))
        #expect(parsed.request == request)
        #expect(parsed.directory == directory.standardizedFileURL)
    }

    @Test
    func rejectsMissingRelativeAndMalformedRequests() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalidURLs = [
            "rightclick://create?path=relative&kind=folder",
            "rightclick://create?path=\(directory.path)&kind=unknown",
            "rightclick://create?path=\(directory.path)&kind=built-in",
            "rightclick://create?path=\(directory.path)&kind=folder&slot=1",
            "rightclick://create?path=\(directory.path)&kind=custom&slot=0"
        ]
        for value in invalidURLs {
            #expect(FileCreationInvocation(
                deepLink: try #require(URL(string: value))
            ) == nil)
        }
    }

    @Test
    func doesNotEncodeAnInvalidCustomTemplateSlot() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(FileCreationInvocation(
            request: .customTemplate(menuSlot: 0),
            directory: directory
        ).deepLink == nil)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }
}
