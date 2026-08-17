import Testing
@testable import RightClickCore

struct RightClickActionTests {
    @Test
    func publishedMenuTagsRemainStable() {
        let expected: [String: Int] = [
            "copyPath": 1,
            "copyFilename": 2,
            "openInVSCode": 3,
            "openInCodex": 4,
            "openInTerminal": 5,
            "runCodexCLI": 6,
            "runClaudeCode": 7,
            "createFile(text)": 8,
            "createFile(markdown)": 9,
            "createFile(python)": 10,
            "createFile(shell)": 11,
            "createFile(html)": 12,
            "createFile(json)": 13,
            "createFile(csv)": 14,
            "copyFileURL": 15,
            "copyShellPath": 16,
            "copyParentPath": 17,
            "openInCursor": 18,
            "openInZed": 19,
            "openInSublimeText": 20,
            "openInXcode": 21,
            "openInJetBrains": 22,
            "openInDefaultApplication": 23,
            "createFolder": 24,
            "createFileFromClipboard": 25,
            "copyRelativePath": 26
        ]
        let actual = Dictionary(uniqueKeysWithValues:
            RightClickAction.allMenuActions.map {
                ($0.configurationID, $0.menuTag)
            }
        )

        #expect(RightClickAction.allMenuActions.count == expected.count)
        #expect(actual == expected)
        for (configurationID, tag) in expected {
            #expect(RightClickAction(menuTag: tag)?.configurationID == configurationID)
            #expect(RightClickAction(configurationID: configurationID)?.menuTag == tag)
        }
    }
}
