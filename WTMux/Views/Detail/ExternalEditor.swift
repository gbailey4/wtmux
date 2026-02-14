import AppKit
import SwiftUI

struct ExternalEditor: Codable, Identifiable, Equatable {
    var id: String { bundleId }
    var name: String
    var bundleId: String

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }

    static let builtIn: [ExternalEditor] = [
        ExternalEditor(name: "VS Code", bundleId: "com.microsoft.VSCode"),
        ExternalEditor(name: "Cursor", bundleId: "com.todesktop.230313mzl4w4u92"),
        ExternalEditor(name: "Zed", bundleId: "dev.zed.Zed"),
        ExternalEditor(name: "Sublime Text", bundleId: "com.sublimetext.4"),
        ExternalEditor(name: "Xcode", bundleId: "com.apple.dt.Xcode"),
    ]

    static func installedEditors(custom: [ExternalEditor], hidden: Set<String> = hiddenEditorIds) -> [ExternalEditor] {
        var seen = Set<String>()
        var result: [ExternalEditor] = []
        for editor in builtIn + custom {
            guard !seen.contains(editor.bundleId) else { continue }
            seen.insert(editor.bundleId)
            if editor.isInstalled && !hidden.contains(editor.bundleId) {
                result.append(editor)
            }
        }
        return result
    }

    static func open(fileURL: URL, editor: ExternalEditor) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
    }

    // MARK: - App Bundle

    static func fromAppBundle(at url: URL) -> ExternalEditor? {
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return ExternalEditor(name: name, bundleId: bundleId)
    }

    var icon: NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    // MARK: - Persistence

    static var hiddenEditorIds: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: "hiddenEditorIds") ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "hiddenEditorIds")
        }
    }

    static var customEditors: [ExternalEditor] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "customEditors"),
                  let editors = try? JSONDecoder().decode([ExternalEditor].self, from: data) else {
                return []
            }
            return editors
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: "customEditors")
        }
    }
}
