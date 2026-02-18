import Testing
import Foundation
@testable import WTLLM

@Suite("ProjectAnalysis Decoding")
struct ProjectAnalysisTests {

    @Test("Decodes valid JSON with all fields")
    func decodesFullJSON() throws {
        let json = """
        {
            "filesToCopy": [".env", ".env.local"],
            "setupCommands": ["pnpm install"],
            "runConfigurations": [
                {
                    "name": "Dev Server",
                    "command": "pnpm dev",
                    "port": 3000,
                    "autoStart": true
                }
            ],
            "terminalStartCommand": "nvm use",
            "projectType": "Next.js",
            "notes": "Monorepo with turborepo"
        }
        """
        let data = Data(json.utf8)
        let analysis = try JSONDecoder().decode(ProjectAnalysis.self, from: data)

        #expect(analysis.filesToCopy == [".env", ".env.local"])
        #expect(analysis.setupCommands == ["pnpm install"])
        #expect(analysis.runConfigurations.count == 1)
        #expect(analysis.runConfigurations[0].name == "Dev Server")
        #expect(analysis.runConfigurations[0].command == "pnpm dev")
        #expect(analysis.runConfigurations[0].port == 3000)
        #expect(analysis.runConfigurations[0].autoStart == true)
        #expect(analysis.terminalStartCommand == "nvm use")
        #expect(analysis.projectType == "Next.js")
        #expect(analysis.notes == "Monorepo with turborepo")
    }

    @Test("Decodes JSON with only required fields")
    func decodesMinimalJSON() throws {
        let json = """
        {
            "filesToCopy": [],
            "setupCommands": [],
            "runConfigurations": []
        }
        """
        let data = Data(json.utf8)
        let analysis = try JSONDecoder().decode(ProjectAnalysis.self, from: data)

        #expect(analysis.filesToCopy.isEmpty)
        #expect(analysis.setupCommands.isEmpty)
        #expect(analysis.runConfigurations.isEmpty)
        #expect(analysis.terminalStartCommand == nil)
        #expect(analysis.projectType == nil)
        #expect(analysis.notes == nil)
    }

    @Test("RunConfigSuggestion without optional port")
    func decodesRunConfigWithoutPort() throws {
        let json = """
        {
            "name": "Build",
            "command": "npm run build",
            "autoStart": false
        }
        """
        let data = Data(json.utf8)
        let rc = try JSONDecoder().decode(ProjectAnalysis.RunConfigSuggestion.self, from: data)

        #expect(rc.name == "Build")
        #expect(rc.command == "npm run build")
        #expect(rc.port == nil)
        #expect(rc.autoStart == false)
    }

    @Test("Rejects invalid JSON")
    func rejectsInvalidJSON() {
        let json = """
        { "invalid": true }
        """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProjectAnalysis.self, from: data)
        }
    }

    @Test("Round-trips through encode/decode")
    func roundTrips() throws {
        let original = ProjectAnalysis(
            filesToCopy: [".env"],
            setupCommands: ["make setup"],
            runConfigurations: [
                .init(name: "Server", command: "make serve", port: 8080, autoStart: true)
            ],
            terminalStartCommand: "source venv/bin/activate",
            projectType: "Django",
            notes: "Python backend"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectAnalysis.self, from: data)

        #expect(decoded == original)
    }
}
