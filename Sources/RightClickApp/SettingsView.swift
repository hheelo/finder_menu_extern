import SwiftUI
import RightClickAppLogic
import RightClickCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State var selectedTab: SettingsTab = .menu
    @State var confirmsFinderRestart = false
    @State var confirmsConfigurationReset = false
    @FocusState var focusedControl: SettingsFocus?
    @ScaledMetric(relativeTo: .body) var templateTitleWidth = 110
    @ScaledMetric(relativeTo: .body) var templateEncodingWidth = 150

    var body: some View {
        ZStack {
            AppSurfaceBackground()

            TabView(selection: $selectedTab) {
                menuSettings
                    .disabled(model.configurationRecoveryRequired)
                    .tabItem {
                        Label(
                            L10n.text("settings.tab.menu", fallback: "菜单"),
                            systemImage: "list.bullet.rectangle"
                        )
                    }
                    .tag(SettingsTab.menu)

                terminalSettings
                    .disabled(model.configurationRecoveryRequired)
                    .tabItem {
                        Label(
                            L10n.text("settings.tab.terminal", fallback: "终端"),
                            systemImage: "terminal"
                        )
                    }
                    .tag(SettingsTab.terminal)

                templateSettings
                    .disabled(model.configurationRecoveryRequired)
                    .tabItem {
                        Label(
                            L10n.text("settings.tab.templates", fallback: "模板"),
                            systemImage: "doc.badge.plus"
                        )
                    }
                    .tag(SettingsTab.templates)

                diagnosticSettings
                    .tabItem {
                        Label(
                            L10n.text(
                                "settings.tab.diagnostics",
                                fallback: "诊断"
                            ),
                            systemImage: "stethoscope"
                        )
                    }
                    .tag(SettingsTab.diagnostics)
            }
        }
        .frame(
            minWidth: 700,
            idealWidth: 780,
            minHeight: 500,
            idealHeight: 660
        )
        .finderRestartConfirmation(isPresented: $confirmsFinderRestart) {
            model.restartFinder()
        }
        .confirmationDialog(
            L10n.text(
                "settings.reset_configuration_confirmation",
                fallback: "重置 Finder 菜单设置？原配置会先保留备份。"
            ),
            isPresented: $confirmsConfigurationReset,
            titleVisibility: .visible
        ) {
            Button(
                L10n.text("button.reset_settings", fallback: "重置设置"),
                role: .destructive
            ) {
                model.resetConfigurationAfterRecovery()
            }
            Button(L10n.text("button.cancel", fallback: "取消"), role: .cancel) {}
        }
        .onAppear {
            focusFirstControl(in: selectedTab)
            if AppEnvironment.shouldCloseMainWindowOnSettingsForUITesting {
                DispatchQueue.main.async {
                    WindowPresenter.closeMainWindowForUITesting()
                }
            }
        }
        .onChange(of: selectedTab) { _, tab in
            focusFirstControl(in: tab)
        }
        .onDisappear {
            model.flushPendingMenuConfiguration()
        }
    }

    private func focusFirstControl(in tab: SettingsTab) {
        DispatchQueue.main.async {
            switch tab {
            case .menu: focusedControl = .collapseMenu
            case .terminal: focusedControl = .terminalProfile
            case .templates: focusedControl = .openTemplates
            case .diagnostics: focusedControl = .menuBarIcon
            }
        }
    }

}

enum SettingsTab: Hashable {
    case menu
    case terminal
    case templates
    case diagnostics
}

enum SettingsFocus: Hashable {
    case collapseMenu
    case terminalProfile
    case openTemplates
    case menuBarIcon
}
