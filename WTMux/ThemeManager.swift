import Foundation
import WTTerminal
import os.log

private let logger = Logger(subsystem: "com.wtmux", category: "ThemeManager")

@MainActor @Observable
final class ThemeManager {
    private(set) var customThemes: [TerminalTheme] = []

    var allThemes: [TerminalTheme] {
        TerminalThemes.builtInThemes + customThemes
    }

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.grahampark.wtmux")
        return dir.appendingPathComponent("custom-themes.json")
    }

    init() {
        loadCustomThemes()
    }

    func theme(forId id: String) -> TerminalTheme {
        allThemes.first { $0.id == id } ?? TerminalThemes.defaultTheme
    }

    @discardableResult
    func importITermColors(from url: URL, name: String? = nil) throws -> TerminalTheme {
        let data = try Data(contentsOf: url)
        let themeName = name ?? url.deletingPathExtension().lastPathComponent
        var theme = try ITermColorsParser.parse(data: data, name: themeName)

        // Deduplicate ID if needed
        let existingIds = Set(allThemes.map(\.id))
        if existingIds.contains(theme.id) {
            var suffix = 2
            while existingIds.contains("\(theme.id)-\(suffix)") {
                suffix += 1
            }
            theme = TerminalTheme(
                id: "\(theme.id)-\(suffix)",
                name: "\(theme.name) (\(suffix))",
                foreground: theme.foreground,
                background: theme.background,
                cursor: theme.cursor,
                selection: theme.selection,
                ansiColors: theme.ansiColors
            )
        }

        customThemes.append(theme)
        saveCustomThemes()
        return theme
    }

    func deleteCustomTheme(id: String) {
        customThemes.removeAll { $0.id == id }
        saveCustomThemes()
    }

    // MARK: - Persistence

    private func loadCustomThemes() {
        let url = storageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            customThemes = try JSONDecoder().decode([TerminalTheme].self, from: data)
        } catch {
            logger.error("Failed to load custom themes: \(error.localizedDescription)")
        }
    }

    private func saveCustomThemes() {
        let url = storageURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(customThemes)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save custom themes: \(error.localizedDescription)")
        }
    }
}
