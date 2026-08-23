import SwiftUI
import RightClickCore

extension SettingsView {
    var templateSettings: some View {
        Form {
            customTemplatesSection
            builtinTemplatesSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    var customTemplatesSection: some View {
        Section(L10n.text("settings.templates", fallback: "自定义文件模板")) {
            HStack {
                Button(L10n.text("button.open_templates", fallback: "打开模板目录")) {
                    model.openCustomTemplatesDirectory()
                }
                .focused($focusedControl, equals: .openTemplates)
                Button(L10n.text("button.refresh", fallback: "刷新模板")) {
                    Task { await model.refreshCustomTemplates() }
                }
                Spacer()
                Text(L10n.format(
                    "settings.synced_templates",
                    fallback: "已同步 %lld 个",
                    Int64(model.menuConfiguration.customTemplates.count)
                ))
                    .foregroundStyle(.secondary)
            }
            Text(L10n.text(
                "settings.templates_help",
                fallback: "把文件放入 ~/Library/Application Support/RightClick/Templates/，刷新后会按原文件名出现在 Finder 的“新建文件”菜单中。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

    }

    @ViewBuilder
    var builtinTemplatesSection: some View {
        Section(L10n.text(
            "settings.builtin_templates",
            fallback: "内置文件模板"
        )) {
            ForEach(FileTemplate.allCases, id: \.rawValue) { template in
                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(template.title)
                                .frame(
                                    minWidth: templateTitleWidth,
                                    alignment: .leading
                                )
                            templateFilenameField(for: template)
                            templateEncodingPicker(for: template)
                                .frame(minWidth: templateEncodingWidth)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(template.title)
                                .fontWeight(.semibold)
                            templateFilenameField(for: template)
                            templateEncodingPicker(for: template)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                        }
                    }
                    let filename = model.templateFilename(for: template)
                    if !filename.isEmpty,
                       !FileCreator.isSafeFilename(filename) {
                        Text(L10n.text(
                            "settings.invalid_template_filename",
                            fallback: "文件名无效，将使用内置默认值。"
                        ))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Text(L10n.text(
                "settings.builtin_templates_help",
                fallback: "文件名留空时使用内置默认值；非法文件名和未知编码会被安全忽略。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

    }

    func templateFilenameField(
        for template: FileTemplate
    ) -> some View {
        TextField(
            template.preferredFilename,
            text: Binding(
                get: { model.templateFilename(for: template) },
                set: { model.setTemplateFilename($0, for: template) }
            )
        )
    }

    func templateEncodingPicker(
        for template: FileTemplate
    ) -> some View {
        let label = L10n.format(
            "settings.template_encoding",
            fallback: "%@ 编码",
            template.title
        )
        return Picker(
            label,
            selection: Binding(
                get: { model.templateEncoding(for: template) },
                set: { model.setTemplateEncoding($0, for: template) }
            )
        ) {
            ForEach(TemplateEncoding.allCases, id: \.self) {
                Text($0.title).tag($0)
            }
        }
        .labelsHidden()
        .accessibilityLabel(label)
    }

}
