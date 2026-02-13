import Testing
@testable import WTProcess

@Test func processManagerPortAllocation() async {
    let manager = ProcessManager()

    let proc1 = await manager.startProcess(id: "p1", command: "echo", directory: "/tmp")
    #expect(proc1.port == 3100)

    let proc2 = await manager.startProcess(id: "p2", command: "echo", directory: "/tmp")
    #expect(proc2.port == 3101)

    // Release first port
    await manager.stopProcess(id: "p1")

    // Released port should be re-used
    let proc3 = await manager.startProcess(id: "p3", command: "echo", directory: "/tmp")
    #expect(proc3.port == 3100)
}
