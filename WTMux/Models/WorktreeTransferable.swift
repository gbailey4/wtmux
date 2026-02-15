import AppKit
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Custom UTType for worktree drag-and-drop, declared in Info.plist.
    /// Conforms to `public.data` (not `public.text`) so hosting views with
    /// text-based drag registrations won't intercept it.
    static let worktreeReference = UTType(exportedAs: "com.grahampark.wtmux.worktree-reference")
}

struct WorktreeReference: Codable, Transferable {
    let worktreeID: String
    let sourcePaneID: String?

    /// Pasteboard type derived from the declared UTType.
    static let pasteboardType = NSPasteboard.PasteboardType(UTType.worktreeReference.identifier)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .worktreeReference)
    }

    /// Creates an NSItemProvider with the reference eagerly encoded under our custom UTType.
    func itemProvider() -> NSItemProvider {
        guard let data = try? JSONEncoder().encode(self) else { return NSItemProvider() }
        return NSItemProvider(item: data as NSData, typeIdentifier: UTType.worktreeReference.identifier)
    }
}
