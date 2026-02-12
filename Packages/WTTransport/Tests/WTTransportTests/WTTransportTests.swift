import Testing
@testable import WTTransport

@Test func localTransportEcho() async throws {
    let transport = LocalTransport()
    let result = try await transport.execute("echo hello")
    #expect(result.succeeded)
    #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
}
