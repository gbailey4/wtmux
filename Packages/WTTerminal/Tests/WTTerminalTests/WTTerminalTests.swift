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
    #expect(result.isEmpty)
}

@MainActor @Test func filterStripsPopKeyboardModeWithParams() {
    // CSI < 1 u  (pop keyboard mode with param)
    let input: [UInt8] = [0x1b, 0x5b, 0x3c, 0x31, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.isEmpty)
}

@MainActor @Test func filterStripsPushKeyboardMode() {
    // CSI > 1 u  (push keyboard mode)
    let input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x31, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.isEmpty)
}

@MainActor @Test func filterStripsQueryKeyboardMode() {
    // CSI ? u  (query keyboard mode)
    let input: [UInt8] = [0x1b, 0x5b, 0x3f, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.isEmpty)
}

@MainActor @Test func filterPreservesStandardCursorRestore() {
    // CSI u  (standard cursor restore — no private prefix)
    let input: [UInt8] = [0x1b, 0x5b, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result == input)
}

@MainActor @Test func filterPreservesSurroundingData() {
    // "AB" + CSI < u + "CD"
    let input: [UInt8] = [0x41, 0x42, 0x1b, 0x5b, 0x3c, 0x75, 0x43, 0x44]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result == [0x41, 0x42, 0x43, 0x44]) // "ABCD"
}

@MainActor @Test func filterHandlesMultipleSequences() {
    // CSI > 3 u + "hello" + CSI < u
    var input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x33, 0x75]  // CSI > 3 u
    input += Array("hello".utf8)
    input += [0x1b, 0x5b, 0x3c, 0x75]  // CSI < u
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result == Array("hello".utf8))
}

@MainActor @Test func filterPassthroughNonKittyEscapes() {
    // CSI H  (cursor home — should pass through)
    let input: [UInt8] = [0x1b, 0x5b, 0x48]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result == input)
}

@MainActor @Test func filterHandlesParamsWithSemicolons() {
    // CSI > 1;2 u  (push with flags)
    let input: [UInt8] = [0x1b, 0x5b, 0x3e, 0x31, 0x3b, 0x32, 0x75]
    let result = DeferredStartTerminalView.filterKittyKeyboardSequences(input[...])
    #expect(result.isEmpty)
}
