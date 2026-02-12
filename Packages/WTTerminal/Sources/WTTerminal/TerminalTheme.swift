import AppKit
import SwiftTerm

public struct ThemeColor: Sendable, Codable, Hashable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public func toNSColor() -> NSColor {
        NSColor(
            deviceRed: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: 1.0
        )
    }

    public func toSwiftTermColor() -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16(r) * 257,
            green: UInt16(g) * 257,
            blue: UInt16(b) * 257
        )
    }
}

public struct TerminalTheme: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let foreground: ThemeColor
    public let background: ThemeColor
    public let cursor: ThemeColor
    public let selection: ThemeColor
    public let ansiColors: [ThemeColor] // 16 elements

    public init(
        id: String,
        name: String,
        foreground: ThemeColor,
        background: ThemeColor,
        cursor: ThemeColor,
        selection: ThemeColor,
        ansiColors: [ThemeColor]
    ) {
        precondition(ansiColors.count == 16, "ansiColors must have exactly 16 elements")
        self.id = id
        self.name = name
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.ansiColors = ansiColors
    }
}
