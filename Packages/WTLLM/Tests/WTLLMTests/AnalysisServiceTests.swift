import Testing
import Foundation
@testable import WTLLM
import WTTransport

// MARK: - Mock Provider

actor MockLLMProvider: LLMProvider {
    var callCount = 0
    var result: Result<LLMToolCallResult, LLMError>

    init(result: Result<LLMToolCallResult, LLMError>) {
        self.result = result
    }

    func analyzeWithTool(
        systemPrompt: String,
        userMessage: String,
        tool: ToolDefinition,
        timeout: TimeInterval
    ) async throws -> LLMToolCallResult {
        callCount += 1
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

// MARK: - Mock Transport

actor MockTransport: CommandTransport {
    let treeOutput: String
    let fileContents: [String: String]

    init(treeOutput: String = ".\n./package.json", fileContents: [String: String] = [:]) {
        self.treeOutput = treeOutput
        self.fileContents = fileContents
    }

    func execute(_ command: String, in directory: String?) async throws -> CommandResult {
        CommandResult(exitCode: 0, stdout: command, stderr: "")
    }

    func execute(_ arguments: [String], in directory: String?) async throws -> CommandResult {
        if arguments.first == "find" {
            return CommandResult(exitCode: 0, stdout: treeOutput, stderr: "")
        }
        if arguments.first == "head", let path = arguments.last, let content = fileContents[path] {
            return CommandResult(exitCode: 0, stdout: content, stderr: "")
        }
        return CommandResult(exitCode: 1, stdout: "", stderr: "not found")
    }
}

// MARK: - Tests

@Suite("AnalysisService")
struct AnalysisServiceTests {

    private func makeSuccessfulResult() throws -> LLMToolCallResult {
        let analysis = ProjectAnalysis(
            filesToCopy: [".env"],
            setupCommands: ["npm install"],
            runConfigurations: [
                .init(name: "Dev", command: "npm run dev", port: 3000, autoStart: true)
            ],
            projectType: "Node.js"
        )
        let data = try JSONEncoder().encode(analysis)
        return LLMToolCallResult(toolName: "report_project_analysis", arguments: data)
    }

    @Test("Successful analysis returns complete progress")
    func successfulAnalysis() async throws {
        let toolResult = try makeSuccessfulResult()
        let provider = MockLLMProvider(result: .success(toolResult))
        let transport = MockTransport()
        let service = AnalysisService(provider: provider, transport: transport)

        var progressSteps: [String] = []
        var finalAnalysis: ProjectAnalysis?

        for await progress in await service.analyze(repoPath: "/tmp/test") {
            switch progress {
            case .gatheringContext:
                progressSteps.append("gathering")
            case .analyzing:
                progressSteps.append("analyzing")
            case .complete(let analysis):
                progressSteps.append("complete")
                finalAnalysis = analysis
            case .failed:
                progressSteps.append("failed")
            }
        }

        #expect(progressSteps.contains("gathering"))
        #expect(progressSteps.contains("analyzing"))
        #expect(progressSteps.contains("complete"))
        #expect(finalAnalysis?.projectType == "Node.js")
        #expect(finalAnalysis?.setupCommands == ["npm install"])
    }

    @Test("Network error yields failed progress")
    func networkErrorFails() async throws {
        let provider = MockLLMProvider(result: .failure(.networkError(underlying: "Connection refused")))
        let transport = MockTransport()
        let service = AnalysisService(provider: provider, transport: transport)

        var gotFailed = false

        for await progress in await service.analyze(repoPath: "/tmp/test") {
            if case .failed = progress {
                gotFailed = true
            }
        }

        #expect(gotFailed)
    }

    @Test("Timeout error yields failed progress")
    func timeoutFails() async throws {
        let provider = MockLLMProvider(result: .failure(.timeout))
        let transport = MockTransport()
        let service = AnalysisService(provider: provider, transport: transport)

        var gotFailed = false

        for await progress in await service.analyze(repoPath: "/tmp/test") {
            if case .failed = progress {
                gotFailed = true
            }
        }

        #expect(gotFailed)
    }
}
