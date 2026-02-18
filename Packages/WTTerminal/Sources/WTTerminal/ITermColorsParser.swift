import Foundation

public enum ITermColorsParser {
    public enum ParseError: Error, CustomStringConvertible {
        case invalidPlist
        case missingColor(String)
        case invalidColorComponent(String)

        public var description: String {
            switch self {
            case .invalidPlist:
                return "Data is not a valid plist"
            case .missingColor(let key):
                return "Missing required color key: \(key)"
            case .invalidColorComponent(let key):
                return "Invalid color components for key: \(key)"
            }
        }
    }

    /// Parse an `.itermcolors` plist file into a `TerminalTheme`.
    /// - Parameters:
    ///   - data: The raw plist data.
    ///   - name: Display name for the theme.
    /// - Returns: A `TerminalTheme` with an ID prefixed by `"custom-"`.
    public static func parse(data: Data, name: String) throws -> TerminalTheme {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ParseError.invalidPlist
        }

        let foreground = try extractColor(from: plist, key: "Foreground Color")
        let background = try extractColor(from: plist, key: "Background Color")
        let cursor = try extractColor(from: plist, key: "Cursor Color")
        let selection = try extractColor(from: plist, key: "Selection Color")

        var ansiColors: [ThemeColor] = []
        for i in 0..<16 {
            let key = "Ansi \(i) Color"
            let color = try extractColor(from: plist, key: key)
            ansiColors.append(color)
        }

        let id = "custom-" + name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        return TerminalTheme(
            id: id,
            name: name,
            foreground: foreground,
            background: background,
            cursor: cursor,
            selection: selection,
            ansiColors: ansiColors
        )
    }

    private static func extractColor(from plist: [String: Any], key: String) throws -> ThemeColor {
        guard let colorDict = plist[key] as? [String: Any] else {
            throw ParseError.missingColor(key)
        }

        // iTerm2 stores color components as floats 0.0–1.0
        // Keys can be "Red Component", "Green Component", "Blue Component"
        guard let red = colorDict["Red Component"] as? Double,
              let green = colorDict["Green Component"] as? Double,
              let blue = colorDict["Blue Component"] as? Double else {
            throw ParseError.invalidColorComponent(key)
        }

        return ThemeColor(
            UInt8(clamping: Int((red * 255).rounded())),
            UInt8(clamping: Int((green * 255).rounded())),
            UInt8(clamping: Int((blue * 255).rounded()))
        )
    }
}
