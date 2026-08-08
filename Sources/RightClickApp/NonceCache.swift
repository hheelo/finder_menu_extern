import Foundation
import RightClickCore

/// 防止已验证签名在有效窗口内被重放。
///
/// 这是进程内缓存：宿主重启后会清空。持久化 30 秒的 nonce 需要
/// 额外锁与清理协议，成本与剩余风险不成比例。
final class NonceCache {
    private var seen: [String: Date] = [:]

    func consume(_ nonce: String, now: Date) -> Bool {
        seen = seen.filter { _, date in
            let age = now.timeIntervalSince(date)
            return age >= 0 && age <= DeepLinkSignature.validityWindow
        }
        guard seen[nonce] == nil else { return false }
        seen[nonce] = now
        return true
    }
}
