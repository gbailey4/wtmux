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

    public static let gruvboxDark = TerminalTheme(
        id: "gruvbox-dark",
        name: "Gruvbox Dark",
        foreground: ThemeColor(0xEB, 0xDB, 0xB2),
        background: ThemeColor(0x28, 0x28, 0x28),
        cursor: ThemeColor(0xEB, 0xDB, 0xB2),
        selection: ThemeColor(0x50, 0x49, 0x45),
        ansiColors: [
            ThemeColor(0x28, 0x28, 0x28), // Black
            ThemeColor(0xCC, 0x24, 0x1D), // Red
            ThemeColor(0x98, 0x97, 0x1A), // Green
            ThemeColor(0xD7, 0x99, 0x21), // Yellow
            ThemeColor(0x45, 0x85, 0x88), // Blue
            ThemeColor(0xB1, 0x62, 0x86), // Magenta
            ThemeColor(0x68, 0x9D, 0x6A), // Cyan
            ThemeColor(0xA8, 0x99, 0x84), // White
            ThemeColor(0x92, 0x83, 0x74), // Bright Black
            ThemeColor(0xFB, 0x49, 0x34), // Bright Red
            ThemeColor(0xB8, 0xBB, 0x26), // Bright Green
            ThemeColor(0xFA, 0xBD, 0x2F), // Bright Yellow
            ThemeColor(0x83, 0xA5, 0x98), // Bright Blue
            ThemeColor(0xD3, 0x86, 0x9B), // Bright Magenta
            ThemeColor(0x8E, 0xC0, 0x7C), // Bright Cyan
            ThemeColor(0xEB, 0xDB, 0xB2), // Bright White
        ]
    )

    public static let nord = TerminalTheme(
        id: "nord",
        name: "Nord",
        foreground: ThemeColor(0xD8, 0xDE, 0xE9),
        background: ThemeColor(0x2E, 0x34, 0x40),
        cursor: ThemeColor(0xD8, 0xDE, 0xE9),
        selection: ThemeColor(0x43, 0x4C, 0x5E),
        ansiColors: [
            ThemeColor(0x3B, 0x42, 0x52), // Black
            ThemeColor(0xBF, 0x61, 0x6A), // Red
            ThemeColor(0xA3, 0xBE, 0x8C), // Green
            ThemeColor(0xEB, 0xCB, 0x8B), // Yellow
            ThemeColor(0x81, 0xA1, 0xC1), // Blue
            ThemeColor(0xB4, 0x8E, 0xAD), // Magenta
            ThemeColor(0x88, 0xC0, 0xD0), // Cyan
            ThemeColor(0xE5, 0xE9, 0xF0), // White
            ThemeColor(0x4C, 0x56, 0x6A), // Bright Black
            ThemeColor(0xBF, 0x61, 0x6A), // Bright Red
            ThemeColor(0xA3, 0xBE, 0x8C), // Bright Green
            ThemeColor(0xEB, 0xCB, 0x8B), // Bright Yellow
            ThemeColor(0x81, 0xA1, 0xC1), // Bright Blue
            ThemeColor(0xB4, 0x8E, 0xAD), // Bright Magenta
            ThemeColor(0x8F, 0xBC, 0xBB), // Bright Cyan
            ThemeColor(0xEC, 0xEF, 0xF4), // Bright White
        ]
    )

    public static let oneDark = TerminalTheme(
        id: "one-dark",
        name: "One Dark",
        foreground: ThemeColor(0xAB, 0xB2, 0xBF),
        background: ThemeColor(0x28, 0x2C, 0x34),
        cursor: ThemeColor(0x52, 0x8B, 0xFF),
        selection: ThemeColor(0x3E, 0x44, 0x51),
        ansiColors: [
            ThemeColor(0x28, 0x2C, 0x34), // Black
            ThemeColor(0xE0, 0x6C, 0x75), // Red
            ThemeColor(0x98, 0xC3, 0x79), // Green
            ThemeColor(0xE5, 0xC0, 0x7B), // Yellow
            ThemeColor(0x61, 0xAF, 0xEF), // Blue
            ThemeColor(0xC6, 0x78, 0xDD), // Magenta
            ThemeColor(0x56, 0xB6, 0xC2), // Cyan
            ThemeColor(0xAB, 0xB2, 0xBF), // White
            ThemeColor(0x54, 0x58, 0x62), // Bright Black
            ThemeColor(0xE0, 0x6C, 0x75), // Bright Red
            ThemeColor(0x98, 0xC3, 0x79), // Bright Green
            ThemeColor(0xE5, 0xC0, 0x7B), // Bright Yellow
            ThemeColor(0x61, 0xAF, 0xEF), // Bright Blue
            ThemeColor(0xC6, 0x78, 0xDD), // Bright Magenta
            ThemeColor(0x56, 0xB6, 0xC2), // Bright Cyan
            ThemeColor(0xBE, 0xC5, 0xD4), // Bright White
        ]
    )

    public static let catppuccinMocha = TerminalTheme(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        foreground: ThemeColor(0xCD, 0xD6, 0xF4),
        background: ThemeColor(0x1E, 0x1E, 0x2E),
        cursor: ThemeColor(0xF5, 0xE0, 0xDC),
        selection: ThemeColor(0x45, 0x47, 0x5A),
        ansiColors: [
            ThemeColor(0x45, 0x47, 0x5A), // Black (Surface1)
            ThemeColor(0xF3, 0x8B, 0xA8), // Red
            ThemeColor(0xA6, 0xE3, 0xA1), // Green
            ThemeColor(0xF9, 0xE2, 0xAF), // Yellow
            ThemeColor(0x89, 0xB4, 0xFA), // Blue
            ThemeColor(0xF5, 0xC2, 0xE7), // Pink
            ThemeColor(0x94, 0xE2, 0xD5), // Teal
            ThemeColor(0xBA, 0xC2, 0xDE), // Subtext1
            ThemeColor(0x58, 0x5B, 0x70), // Bright Black (Surface2)
            ThemeColor(0xF3, 0x8B, 0xA8), // Bright Red
            ThemeColor(0xA6, 0xE3, 0xA1), // Bright Green
            ThemeColor(0xF9, 0xE2, 0xAF), // Bright Yellow
            ThemeColor(0x89, 0xB4, 0xFA), // Bright Blue
            ThemeColor(0xF5, 0xC2, 0xE7), // Bright Pink
            ThemeColor(0x94, 0xE2, 0xD5), // Bright Teal
            ThemeColor(0xA6, 0xAD, 0xC8), // Bright White (Subtext0)
        ]
    )

    public static let monokai = TerminalTheme(
        id: "monokai",
        name: "Monokai",
        foreground: ThemeColor(0xF8, 0xF8, 0xF2),
        background: ThemeColor(0x27, 0x28, 0x22),
        cursor: ThemeColor(0xF8, 0xF8, 0xF0),
        selection: ThemeColor(0x49, 0x48, 0x3E),
        ansiColors: [
            ThemeColor(0x27, 0x28, 0x22), // Black
            ThemeColor(0xF9, 0x26, 0x72), // Red
            ThemeColor(0xA6, 0xE2, 0x2E), // Green
            ThemeColor(0xF4, 0xBF, 0x75), // Yellow
            ThemeColor(0x66, 0xD9, 0xEF), // Blue
            ThemeColor(0xAE, 0x81, 0xFF), // Magenta
            ThemeColor(0xA1, 0xEF, 0xE4), // Cyan
            ThemeColor(0xF8, 0xF8, 0xF2), // White
            ThemeColor(0x75, 0x71, 0x5E), // Bright Black
            ThemeColor(0xF9, 0x26, 0x72), // Bright Red
            ThemeColor(0xA6, 0xE2, 0x2E), // Bright Green
            ThemeColor(0xF4, 0xBF, 0x75), // Bright Yellow
            ThemeColor(0x66, 0xD9, 0xEF), // Bright Blue
            ThemeColor(0xAE, 0x81, 0xFF), // Bright Magenta
            ThemeColor(0xA1, 0xEF, 0xE4), // Bright Cyan
            ThemeColor(0xF9, 0xF8, 0xF5), // Bright White
        ]
    )

    public static let rosePine = TerminalTheme(
        id: "rose-pine",
        name: "Rosé Pine",
        foreground: ThemeColor(0xE0, 0xDE, 0xF4),
        background: ThemeColor(0x19, 0x17, 0x24),
        cursor: ThemeColor(0xE0, 0xDE, 0xF4),
        selection: ThemeColor(0x2A, 0x27, 0x3F),
        ansiColors: [
            ThemeColor(0x26, 0x23, 0x3A), // Black
            ThemeColor(0xEB, 0x6F, 0x92), // Red
            ThemeColor(0x9C, 0xCF, 0xD8), // Green (Foam)
            ThemeColor(0xF6, 0xC1, 0x77), // Yellow (Gold)
            ThemeColor(0x31, 0x74, 0x8F), // Blue (Pine)
            ThemeColor(0xC4, 0xA7, 0xE7), // Magenta (Iris)
            ThemeColor(0xEA, 0x9A, 0x97), // Cyan (Rose)
            ThemeColor(0xE0, 0xDE, 0xF4), // White
            ThemeColor(0x6E, 0x6A, 0x86), // Bright Black
            ThemeColor(0xEB, 0x6F, 0x92), // Bright Red
            ThemeColor(0x9C, 0xCF, 0xD8), // Bright Green
            ThemeColor(0xF6, 0xC1, 0x77), // Bright Yellow
            ThemeColor(0x31, 0x74, 0x8F), // Bright Blue
            ThemeColor(0xC4, 0xA7, 0xE7), // Bright Magenta
            ThemeColor(0xEA, 0x9A, 0x97), // Bright Cyan
            ThemeColor(0xE0, 0xDE, 0xF4), // Bright White
        ]
    )

    public static let githubDark = TerminalTheme(
        id: "github-dark",
        name: "GitHub Dark",
        foreground: ThemeColor(0xC9, 0xD1, 0xD9),
        background: ThemeColor(0x0D, 0x11, 0x17),
        cursor: ThemeColor(0xC9, 0xD1, 0xD9),
        selection: ThemeColor(0x16, 0x3B, 0x6E),
        ansiColors: [
            ThemeColor(0x48, 0x4F, 0x58), // Black
            ThemeColor(0xFF, 0x7B, 0x72), // Red
            ThemeColor(0x3F, 0xB9, 0x50), // Green
            ThemeColor(0xD2, 0x9A, 0x22), // Yellow
            ThemeColor(0x58, 0xA6, 0xFF), // Blue
            ThemeColor(0xBC, 0x8C, 0xFF), // Magenta
            ThemeColor(0x39, 0xD3, 0xEF), // Cyan
            ThemeColor(0xB1, 0xBA, 0xC4), // White
            ThemeColor(0x6E, 0x76, 0x81), // Bright Black
            ThemeColor(0xFF, 0xA1, 0x98), // Bright Red
            ThemeColor(0x56, 0xD3, 0x64), // Bright Green
            ThemeColor(0xE3, 0xB3, 0x41), // Bright Yellow
            ThemeColor(0x79, 0xC0, 0xFF), // Bright Blue
            ThemeColor(0xD2, 0xA8, 0xFF), // Bright Magenta
            ThemeColor(0x56, 0xD4, 0xDD), // Bright Cyan
            ThemeColor(0xF0, 0xF6, 0xFC), // Bright White
        ]
    )

    public static let solarizedLight = TerminalTheme(
        id: "solarized-light",
        name: "Solarized Light",
        foreground: ThemeColor(0x65, 0x7B, 0x83), // base00
        background: ThemeColor(0xFD, 0xF6, 0xE3), // base3
        cursor: ThemeColor(0x58, 0x6E, 0x75),     // base01
        selection: ThemeColor(0xEE, 0xE8, 0xD5),   // base2
        ansiColors: [
            ThemeColor(0xEE, 0xE8, 0xD5), // base2
            ThemeColor(0xDC, 0x32, 0x2F), // red
            ThemeColor(0x85, 0x99, 0x00), // green
            ThemeColor(0xB5, 0x89, 0x00), // yellow
            ThemeColor(0x26, 0x8B, 0xD2), // blue
            ThemeColor(0xD3, 0x36, 0x82), // magenta
            ThemeColor(0x2A, 0xA1, 0x98), // cyan
            ThemeColor(0x07, 0x36, 0x42), // base02
            ThemeColor(0xFD, 0xF6, 0xE3), // base3
            ThemeColor(0xCB, 0x4B, 0x16), // orange
            ThemeColor(0x93, 0xA1, 0xA1), // base1
            ThemeColor(0x83, 0x94, 0x96), // base0
            ThemeColor(0x65, 0x7B, 0x83), // base00
            ThemeColor(0x6C, 0x71, 0xC4), // violet
            ThemeColor(0x58, 0x6E, 0x75), // base01
            ThemeColor(0x00, 0x2B, 0x36), // base03
        ]
    )

    public static let githubLight = TerminalTheme(
        id: "github-light",
        name: "GitHub Light",
        foreground: ThemeColor(0x24, 0x29, 0x2E),
        background: ThemeColor(0xFF, 0xFF, 0xFF),
        cursor: ThemeColor(0x04, 0x4F, 0x88),
        selection: ThemeColor(0xDB, 0xED, 0xFF),
        ansiColors: [
            ThemeColor(0x24, 0x29, 0x2E), // Black
            ThemeColor(0xCF, 0x22, 0x2E), // Red
            ThemeColor(0x11, 0x6B, 0x29), // Green
            ThemeColor(0x4D, 0x2D, 0x00), // Yellow
            ThemeColor(0x04, 0x50, 0xD1), // Blue
            ThemeColor(0x8E, 0x44, 0xAD), // Magenta
            ThemeColor(0x1B, 0x7C, 0x83), // Cyan
            ThemeColor(0x6E, 0x76, 0x81), // White
            ThemeColor(0x57, 0x60, 0x6A), // Bright Black
            ThemeColor(0xA4, 0x00, 0x0F), // Bright Red
            ThemeColor(0x1A, 0x7F, 0x37), // Bright Green
            ThemeColor(0x63, 0x3C, 0x01), // Bright Yellow
            ThemeColor(0x21, 0x8B, 0xFF), // Bright Blue
            ThemeColor(0xA4, 0x75, 0xF9), // Bright Magenta
            ThemeColor(0x3E, 0x99, 0x9F), // Bright Cyan
            ThemeColor(0x8C, 0x95, 0x9F), // Bright White
        ]
    )

    // MARK: - Catalog

    public static let builtInThemes: [TerminalTheme] = [
        dracula,
        proDark,
        tokyoNight,
        gruvboxDark,
        nord,
        oneDark,
        catppuccinMocha,
        monokai,
        rosePine,
        githubDark,
        solarizedDark,
        solarizedLight,
        githubLight,
        classicLight,
    ]

    public static let defaultTheme = dracula

    public static func theme(forId id: String) -> TerminalTheme {
        builtInThemes.first { $0.id == id } ?? defaultTheme
    }
}
