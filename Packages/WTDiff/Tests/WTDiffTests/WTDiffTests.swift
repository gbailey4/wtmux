import Testing
@testable import WTDiff

// MARK: - Basic parsing

@Test func parsesUnifiedDiff() {
    let diff = """
    diff --git a/src/main.swift b/src/main.swift
    index 1234567..abcdefg 100644
    --- a/src/main.swift
    +++ b/src/main.swift
    @@ -1,3 +1,4 @@
     import Foundation
    +import SwiftUI

     print("hello")
    """

    let parser = DiffParser()
    let files = parser.parse(diff)
    #expect(files.count == 1)
    #expect(files[0].displayPath == "src/main.swift")
    #expect(files[0].hunks.count == 1)
    #expect(files[0].hunks[0].lines.count == 4)
}

// MARK: - Edge cases

@Test func parsesEmptyDiff() {
    let parser = DiffParser()
    let files = parser.parse("")
    #expect(files.isEmpty)
}

@Test func parsesWhitespaceOnlyDiff() {
    let parser = DiffParser()
    let files = parser.parse("   \n  \n")
    #expect(files.isEmpty)
}

@Test func parsesMultipleFiles() {
    let diff = """
    diff --git a/file1.swift b/file1.swift
    index 1234567..abcdefg 100644
    --- a/file1.swift
    +++ b/file1.swift
    @@ -1,2 +1,3 @@
     line1
    +line2
     line3
    diff --git a/file2.swift b/file2.swift
    index 7654321..fedcba9 100644
    --- a/file2.swift
    +++ b/file2.swift
    @@ -1 +1 @@
    -old
    +new
    """

    let parser = DiffParser()
    let files = parser.parse(diff)
    #expect(files.count == 2)
    #expect(files[0].displayPath == "file1.swift")
    #expect(files[1].displayPath == "file2.swift")
}

@Test func parsesMultipleHunks() {
    let diff = """
    diff --git a/file.swift b/file.swift
    index 1234567..abcdefg 100644
    --- a/file.swift
    +++ b/file.swift
    @@ -1,3 +1,4 @@
     first
    +inserted
     second
     third
    @@ -10,3 +11,4 @@
     tenth
    +also inserted
     eleventh
     twelfth
    """

    let parser = DiffParser()
    let files = parser.parse(diff)
    #expect(files.count == 1)
    #expect(files[0].hunks.count == 2)
    #expect(files[0].hunks[0].oldStart == 1)
    #expect(files[0].hunks[1].oldStart == 10)
}

@Test func parsesDeletion() {
    let diff = """
    diff --git a/deleted.swift b/deleted.swift
    deleted file mode 100644
    index 1234567..0000000
    --- a/deleted.swift
    +++ /dev/null
    @@ -1,3 +0,0 @@
    -line1
    -line2
    -line3
    """

    let parser = DiffParser()
    let files = parser.parse(diff)
    #expect(files.count == 1)
    // displayPath should use oldPath when newPath is /dev/null
    #expect(files[0].displayPath == "deleted.swift")
    #expect(files[0].hunks[0].lines.count == 3)
    #expect(files[0].hunks[0].lines.allSatisfy { $0.kind == .deletion })
}

@Test func parsesNewFile() {
    let diff = """
    diff --git a/new.swift b/new.swift
    new file mode 100644
    index 0000000..1234567
    --- /dev/null
    +++ b/new.swift
    @@ -0,0 +1,3 @@
    +line1
    +line2
    +line3
    """

    let parser = DiffParser()
    let files = parser.parse(diff)
    #expect(files.count == 1)
    #expect(files[0].displayPath == "new.swift")
    #expect(files[0].hunks[0].lines.count == 3)
    #expect(files[0].hunks[0].lines.allSatisfy { $0.kind == .addition })
}

@Test func parsesLineNumbers() {
    let diff = """
    diff --git a/file.swift b/file.swift
    index 1234567..abcdefg 100644
    --- a/file.swift
    +++ b/file.swift
    @@ -5,3 +5,4 @@
     context
    +added
     more context
     end
    """

    let parser = DiffParser()
    let files = parser.parse(diff)
    let lines = files[0].hunks[0].lines

    // Context line: old=5, new=5
    #expect(lines[0].kind == .context)
    #expect(lines[0].oldLineNumber == 5)
    #expect(lines[0].newLineNumber == 5)

    // Addition: no old line number, new=6
    #expect(lines[1].kind == .addition)
    #expect(lines[1].oldLineNumber == nil)
    #expect(lines[1].newLineNumber == 6)

    // Context: old=6, new=7
    #expect(lines[2].kind == .context)
    #expect(lines[2].oldLineNumber == 6)
    #expect(lines[2].newLineNumber == 7)
}

@Test func parsesBinaryFileDiff() {
    // Binary diffs have no hunk content
    let diff = """
    diff --git a/image.png b/image.png
    index 1234567..abcdefg 100644
    Binary files a/image.png and b/image.png differ
    """

    let parser = DiffParser()
    let files = parser.parse(diff)
    #expect(files.count == 1)
    #expect(files[0].hunks.isEmpty)
}

@Test func parsesRename() {
    let diff = """
    diff --git a/old_name.swift b/new_name.swift
    similarity index 100%
    rename from old_name.swift
    rename to new_name.swift
    """

    let parser = DiffParser()
    let files = parser.parse(diff)
    #expect(files.count == 1)
    #expect(files[0].oldPath == "old_name.swift")
    #expect(files[0].newPath == "new_name.swift")
    #expect(files[0].hunks.isEmpty)
}

@Test func hunkCountsParsedCorrectly() {
    let diff = """
    diff --git a/file.swift b/file.swift
    index 1234567..abcdefg 100644
    --- a/file.swift
    +++ b/file.swift
    @@ -1,7 +1,6 @@
     context
    -removed
     context
     context
     context
     context
     context
    """

    let parser = DiffParser()
    let files = parser.parse(diff)
    #expect(files[0].hunks[0].oldStart == 1)
    #expect(files[0].hunks[0].oldCount == 7)
    #expect(files[0].hunks[0].newStart == 1)
    #expect(files[0].hunks[0].newCount == 6)
}
