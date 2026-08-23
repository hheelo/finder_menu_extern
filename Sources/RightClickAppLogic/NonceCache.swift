import Foundation
import RightClickCore

public final class NonceCache {
    private static let cleanupThreshold = 128
    private var seen: [String: Date] = [:]

    public init() {}

    public func consume(_ nonce: String, now: Date) -> Bool {
        if let previous = seen[nonce] {
            let age = now.timeIntervalSince(previous)
            if age >= 0 && age <= DeepLinkSignature.validityWindow {
                return false
            }
            seen.removeValue(forKey: nonce)
        }
        if seen.count >= Self.cleanupThreshold {
            seen = seen.filter { _, date in
                let age = now.timeIntervalSince(date)
                return age >= 0 && age <= DeepLinkSignature.validityWindow
            }
        }
        seen[nonce] = now
        return true
    }
}
