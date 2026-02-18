import Foundation
import Testing
@testable import WTTerminal

@MainActor @Test func sessionManager() {
    let manager = TerminalSessionManager()
    let session = manager.createSession(id: "test", title: "Test", workingDirectory: "/tmp")
    #expect(session.id == "test")
    #expect(manager.sessions.count == 1)

    // Same ID returns existing session
    let same = manager.createSession(id: "test", title: "Test 2", workingDirectory: "/tmp")
    #expect(same.id == session.id)
    #expect(manager.sessions.count == 1)

    manager.removeSession(id: "test")
    #expect(manager.sessions.count == 0)
}

// MARK: - Kitty keyboard protocol filter tests

@MainActor @Test func filterStripsPopKeyboardMode() {
    // CSI < u  (pop keyboard mode, no params)
    let input: [UInt8] = [0x1b, 0x5b, 0x3c, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered.isEmpty)
}

@MainActor @Test func filterStripsPopKeyboardModeWithParams() {
    // CSI < 1 u  (pop keyboard mode with param)
    let input: [UInt8] = [0x1b, 0x5b, 0x3c, 0x31, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered.isEmpty)
}

@MainActor @Test func filterStripsPushKeyboardMode() {
    // CSI > 1 u  (push keyboard mode)
    let input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x31, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered.isEmpty)
}

@MainActor @Test func filterStripsQueryKeyboardMode() {
    // CSI ? u  (query keyboard mode)
    let input: [UInt8] = [0x1b, 0x5b, 0x3f, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered.isEmpty)
}

@MainActor @Test func filterPreservesStandardCursorRestore() {
    // CSI u  (standard cursor restore — no private prefix)
    let input: [UInt8] = [0x1b, 0x5b, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered == input)
}

@MainActor @Test func filterPreservesSurroundingData() {
    // "AB" + CSI < u + "CD"
    let input: [UInt8] = [0x41, 0x42, 0x1b, 0x5b, 0x3c, 0x75, 0x43, 0x44]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered == [0x41, 0x42, 0x43, 0x44]) // "ABCD"
}

@MainActor @Test func filterHandlesMultipleSequences() {
    // CSI > 3 u + "hello" + CSI < u
    var input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x33, 0x75]  // CSI > 3 u
    input += Array("hello".utf8)
    input += [0x1b, 0x5b, 0x3c, 0x75]  // CSI < u
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered == Array("hello".utf8))
}

@MainActor @Test func filterPassthroughNonKittyEscapes() {
    // CSI H  (cursor home — should pass through)
    let input: [UInt8] = [0x1b, 0x5b, 0x48]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered == input)
}

@MainActor @Test func filterHandlesParamsWithSemicolons() {
    // CSI > 1;2 u  (push with flags)
    let input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x31, 0x3b, 0x32, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered.isEmpty)
}

// MARK: - Kitty command extraction tests

@MainActor @Test func filterExtractsPushCommand() {
    // CSI > 1 u → push(level: 1)
    let input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x31, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.commands == [.push(level: 1)])
}

@MainActor @Test func filterExtractsPushWithZeroLevel() {
    // CSI > u → push(level: 0)
    let input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.commands == [.push(level: 0)])
}

@MainActor @Test func filterExtractsPushWithFlags() {
    // CSI > 3;1 u → push(level: 3), first param only
    let input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x33, 0x3b, 0x31, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.commands == [.push(level: 3)])
}

@MainActor @Test func filterExtractsPopDefaultCount() {
    // CSI < u → pop(count: 1) — no param defaults to 1
    let input: [UInt8] = [0x1b, 0x5b, 0x3c, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.commands == [.pop(count: 1)])
}

@MainActor @Test func filterExtractsPopWithCount() {
    // CSI < 3 u → pop(count: 3)
    let input: [UInt8] = [0x1b, 0x5b, 0x3c, 0x33, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.commands == [.pop(count: 3)])
}

@MainActor @Test func filterExtractsQueryCommand() {
    // CSI ? u → query
    let input: [UInt8] = [0x1b, 0x5b, 0x3f, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.commands == [.query])
}

@MainActor @Test func filterExtractsMultipleCommandsInOneSlice() {
    // CSI > 1 u + "AB" + CSI < u → [push(1), pop(1)]
    var input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x31, 0x75]  // push 1
    input += [0x41, 0x42]  // "AB"
    input += [0x1b, 0x5b, 0x3c, 0x75]  // pop
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered == [0x41, 0x42])
    #expect(result.commands == [.push(level: 1), .pop(count: 1)])
}

@MainActor @Test func filterNoCommandsForPlainData() {
    let input: [UInt8] = Array("hello world".utf8)
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.filtered == input)
    #expect(result.commands.isEmpty)
}

// MARK: - Theme tests

@Test func defaultThemeIsDracula() {
    #expect(TerminalThemes.defaultTheme.id == "dracula")
}

@Test func builtInThemeIdsAreUnique() {
    let ids = TerminalThemes.builtInThemes.map(\.id)
    #expect(Set(ids).count == ids.count)
}

@Test func builtInThemeCount() {
    #expect(TerminalThemes.builtInThemes.count == 14)
}

@Test func themeForIdFallsBackToDefault() {
    let theme = TerminalThemes.theme(forId: "nonexistent-id")
    #expect(theme.id == TerminalThemes.defaultTheme.id)
}

// MARK: - ITermColorsParser tests

@Test func parseValidITermColors() throws {
    let plist = makeITermColorsPlist()
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let theme = try ITermColorsParser.parse(data: data, name: "Test Theme")

    #expect(theme.id == "custom-test-theme")
    #expect(theme.name == "Test Theme")
    #expect(theme.foreground == ThemeColor(255, 255, 255))
    #expect(theme.background == ThemeColor(0, 0, 0))
    #expect(theme.cursor == ThemeColor(128, 128, 128))
    #expect(theme.selection == ThemeColor(64, 64, 64))
    #expect(theme.ansiColors.count == 16)
}

@Test func parseMissingColorKeyThrows() throws {
    var plist = makeITermColorsPlist()
    plist.removeValue(forKey: "Cursor Color")
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

    #expect(throws: ITermColorsParser.ParseError.self) {
        try ITermColorsParser.parse(data: data, name: "Bad Theme")
    }
}

@Test func parseInvalidDataThrows() {
    let data = Data("not a plist".utf8)

    #expect(throws: ITermColorsParser.ParseError.self) {
        try ITermColorsParser.parse(data: data, name: "Invalid")
    }
}

@Test func parseCustomIdPrefixing() throws {
    let plist = makeITermColorsPlist()
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let theme = try ITermColorsParser.parse(data: data, name: "My Cool Theme!")

    #expect(theme.id.hasPrefix("custom-"))
    #expect(theme.id == "custom-my-cool-theme")
}

// MARK: - Test helpers

private func makeITermColorsPlist() -> [String: Any] {
    func colorEntry(_ r: Double, _ g: Double, _ b: Double) -> [String: Any] {
        [
            "Red Component": r,
            "Green Component": g,
            "Blue Component": b,
            "Color Space": "sRGB",
        ]
    }

    var plist: [String: Any] = [
        "Foreground Color": colorEntry(1.0, 1.0, 1.0),
        "Background Color": colorEntry(0.0, 0.0, 0.0),
        "Cursor Color": colorEntry(0.5, 0.5, 0.5),
        "Selection Color": colorEntry(0.25, 0.25, 0.25),
    ]

    for i in 0..<16 {
        let value = Double(i) / 15.0
        plist["Ansi \(i) Color"] = colorEntry(value, value, value)
    }

    return plist
}
