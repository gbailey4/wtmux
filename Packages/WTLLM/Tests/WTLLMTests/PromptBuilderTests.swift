import Testing
import Foundation
@testable import WTLLM

@Suite("PromptBuilder")
struct PromptBuilderTests {

    @Test("User message contains directory tree")
    func userMessageContainsTree() {
        let context = ProjectContext(
            directoryTree: "./src\n./package.json",
            fileContents: []
        )
        let message = PromptBuilder.buildUserMessage(from: context)

        #expect(message.contains("## Directory Tree"))
        #expect(message.contains("./src"))
        #expect(message.contains("./package.json"))
    }

    @Test("User message contains file contents")
    func userMessageContainsFiles() {
        let context = ProjectContext(
            directoryTree: ".",
            fileContents: [
                (path: "package.json", content: "{\"name\": \"test\"}")
            ]
        )
        let message = PromptBuilder.buildUserMessage(from: context)

        #expect(message.contains("## Config Files"))
        #expect(message.contains("### package.json"))
        #expect(message.contains("{\"name\": \"test\"}"))
    }

    @Test("User message omits Config Files section when no files")
    func userMessageOmitsEmptyFiles() {
        let context = ProjectContext(
            directoryTree: ".",
            fileContents: []
        )
        let message = PromptBuilder.buildUserMessage(from: context)

        #expect(!message.contains("## Config Files"))
    }

    @Test("Tool definition has valid JSON schema")
    func toolDefinitionHasValidSchema() throws {
        let tool = PromptBuilder.analysisToolDefinition()

        #expect(tool.name == "report_project_analysis")

        let schema = try JSONSerialization.jsonObject(with: tool.inputSchemaJSON) as? [String: Any]
        #expect(schema != nil)
        #expect(schema?["type"] as? String == "object")

        let properties = schema?["properties"] as? [String: Any]
        #expect(properties != nil)
        #expect(properties?["filesToCopy"] != nil)
        #expect(properties?["setupCommands"] != nil)
        #expect(properties?["runConfigurations"] != nil)

        let required = schema?["required"] as? [String]
        #expect(required?.contains("filesToCopy") == true)
        #expect(required?.contains("setupCommands") == true)
        #expect(required?.contains("runConfigurations") == true)
    }

    @Test("System prompt is non-empty")
    func systemPromptExists() {
        #expect(!PromptBuilder.systemPrompt.isEmpty)
    }
}
