import SwiftUI
import HighlightSwift

public struct DiffContentView<HeaderAccessory: View>: View {
    let file: DiffFile
    var onClose: () -> Void
    var backgroundColor: Color?
    var foregroundColor: Color?
    @ViewBuilder var headerAccessory: () -> HeaderAccessory

    @Environment(\.colorScheme) private var colorScheme
    @State private var highlightedLines: [String: AttributedString] = [:]

    public init(file: DiffFile, onClose: @escaping () -> Void,
                backgroundColor: Color? = nil, foregroundColor: Color? = nil)
        where HeaderAccessory == EmptyView {
        self.file = file
        self.onClose = onClose
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.headerAccessory = { EmptyView() }
    }

    public init(file: DiffFile, onClose: @escaping () -> Void,
                backgroundColor: Color? = nil, foregroundColor: Color? = nil,
                @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory) {
        self.file = file
        self.onClose = onClose
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.headerAccessory = headerAccessory
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(file.hunks) { hunk in
                            hunkHeader(hunk)
                            ForEach(hunk.lines) { line in
                                diffLine(line)
                            }
                        }
                    }
                    .frame(minWidth: 600, minHeight: proxy.size.height, alignment: .top)
                }
                .font(.system(size: 12, weight: .regular, design: .monospaced))
            }
        }
        .background(backgroundColor ?? Color.clear)
        .task(id: "\(file.id)-\(colorScheme)") {
            await highlightFile()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerBar: some View {
        HStack {
            Text(file.displayPath)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            headerAccessory()
            Button { onClose() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Hunk Header

    @ViewBuilder
    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        Text(hunk.header)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.leading, 82)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08))
    }

    // MARK: - Diff Line

    @ViewBuilder
    private func diffLine(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            // Old line number
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .background(gutterBackground(line.kind))

            // New line number
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .background(gutterBackground(line.kind))

            // Colored bar
            Rectangle()
                .fill(barColor(line.kind))
                .frame(width: 2)

            // Code content
            if let highlighted = highlightedLines[line.id] {
                Text(highlighted)
                    .padding(.leading, 8)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(line.content)
                    .foregroundStyle(foregroundColor ?? .primary)
                    .padding(.leading, 8)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 1)
        .background(lineBackground(line.kind))
    }

    // MARK: - Colors

    private func lineBackground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: Color.green.opacity(0.08)
        case .deletion: Color.red.opacity(0.08)
        case .context: .clear
        }
    }

    private func gutterBackground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: Color.green.opacity(0.15)
        case .deletion: Color.red.opacity(0.15)
        case .context: .clear
        }
    }

    private func barColor(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        case .context: .clear
        }
    }

    // MARK: - Syntax Highlighting

    private func highlightFile() async {
        let highlighter = Highlight()
        let colors: HighlightColors = colorScheme == .dark
            ? .dark(.xcode)
            : .light(.xcode)

        // Collect lines by stream: "new" (context + additions) and "old" (deletions)
        var newLineIds: [String] = []
        var newContents: [String] = []
        var oldLineIds: [String] = []
        var oldContents: [String] = []

        for hunk in file.hunks {
            for line in hunk.lines {
                switch line.kind {
                case .context, .addition:
                    newLineIds.append(line.id)
                    newContents.append(line.content)
                case .deletion:
                    oldLineIds.append(line.id)
                    oldContents.append(line.content)
                }
            }
        }

        var result: [String: AttributedString] = [:]

        // Highlight new content block (context + additions)
        if !newContents.isEmpty {
            let joined = newContents.joined(separator: "\n")
            if let highlighted = await highlightText(joined, highlighter: highlighter, colors: colors) {
                let lines = splitByNewlines(highlighted)
                for (i, id) in newLineIds.enumerated() where i < lines.count {
                    result[id] = lines[i]
                }
            }
        }

        // Highlight old content block (deletions)
        if !oldContents.isEmpty {
            let joined = oldContents.joined(separator: "\n")
            if let highlighted = await highlightText(joined, highlighter: highlighter, colors: colors) {
                let lines = splitByNewlines(highlighted)
                for (i, id) in oldLineIds.enumerated() where i < lines.count {
                    result[id] = lines[i]
                }
            }
        }

        highlightedLines = result
    }

    private func highlightText(_ text: String, highlighter: Highlight, colors: HighlightColors) async -> AttributedString? {
        if let lang = languageHint {
            return try? await highlighter.attributedText(text, language: lang, colors: colors)
        } else {
            return try? await highlighter.attributedText(text, colors: colors)
        }
    }

    private var languageHint: String? {
        let ext = (file.displayPath as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "rb": return "ruby"
        case "go": return "go"
        case "rs": return "rust"
        case "java": return "java"
        case "kt": return "kotlin"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "cs": return "csharp"
        case "html", "htm": return "html"
        case "css": return "css"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "sh", "bash", "zsh": return "bash"
        case "sql": return "sql"
        case "xml": return "xml"
        default: return nil
        }
    }

    private func splitByNewlines(_ source: AttributedString) -> [AttributedString] {
        let plain = String(source.characters)
        let components = plain.components(separatedBy: "\n")

        var results: [AttributedString] = []
        var pos = source.startIndex

        for (i, component) in components.enumerated() {
            if component.isEmpty {
                results.append(AttributedString())
            } else {
                let end = source.characters.index(pos, offsetBy: component.count)
                results.append(AttributedString(source[pos..<end]))
                pos = end
            }
            // Skip the newline character
            if i < components.count - 1 && pos < source.endIndex {
                pos = source.characters.index(after: pos)
            }
        }

        return results
    }
}
