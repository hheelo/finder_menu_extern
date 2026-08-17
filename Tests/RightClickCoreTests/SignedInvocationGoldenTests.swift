import Foundation
import Testing
@testable import RightClickCore

struct SignedInvocationGoldenTests {
    private let token = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let nonce = "123E4567-E89B-12D3-A456-426614174000"
    private let directory = URL(
        fileURLWithPath: "/tmp/RightClick Golden/项目",
        isDirectory: true
    )

    @Test
    func publishedSignedURLsRemainByteForByteStable() throws {
        let urls = try [
            CLIInvocation(
                command: .claude,
                workingDirectory: directory,
                authenticationToken: token
            ).deepLink(now: now, nonce: nonce),
            ConfiguredCLIInvocation(
                profileID: "gemini-main",
                workingDirectory: directory,
                authenticationToken: token
            ).deepLink(now: now, nonce: nonce),
            TerminalInvocation(
                workingDirectory: directory,
                authenticationToken: token
            ).deepLink(now: now, nonce: nonce),
            OpenInvocation(
                application: .visualStudioCode,
                targets: [
                    directory.appendingPathComponent("a&b.txt"),
                    directory.appendingPathComponent("Alice's.md")
                ],
                authenticationToken: token
            ).deepLink(now: now, nonce: nonce),
            ErrorInvocation(
                message: "无法创建：a&b=1",
                authenticationToken: token
            ).deepLink(now: now, nonce: nonce)
        ].map { try #require($0).absoluteString }

        let expected = [
            "rightclick://run?tool=claude&cwd=/tmp/RightClick%20Golden/%E9%A1%B9%E7%9B%AE&v=2&ts=1700000000&nonce=123E4567-E89B-12D3-A456-426614174000&sig=y+l41JF1+2hll34UJ/UgvARYBkt1R0VNcDzh7QIpoMc%3D",
            "rightclick://run-configured?profile=gemini-main&cwd=/tmp/RightClick%20Golden/%E9%A1%B9%E7%9B%AE&v=2&ts=1700000000&nonce=123E4567-E89B-12D3-A456-426614174000&sig=r05McY1hyOVfVppDh6jMa1mPW3lDvxdsVH7XQf394/0%3D",
            "rightclick://terminal?cwd=/tmp/RightClick%20Golden/%E9%A1%B9%E7%9B%AE&v=2&ts=1700000000&nonce=123E4567-E89B-12D3-A456-426614174000&sig=OuuOEEHSCC90YpfhhO8cCnmY1qoefWdNg4m57WcsT68%3D",
            "rightclick://open?app=vscode&path=/tmp/RightClick%20Golden/%E9%A1%B9%E7%9B%AE/a%26b.txt&path=/tmp/RightClick%20Golden/%E9%A1%B9%E7%9B%AE/Alice's.md&v=2&ts=1700000000&nonce=123E4567-E89B-12D3-A456-426614174000&sig=FvUZJts0goUKijtks17xmSJp3t1fbIa2TdP2LcnSXsg%3D",
            "rightclick://error?message=%E6%97%A0%E6%B3%95%E5%88%9B%E5%BB%BA%EF%BC%9Aa%26b%3D1&v=2&ts=1700000000&nonce=123E4567-E89B-12D3-A456-426614174000&sig=SDuJTg9L0XnzaEfskrwf/jW3LRQYAHTyoVDthT32ko0%3D"
        ]

        #expect(urls == expected)
    }
}
