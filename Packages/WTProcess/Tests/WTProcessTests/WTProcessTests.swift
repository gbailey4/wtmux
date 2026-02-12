import Testing
@testable import WTProcess

@Test func portAllocator() {
    let allocator = PortAllocator()
    let port1 = allocator.allocate()
    let port2 = allocator.allocate()
    #expect(port1 == 3100)
    #expect(port2 == 3101)
    allocator.release(port1)
    let port3 = allocator.allocate()
    #expect(port3 == 3100)
}
