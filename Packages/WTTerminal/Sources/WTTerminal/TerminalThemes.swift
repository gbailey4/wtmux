public enum TerminalThemes {
    // MARK: - macOS Terminal.app ANSI palette

    /// Standard ANSI colors matching macOS Terminal.app
    private static let terminalAppAnsi: [ThemeColor] = [
        // Normal colors (0-7)
        ThemeColor(0x00, 0x00, 0x00), // Black
        ThemeColor(0x99, 0x00, 0x00), // Red
        ThemeColor(0x00, 0xA6, 0x00), // Green
        ThemeColor(0x99, 0x9A, 0x00), // Yellow
        ThemeColor(0x00, 0x00, 0xB2), // Blue
        ThemeColor(0xB2, 0x00, 0xB2), // Magenta
        ThemeColor(0x00, 0xA6, 0xB2), // Cyan
        ThemeColor(0xBF, 0xBF, 0xBF), // White
        // Bright colors (8-15)
        ThemeColor(0x66, 0x66, 0x66), // Bright Black
        ThemeColor(0xE5, 0x00, 0x00), // Bright Red
        ThemeColor(0x00, 0xD9, 0x00), // Bright Green
        ThemeColor(0xE5, 0xE5, 0x00), // Bright Yellow
        ThemeColor(0x00, 0x00, 0xFF), // Bright Blue
        ThemeColor(0xE5, 0x00, 0xE5), // Bright Magenta
        ThemeColor(0x00, 0xE5, 0xE5), // Bright Cyan
        ThemeColor(0xE5, 0xE5, 0xE5), // Bright White
    ]

    // MARK: - Built-in Themes

    public static let proDark = TerminalTheme(
        id: "pro-dark",
        name: "Pro Dark",
        foreground: ThemeColor(0xE6, 0xE6, 0xE6),
        background: ThemeColor(0x1E, 0x1E, 0x1E),
        cursor: ThemeColor(0x4D, 0x9E, 0xF7),
        selection: ThemeColor(0x3A, 0x5A, 0x80),
        ansiColors: terminalAppAnsi
    )

    public static let solarizedDark = TerminalTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        foreground: ThemeColor(0x83, 0x94, 0x96), // base0
        background: ThemeColor(0x00, 0x2B, 0x36), // base03
        cursor: ThemeColor(0x93, 0xA1, 0xA1),     // base1
        selection: ThemeColor(0x07, 0x36, 0x42),   // base02
        ansiColors: [
            // Normal
            ThemeColor(0x07, 0x36, 0x42), // base02
            ThemeColor(0xDC, 0x32, 0x2F), // red
            ThemeColor(0x85, 0x99, 0x00), // green
            ThemeColor(0xB5, 0x89, 0x00), // yellow
            ThemeColor(0x26, 0x8B, 0xD2), // blue
            ThemeColor(0xD3, 0x36, 0x82), // magenta
            ThemeColor(0x2A, 0xA1, 0x98), // cyan
            ThemeColor(0xEE, 0xE8, 0xD5), // base2
            // Bright
            ThemeColor(0x00, 0x2B, 0x36), // base03
            ThemeColor(0xCB, 0x4B, 0x16), // orange
            ThemeColor(0x58, 0x6E, 0x75), // base01
            ThemeColor(0x65, 0x7B, 0x83), // base00
            ThemeColor(0x83, 0x94, 0x96), // base0
            ThemeColor(0x6C, 0x71, 0xC4), // violet
            ThemeColor(0x93, 0xA1, 0xA1), // base1
            ThemeColor(0xFD, 0xF6, 0xE3), // base3
        ]
    )

    public static let tokyoNight = TerminalTheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        foreground: ThemeColor(0xC0, 0xCA, 0xF5),
        background: ThemeColor(0x1A, 0x1B, 0x26),
        cursor: ThemeColor(0xC0, 0xCA, 0xF5),
        selection: ThemeColor(0x28, 0x3B, 0x8A),
        ansiColors: [
            // Normal
            ThemeColor(0x15, 0x16, 0x1E), // Black
            ThemeColor(0xF7, 0x76, 0x8E), // Red
            ThemeColor(0x9E, 0xCE, 0x6A), // Green
            ThemeColor(0xE0, 0xAF, 0x68), // Yellow
            ThemeColor(0x7A, 0xA2, 0xF7), // Blue
            ThemeColor(0xBB, 0x9A, 0xF7), // Magenta
            ThemeColor(0x7D, 0xCF, 0xFF), // Cyan
            ThemeColor(0xA9, 0xB1, 0xD6), // White
            // Bright
            ThemeColor(0x41, 0x48, 0x68), // Bright Black
            ThemeColor(0xF7, 0x76, 0x8E), // Bright Red
            ThemeColor(0x9E, 0xCE, 0x6A), // Bright Green
            ThemeColor(0xE0, 0xAF, 0x68), // Bright Yellow
            ThemeColor(0x7A, 0xA2, 0xF7), // Bright Blue
            ThemeColor(0xBB, 0x9A, 0xF7), // Bright Magenta
            ThemeColor(0x7D, 0xCF, 0xFF), // Bright Cyan
            ThemeColor(0xC0, 0xCA, 0xF5), // Bright White
        ]
    )

    public static let dracula = TerminalTheme(
        id: "dracula",
        name: "Dracula",
        foreground: ThemeColor(0xF8, 0xF8, 0xF2),
        background: ThemeColor(0x28, 0x2A, 0x36),
        cursor: ThemeColor(0xF8, 0xF8, 0xF2),
        selection: ThemeColor(0x44, 0x47, 0x5A),
        ansiColors: [
            // Normal
            ThemeColor(0x21, 0x22, 0x2C), // Black
            ThemeColor(0xFF, 0x55, 0x55), // Red
            ThemeColor(0x50, 0xFA, 0x7B), // Green
            ThemeColor(0xF1, 0xFA, 0x8C), // Yellow
            ThemeColor(0xBD, 0x93, 0xF9), // Blue
            ThemeColor(0xFF, 0x79, 0xC6), // Magenta
            ThemeColor(0x8B, 0xE9, 0xFD), // Cyan
            ThemeColor(0xF8, 0xF8, 0xF2), // White
            // Bright
            ThemeColor(0x62, 0x72, 0xA4), // Bright Black
            ThemeColor(0xFF, 0x6E, 0x6E), // Bright Red
            ThemeColor(0x69, 0xFF, 0x94), // Bright Green
            ThemeColor(0xFF, 0xFF, 0xA5), // Bright Yellow
            ThemeColor(0xD6, 0xAC, 0xFF), // Bright Blue
            ThemeColor(0xFF, 0x92, 0xDF), // Bright Magenta
            ThemeColor(0xA4, 0xFF, 0xFF), // Bright Cyan
            ThemeColor(0xFF, 0xFF, 0xFF), // Bright White
        ]
    )

    public static let classicLight = TerminalTheme(
        id: "classic-light",
        name: "Classic Light",
        foreground: ThemeColor(0x1E, 0x1E, 0x1E),
        background: ThemeColor(0xFF, 0xFF, 0xFF),
        cursor: ThemeColor(0x1E, 0x1E, 0x1E),
        selection: ThemeColor(0xB4, 0xD5, 0xFE),
        ansiColors: terminalAppAnsi
    )

    // MARK: - Catalog

    public static let allThemes: [TerminalTheme] = [
        proDark,
        dracula,
        solarizedDark,
        tokyoNight,
        classicLight,
    ]

    public static let defaultTheme = proDark

    public static func theme(forId id: String) -> TerminalTheme {
        allThemes.first { $0.id == id } ?? defaultTheme
    }
}
