@preconcurrency import AppKit
import Foundation
import RightClickCore
import Testing
@testable import RightClickFinderAdapter

/// Finder 的 `menu(for:)` 在主线程执行。这个基线使用发布边界内的高负载配置，
/// 既记录可比较的耗时，也用宽松上界拦住意外文件 I/O、指数递归等量级回归。
@MainActor
struct FinderMenuPerformanceTests {
    private static let iterations = 20
    private static let maximumDurationNanoseconds: UInt64 = 5_000_000_000

    @Test
    func realisticHighLoadMenuStaysWithinInteractiveBudget() throws {
        let configuration = MenuConfiguration(
            cliProfiles: (1...20).map {
                CLIProfile(
                    id: "cli-\($0)",
                    title: "CLI \($0)",
                    executable: "command-\($0)",
                    arguments: ["--profile", "\($0)"],
                    menuSlot: $0
                )
            },
            customTemplates: (1...50).map {
                CustomFileTemplate(
                    id: "template-\($0)",
                    title: "Template \($0)",
                    filename: "Template \($0).txt",
                    menuSlot: $0
                )
            }
        )
        let selectedURLs = (1...OpenInvocation.maximumTargets).map {
            URL(fileURLWithPath: "/tmp/rightclick-performance/file-\($0)")
        }
        let context = SelectionContext(
            selectedURLs: selectedURLs,
            targetedURL: nil
        )
        let nodes = RightClickMenu.nodes(
            placement: .items,
            context: context,
            configuration: configuration
        )
        let target = PerformanceMenuTarget()

        // 第一次 AppKit/SF Symbols 初始化不计入稳态菜单基线。
        _ = FinderMenuRenderer.menu(
            nodes: nodes,
            placement: .items,
            hasClipboardText: true,
            authenticationAvailable: true,
            target: target,
            action: #selector(PerformanceMenuTarget.perform(_:))
        )

        let started = DispatchTime.now().uptimeNanoseconds
        var renderedItemCount = 0
        for _ in 0..<Self.iterations {
            autoreleasepool {
                let menu = FinderMenuRenderer.menu(
                    nodes: nodes,
                    placement: .items,
                    hasClipboardText: true,
                    authenticationAvailable: true,
                    target: target,
                    action: #selector(PerformanceMenuTarget.perform(_:))
                )
                renderedItemCount += menu.map(recursiveItemCount) ?? 0
            }
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        let milliseconds = Double(elapsed) / 1_000_000

        #expect(renderedItemCount > 0)
        #expect(elapsed < Self.maximumDurationNanoseconds)
        print(
            "PERFORMANCE FinderMenu high-load: \(Self.iterations) iterations, "
                + String(format: "%.2f ms", milliseconds)
        )
    }

    private func recursiveItemCount(_ menu: NSMenu) -> Int {
        menu.items.reduce(0) { count, item in
            count + 1 + (item.submenu.map(recursiveItemCount) ?? 0)
        }
    }
}

@MainActor
private final class PerformanceMenuTarget: NSObject {
    @objc func perform(_ sender: NSMenuItem) {}
}
