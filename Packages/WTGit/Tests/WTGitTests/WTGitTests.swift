import Testing
@testable import WTGit

@Test func gitWorktreeInfoInit() {
    let info = GitWorktreeInfo(path: "/tmp/test", branch: "main", isBare: false)
    #expect(info.path == "/tmp/test")
    #expect(info.branch == "main")
}
