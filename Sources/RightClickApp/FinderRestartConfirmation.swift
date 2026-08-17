import AppKit
import RightClickCore
import SwiftUI

private enum FinderRestartConfirmationText {
    static var title: String {
        L10n.text(
            "confirmation.restart_finder.title",
            fallback: "要重启 Finder 吗？"
        )
    }

    static var message: String {
        L10n.text(
            "confirmation.restart_finder.message",
            fallback: "这会关闭所有 Finder 窗口；确认后 Finder 会自动重新打开。"
        )
    }

    static var confirm: String {
        L10n.text("button.restart_finder", fallback: "重启 Finder")
    }

    static var cancel: String {
        L10n.text("button.cancel", fallback: "取消")
    }
}

extension View {
    func finderRestartConfirmation(
        isPresented: Binding<Bool>,
        restart: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            FinderRestartConfirmationText.title,
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button(
                FinderRestartConfirmationText.confirm,
                role: .destructive,
                action: restart
            )
            Button(FinderRestartConfirmationText.cancel, role: .cancel) {}
        } message: {
            Text(FinderRestartConfirmationText.message)
        }
    }
}

@MainActor
enum FinderRestartConfirmer {
    static func present(restart: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = FinderRestartConfirmationText.title
        alert.informativeText = FinderRestartConfirmationText.message
        alert.addButton(withTitle: FinderRestartConfirmationText.confirm)
        alert.addButton(withTitle: FinderRestartConfirmationText.cancel)

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    restart()
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            restart()
        }
    }
}
