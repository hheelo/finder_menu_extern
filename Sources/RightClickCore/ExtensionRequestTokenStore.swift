import Darwin
import Foundation

public enum ExtensionRequestTokenStore {
    private static let tokenByteCount = 32
    private static let supportDirectoryName = "RightClick"
    private static let tokenFilename = "extension-request-token"
    private static let lockFilename = "extension-request-token.lock"

    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<tokenByteCount).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        }
        return Data(bytes).base64EncodedString()
    }

    public static func isValidToken(_ token: String) -> Bool {
        guard let data = Data(base64Encoded: token),
              data.count == tokenByteCount else {
            return false
        }
        return data.base64EncodedString() == token
    }

    public static func loadOrCreateForExtension(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        tokenGenerator: () -> String = {
            ExtensionRequestTokenStore.makeToken()
        }
    ) throws -> String {
        let supportDirectory = applicationSupportDirectory
            ?? fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        guard let supportDirectory else {
            throw ExtensionRequestTokenError.applicationSupportUnavailable
        }

        let tokenURL = tokenFileURL(
            applicationSupportDirectory: supportDirectory
        )
        if let existing = loadToken(at: tokenURL) {
            return existing
        }

        let directory = tokenURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let lockURL = directory.appendingPathComponent(
            lockFilename,
            isDirectory: false
        )
        let descriptor = lockURL.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw ExtensionRequestTokenError.lockUnavailable
        }
        defer { Darwin.close(descriptor) }
        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        guard fcntl(descriptor, F_SETLKW, &lock) != -1 else {
            throw ExtensionRequestTokenError.lockUnavailable
        }
        defer {
            var unlock = flock()
            unlock.l_type = Int16(F_UNLCK)
            unlock.l_whence = Int16(SEEK_SET)
            _ = fcntl(descriptor, F_SETLK, &unlock)
        }

        // Finder 与打开/保存面板可能同时拉起扩展进程。锁内必须重新读取，
        // 保证所有实例采用同一个最终令牌。
        if let concurrentlyCreated = loadToken(at: tokenURL) {
            return concurrentlyCreated
        }

        let token = tokenGenerator()
        guard isValidToken(token) else {
            throw ExtensionRequestTokenError.invalidGeneratedToken
        }
        try Data(token.utf8).write(to: tokenURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenURL.path
        )

        // 原子替换完成后再读一次；即使有并发初始化，也以最终落盘值为准。
        guard let persisted = loadToken(at: tokenURL) else {
            throw ExtensionRequestTokenError.persistedTokenInvalid
        }
        return persisted
    }

    public static func loadForHost(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        loadToken(at: hostTokenFileURL(homeDirectory: homeDirectory))
    }

    public static func tokenFileURL(
        applicationSupportDirectory: URL
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(tokenFilename, isDirectory: false)
    }

    public static func hostTokenFileURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(
                AppConstants.finderExtensionBundleIdentifier,
                isDirectory: true
            )
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(tokenFilename, isDirectory: false)
    }

    private static func loadToken(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let token = String(data: data, encoding: .utf8),
              isValidToken(token) else {
            return nil
        }
        return token
    }
}

public enum ExtensionRequestTokenError: Error, Equatable {
    case applicationSupportUnavailable
    case lockUnavailable
    case invalidGeneratedToken
    case persistedTokenInvalid
}
