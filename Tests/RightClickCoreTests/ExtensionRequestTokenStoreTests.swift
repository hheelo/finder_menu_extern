import Foundation
import Testing
@testable import RightClickCore

struct ExtensionRequestTokenStoreTests {
    @Test
    func generatesCanonicalRandomTokens() {
        let first = ExtensionRequestTokenStore.makeToken()
        let second = ExtensionRequestTokenStore.makeToken()

        #expect(ExtensionRequestTokenStore.isValidToken(first))
        #expect(ExtensionRequestTokenStore.isValidToken(second))
        #expect(first != second)
    }

    @Test
    func extensionCreatesOnceAndHostReadsTheSameToken() throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let applicationSupport = home
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(
                AppConstants.finderExtensionBundleIdentifier,
                isDirectory: true
            )
            .appendingPathComponent(
                "Data/Library/Application Support",
                isDirectory: true
            )
        let first = ExtensionRequestTokenStore.makeToken()
        let second = ExtensionRequestTokenStore.makeToken()

        let created = try ExtensionRequestTokenStore.loadOrCreateForExtension(
            applicationSupportDirectory: applicationSupport,
            tokenGenerator: { first }
        )
        let loadedAgain = try ExtensionRequestTokenStore.loadOrCreateForExtension(
            applicationSupportDirectory: applicationSupport,
            tokenGenerator: { second }
        )

        #expect(created == first)
        #expect(loadedAgain == first)
        #expect(
            ExtensionRequestTokenStore.loadForHost(homeDirectory: home) == first
        )

        let tokenURL = ExtensionRequestTokenStore.hostTokenFileURL(
            homeDirectory: home
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: tokenURL.path
        )
        let permissions = try #require(
            attributes[.posixPermissions] as? NSNumber
        ).intValue
        #expect(permissions & 0o777 == 0o600)
    }

    @Test
    func invalidPersistedTokenIsReplaced() throws {
        let support = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: support) }

        let tokenURL = ExtensionRequestTokenStore.tokenFileURL(
            applicationSupportDirectory: support
        )
        try FileManager.default.createDirectory(
            at: tokenURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-a-token".utf8).write(to: tokenURL)
        let replacement = ExtensionRequestTokenStore.makeToken()

        let loaded = try ExtensionRequestTokenStore.loadOrCreateForExtension(
            applicationSupportDirectory: support,
            tokenGenerator: { replacement }
        )
        #expect(loaded == replacement)
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
