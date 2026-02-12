import Testing
@testable import WTDiff

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
