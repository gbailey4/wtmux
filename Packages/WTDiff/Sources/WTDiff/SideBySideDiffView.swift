import SwiftUI

public struct InlineDiffView: View {
    let file: DiffFile

    public init(file: DiffFile) {
        self.file = file
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(file.hunks) { hunk in
                    HunkHeaderView(header: hunk.header)
                    ForEach(hunk.lines) { line in
                        DiffLineView(line: line)
                    }
                }
            }
        }
        .font(.system(.body, design: .monospaced))
    }
}

struct HunkHeaderView: View {
    let header: String

    var body: some View {
        Text(header)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.1))
    }
}

struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Line numbers
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)

            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)

            // Prefix
            Text(prefix)
                .foregroundStyle(prefixColor)
                .frame(width: 14)

            // Content
            Text(line.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(backgroundColor)
    }

    private var prefix: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "-"
        case .context: " "
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .addition: .green
        case .deletion: .red
        case .context: .secondary
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .addition: Color.green.opacity(0.1)
        case .deletion: Color.red.opacity(0.1)
        case .context: .clear
        }
    }
}
