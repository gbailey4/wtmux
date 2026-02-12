import Testing
@testable import WTTerminal

@Test func sessionManager() {
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
