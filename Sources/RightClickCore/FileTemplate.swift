import Foundation

public enum FileTemplate: String, CaseIterable, Codable, Sendable {
    case text
    case markdown
    case python
    case shell
    case html
    case json
    case csv

    public var title: String {
        switch self {
        case .text: L10n.text("template.text", fallback: "TXT 文件")
        case .markdown:
            L10n.text("template.markdown", fallback: "Markdown 文件")
        case .python: L10n.text("template.python", fallback: "Python 文件")
        case .shell: L10n.text("template.shell", fallback: "Shell 文件")
        case .html: L10n.text("template.html", fallback: "HTML 文件")
        case .json: L10n.text("template.json", fallback: "JSON 文件")
        case .csv: L10n.text("template.csv", fallback: "CSV 文件")
        }
    }

    public var preferredFilename: String {
        switch self {
        case .text: "Untitled.txt"
        case .markdown: "Untitled.md"
        case .python: "Untitled.py"
        case .shell: "Untitled.sh"
        case .html: "Untitled.html"
        case .json: "Untitled.json"
        case .csv: "Untitled.csv"
        }
    }

    public var initialContents: String {
        switch self {
        case .text, .markdown, .csv:
            return ""
        case .python:
            return "#!/usr/bin/env python3\n\n"
        case .shell:
            return "#!/bin/zsh\n\n"
        case .html:
            let languageTag = L10n.text(
                "html.language_tag",
                fallback: "zh-CN"
            )
            return """
            <!doctype html>
            <html lang="\(languageTag)">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Untitled</title>
            </head>
            <body>

            </body>
            </html>

            """
        case .json:
            return "{\n  \n}\n"
        }
    }
}
