import Testing
@testable import WTCore

@Test func projectCreation() {
    let project = Project(name: "Test", repoPath: "/tmp/test")
    #expect(project.name == "Test")
    #expect(project.isRemote == false)
}
