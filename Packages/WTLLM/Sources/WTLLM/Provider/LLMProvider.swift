import Foundation

// MARK: - Provider Kind

public enum LLMProviderKind: String, Codable, Sendable, CaseIterable {
    case claude
}

// MARK: - Errors

public enum LLMError: Error, Sendable {
    case noAPIKey
    case networkError(underlying: String)
    case rateLimited(retryAfter: TimeInterval?)
    case invalidResponse(detail: String)
    case timeout
}

// MARK: - Tool Types

public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchemaJSON: Data

    public init(name: String, description: String, inputSchemaJSON: Data) {
        self.name = name
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
    }
}

public struct LLMToolCallResult: Sendable {
    public let toolName: String
    public let arguments: Data

    public init(toolName: String, arguments: Data) {
        self.toolName = toolName
        self.arguments = arguments
    }
}

// MARK: - Provider Protocol

public protocol LLMProvider: Sendable {
    func analyzeWithTool(
        systemPrompt: String,
        userMessage: String,
        tool: ToolDefinition,
        timeout: TimeInterval
    ) async throws -> LLMToolCallResult
}
