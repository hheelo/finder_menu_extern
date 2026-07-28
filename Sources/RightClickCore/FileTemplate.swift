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
        case .text: "TXT 文件"
        case .markdown: "Markdown 文件"
        case .python: "Python 文件"
        case .shell: "Shell 文件"
        case .html: "HTML 文件"
        case .json: "JSON 文件"
        case .csv: "CSV 文件"
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
            ""
        case .python:
            "#!/usr/bin/env python3\n\n"
        case .shell:
            "#!/bin/zsh\n\n"
        case .html:
            """
            <!doctype html>
            <html lang="zh-CN">
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
            "{\n  \n}\n"
        }
    }
}
