import Foundation
import WTTransport

public enum AnalysisProgress: Sendable {
    case gatheringContext
    case analyzing
    case complete(ProjectAnalysis)
    case failed(LLMError)
}

public actor AnalysisService {
    private let provider: any LLMProvider
    private let transport: any CommandTransport

    private static let maxRetries = 2
    private static let requestTimeout: TimeInterval = 60

    public init(provider: any LLMProvider, transport: any CommandTransport) {
        self.provider = provider
        self.transport = transport
    }

    public func analyze(repoPath: String) -> AsyncStream<AnalysisProgress> {
        AsyncStream { continuation in
            Task {
                await self.runAnalysis(repoPath: repoPath, continuation: continuation)
            }
        }
    }

    private func runAnalysis(
        repoPath: String,
        continuation: AsyncStream<AnalysisProgress>.Continuation
    ) async {
        continuation.yield(.gatheringContext)

        let context: ProjectContext
        do {
            let gatherer = ProjectContextGatherer(transport: transport)
            context = try await gatherer.gather(repoPath: repoPath)
        } catch {
            continuation.yield(.failed(.networkError(underlying: "Failed to gather project context: \(error.localizedDescription)")))
            continuation.finish()
            return
        }

        continuation.yield(.analyzing)

        let userMessage = PromptBuilder.buildUserMessage(from: context)
        let tool = PromptBuilder.analysisToolDefinition()

        var lastError: LLMError?
        for attempt in 0...Self.maxRetries {
            if attempt > 0 {
                let delay = pow(2.0, Double(attempt - 1))
                try? await Task.sleep(for: .seconds(delay))
            }

            do {
                let result = try await provider.analyzeWithTool(
                    systemPrompt: PromptBuilder.systemPrompt,
                    userMessage: userMessage,
                    tool: tool,
                    timeout: Self.requestTimeout
                )

                let analysis = try JSONDecoder().decode(ProjectAnalysis.self, from: result.arguments)
                continuation.yield(.complete(analysis))
                continuation.finish()
                return
            } catch let error as LLMError {
                lastError = error
                switch error {
                case .rateLimited:
                    continue
                case .invalidResponse where attempt < Self.maxRetries:
                    continue
                default:
                    break
                }
                break
            } catch {
                lastError = .invalidResponse(detail: "Decoding failed: \(error.localizedDescription)")
                if attempt < Self.maxRetries {
                    continue
                }
                break
            }
        }

        continuation.yield(.failed(lastError ?? .invalidResponse(detail: "Unknown error")))
        continuation.finish()
    }
}
