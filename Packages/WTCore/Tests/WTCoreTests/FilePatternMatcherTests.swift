import Testing
import Foundation
@testable import WTCore

@Suite("FilePatternMatcher")
struct FilePatternMatcherTests {
    private let fm = FileManager.default

    private func makeTempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "FilePatternMatcherTests-\(UUID().uuidString)"
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createFile(_ relativePath: String, in dir: String) throws {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: nil)
    }

    private func createDir(_ relativePath: String, in dir: String) throws {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(relativePath)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @Test("Glob pattern matches .env* files")
    func globPatternMatchesEnvFiles() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        try createFile(".env", in: dir)
        try createFile(".env.local", in: dir)
        try createFile(".env.production", in: dir)
        try createFile("README.md", in: dir)

        let matches = FilePatternMatcher.match(patterns: [".env*"], in: dir)
        #expect(matches.count == 3)
        #expect(matches.contains(".env"))
        #expect(matches.contains(".env.local"))
        #expect(matches.contains(".env.production"))
        #expect(!matches.contains("README.md"))
    }

    @Test("Literal file path matches existing file")
    func literalFileMatch() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        try createFile("config.json", in: dir)

        let matches = FilePatternMatcher.match(patterns: ["config.json"], in: dir)
        #expect(matches == ["config.json"])
    }

    @Test("Literal file path does not match missing file")
    func literalFileMissing() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        let matches = FilePatternMatcher.match(patterns: ["config.json"], in: dir)
        #expect(matches.isEmpty)
    }

    @Test("Directory pattern with trailing slash matches existing directory")
    func directoryPatternMatch() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        try createDir(".claude", in: dir)
        try createFile(".claude/settings.json", in: dir)

        let matches = FilePatternMatcher.match(patterns: [".claude/"], in: dir)
        #expect(matches == [".claude"])
    }

    @Test("Directory pattern does not match missing directory")
    func directoryPatternMissing() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        let matches = FilePatternMatcher.match(patterns: [".claude/"], in: dir)
        #expect(matches.isEmpty)
    }

    @Test("Multiple patterns combined")
    func multiplePatterns() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        try createFile(".env", in: dir)
        try createFile(".env.local", in: dir)
        try createDir(".claude", in: dir)
        try createFile("config.json", in: dir)

        let matches = FilePatternMatcher.match(
            patterns: [".env*", ".claude/", "config.json"],
            in: dir
        )
        #expect(matches.count == 4)
        #expect(matches.contains(".env"))
        #expect(matches.contains(".env.local"))
        #expect(matches.contains(".claude"))
        #expect(matches.contains("config.json"))
    }

    @Test("Results are sorted")
    func resultsSorted() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        try createFile(".env.production", in: dir)
        try createFile(".env", in: dir)
        try createFile(".env.local", in: dir)

        let matches = FilePatternMatcher.match(patterns: [".env*"], in: dir)
        #expect(matches == [".env", ".env.local", ".env.production"])
    }

    @Test("No duplicates when patterns overlap")
    func noDuplicates() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        try createFile(".env", in: dir)

        let matches = FilePatternMatcher.match(patterns: [".env*", ".env"], in: dir)
        #expect(matches == [".env"])
    }

    @Test("Empty patterns returns empty results")
    func emptyPatterns() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        let matches = FilePatternMatcher.match(patterns: [], in: dir)
        #expect(matches.isEmpty)
    }
}

@Suite("FilePreset")
struct FilePresetTests {

    private let fm = FileManager.default

    private func makeTempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "FilePresetTests-\(UUID().uuidString)"
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("detectPresets finds matching presets")
    func detectPresetsFindsMatches() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        // Create .env and .claude/
        fm.createFile(atPath: (dir as NSString).appendingPathComponent(".env"), contents: nil)
        try fm.createDirectory(
            atPath: (dir as NSString).appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )

        let detected = FilePreset.detectPresets(in: dir)
        #expect(detected.contains(.envFiles))
        #expect(detected.contains(.claudeCode))
        #expect(!detected.contains(.vscode))
        #expect(!detected.contains(.cursor))
    }

    @Test("detectPresets returns empty for bare directory")
    func detectPresetsEmpty() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }

        let detected = FilePreset.detectPresets(in: dir)
        #expect(detected.isEmpty)
    }

    @Test("Each preset has a non-empty displayName and pattern")
    func presetProperties() {
        for preset in FilePreset.allCases {
            #expect(!preset.displayName.isEmpty)
            #expect(!preset.pattern.isEmpty)
        }
    }
}
