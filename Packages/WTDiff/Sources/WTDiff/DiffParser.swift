import Foundation

public struct DiffFile: Identifiable, Sendable {
    public let id: String
    public let oldPath: String
    public let newPath: String
    public let hunks: [DiffHunk]

    public init(id: String, oldPath: String, newPath: String, hunks: [DiffHunk]) {
        self.id = id
        self.oldPath = oldPath
        self.newPath = newPath
        self.hunks = hunks
    }

    public var displayPath: String {
        newPath == "/dev/null" ? oldPath : newPath
    }
}

public struct DiffHunk: Identifiable, Sendable {
    public let id: String
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(id: String, header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

public struct DiffLine: Identifiable, Sendable {
    public enum Kind: Sendable {
        case context
        case addition
        case deletion
    }

    public let id: String
    public let kind: Kind
    public let content: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?

    public init(id: String, kind: Kind, content: String, oldLineNumber: Int?, newLineNumber: Int?) {
        self.id = id
        self.kind = kind
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

public struct DiffParser: Sendable {
    public init() {}

    public func parse(_ unifiedDiff: String) -> [DiffFile] {
        var files: [DiffFile] = []
        let lines = unifiedDiff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0

        while i < lines.count {
            // Look for diff --git header
            if lines[i].hasPrefix("diff --git ") {
                let (file, nextIndex) = parseFile(lines: lines, from: i)
                if let file {
                    files.append(file)
                }
                i = nextIndex
            } else {
                i += 1
            }
        }

        return files
    }

    private func parseFile(lines: [String], from startIndex: Int) -> (DiffFile?, Int) {
        var i = startIndex
        let diffHeader = lines[i]

        // Parse file paths from "diff --git a/path b/path"
        let parts = diffHeader.split(separator: " ", maxSplits: 3).map(String.init)
        let oldPath: String
        let newPath: String
        if parts.count >= 4 {
            oldPath = String(parts[2].dropFirst(2)) // Remove "a/"
            newPath = String(parts[3].dropFirst(2)) // Remove "b/"
        } else {
            return (nil, i + 1)
        }
        i += 1

        // Skip index, old mode, new mode lines
        while i < lines.count && !lines[i].hasPrefix("---") && !lines[i].hasPrefix("diff --git") && !lines[i].hasPrefix("@@") {
            i += 1
        }

        // Parse --- and +++ headers
        if i < lines.count && lines[i].hasPrefix("---") { i += 1 }
        if i < lines.count && lines[i].hasPrefix("+++") { i += 1 }

        // Parse hunks
        var hunks: [DiffHunk] = []
        var hunkIndex = 0
        while i < lines.count && !lines[i].hasPrefix("diff --git") {
            if lines[i].hasPrefix("@@") {
                let (hunk, nextIndex) = parseHunk(lines: lines, from: i, hunkIndex: hunkIndex)
                if let hunk {
                    hunks.append(hunk)
                    hunkIndex += 1
                }
                i = nextIndex
            } else {
                i += 1
            }
        }

        let file = DiffFile(
            id: newPath,
            oldPath: oldPath,
            newPath: newPath,
            hunks: hunks
        )
        return (file, i)
    }

    private func parseHunk(lines: [String], from startIndex: Int, hunkIndex: Int) -> (DiffHunk?, Int) {
        let header = lines[startIndex]

        // Parse @@ -old,count +new,count @@
        guard let range = header.range(of: #"@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@"#, options: .regularExpression) else {
            return (nil, startIndex + 1)
        }

        let headerContent = String(header[range])
        let numbers = headerContent
            .replacingOccurrences(of: "@@", with: "")
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")

        let oldParts = String(numbers[0]).dropFirst().split(separator: ",")
        let newParts = String(numbers[1]).dropFirst().split(separator: ",")

        let oldStart = Int(oldParts[0]) ?? 0
        let oldCount = oldParts.count > 1 ? Int(oldParts[1]) ?? 0 : 1
        let newStart = Int(newParts[0]) ?? 0
        let newCount = newParts.count > 1 ? Int(newParts[1]) ?? 0 : 1

        var i = startIndex + 1
        var diffLines: [DiffLine] = []
        var oldLine = oldStart
        var newLine = newStart
        var lineIndex = 0

        while i < lines.count && !lines[i].hasPrefix("@@") && !lines[i].hasPrefix("diff --git") {
            let line = lines[i]
            let kind: DiffLine.Kind
            let content: String
            var oldNum: Int?
            var newNum: Int?

            if line.hasPrefix("+") {
                kind = .addition
                content = String(line.dropFirst())
                newNum = newLine
                newLine += 1
            } else if line.hasPrefix("-") {
                kind = .deletion
                content = String(line.dropFirst())
                oldNum = oldLine
                oldLine += 1
            } else if line.hasPrefix(" ") || line.isEmpty {
                kind = .context
                content = line.isEmpty ? "" : String(line.dropFirst())
                oldNum = oldLine
                newNum = newLine
                oldLine += 1
                newLine += 1
            } else {
                // Binary file or other marker
                i += 1
                continue
            }

            diffLines.append(DiffLine(
                id: "\(hunkIndex)-\(lineIndex)",
                kind: kind,
                content: content,
                oldLineNumber: oldNum,
                newLineNumber: newNum
            ))
            lineIndex += 1
            i += 1
        }

        let hunk = DiffHunk(
            id: "\(hunkIndex)",
            header: header,
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            lines: diffLines
        )
        return (hunk, i)
    }
}
