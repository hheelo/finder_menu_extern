import AppKit
import RightClickCore
import Testing

struct MenuIconTests {
    @Test
    func everyPublishedMenuSymbolResolvesToAnImage() {
        let symbolNames = Set(
            RightClickAction.allMenuActions.map(\.systemImageName)
                + ["terminal.fill", "doc.badge.plus"]
        )

        for symbolName in symbolNames {
            #expect(
                NSImage(
                    systemSymbolName: symbolName,
                    accessibilityDescription: symbolName
                ) != nil,
                "Missing SF Symbol: \(symbolName)"
            )
        }
    }
}
