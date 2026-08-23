import Foundation
@testable import RightClickAppLogic
import RightClickCore
import Testing

struct NonceCacheTests {
    @Test
    func rejectsReplayWithinWindowAndAcceptsExpiredNonce() {
        let cache = NonceCache()
        let firstUse = Date(timeIntervalSince1970: 1_000)

        #expect(cache.consume("nonce", now: firstUse))
        #expect(cache.consume("nonce", now: firstUse.addingTimeInterval(30)) == false)
        #expect(cache.consume("nonce", now: firstUse.addingTimeInterval(31)))
    }

    @Test
    func lazyCleanupDoesNotChangeExpirySemantics() {
        let cache = NonceCache()
        let firstUse = Date(timeIntervalSince1970: 1_000)
        for index in 0..<140 {
            #expect(cache.consume("old-\(index)", now: firstUse))
        }

        let afterWindow = firstUse.addingTimeInterval(
            DeepLinkSignature.validityWindow + 1
        )
        #expect(cache.consume("new", now: afterWindow))
        #expect(cache.consume("old-0", now: afterWindow))
    }
}
