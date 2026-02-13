import Foundation

public actor ClaudeProvider: LLMProvider {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    public init(apiKey: String, model: String = "claude-sonnet-4-5-20250929") {
        self.apiKey = apiKey
        self.model = model
        self.session = URLSession(configuration: .default)
    }

    public func analyzeWithTool(
        systemPrompt: String,
        userMessage: String,
        tool: ToolDefinition,
        timeout: TimeInterval
    ) async throws -> LLMToolCallResult {
        let request = try buildRequest(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            tool: tool,
            timeout: timeout
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMError.timeout
        } catch {
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(underlying: "Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseToolCall(from: data)
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap(TimeInterval.init)
            throw LLMError.rateLimited(retryAfter: retryAfter)
        case 401:
            throw LLMError.noAPIKey
        default:
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.invalidResponse(detail: "HTTP \(httpResponse.statusCode): \(body)")
        }
    }

    // MARK: - Request Building

    private func buildRequest(
        systemPrompt: String,
        userMessage: String,
        tool: ToolDefinition,
        timeout: TimeInterval
    ) throws -> URLRequest {
        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let inputSchema = try JSONSerialization.jsonObject(with: tool.inputSchemaJSON)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ],
            "tools": [
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": inputSchema
                ]
            ],
            "tool_choice": [
                "type": "tool",
                "name": tool.name
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Parsing

    private func parseToolCall(from data: Data) throws -> LLMToolCallResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw LLMError.invalidResponse(detail: "Missing content array")
        }

        guard let toolUseBlock = content.first(where: { ($0["type"] as? String) == "tool_use" }) else {
            throw LLMError.invalidResponse(detail: "No tool_use block in response")
        }

        guard let toolName = toolUseBlock["name"] as? String,
              let input = toolUseBlock["input"] else {
            throw LLMError.invalidResponse(detail: "Malformed tool_use block")
        }

        let inputData = try JSONSerialization.data(withJSONObject: input)
        return LLMToolCallResult(toolName: toolName, arguments: inputData)
    }
}
