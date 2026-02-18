import AppKit
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Custom UTType for terminal tab drag-and-drop between columns.
    static let terminalTabReference = UTType(exportedAs: "com.grahampark.wtmux.terminal-tab-reference")
}

struct TerminalTabReference: Codable, Transferable {
    let columnId: String
    let sessionId: String

    static let pasteboardType = NSPasteboard.PasteboardType(UTType.terminalTabReference.identifier)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .terminalTabReference)
    }
}
