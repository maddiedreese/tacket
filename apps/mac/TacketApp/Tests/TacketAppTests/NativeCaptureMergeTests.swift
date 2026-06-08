import XCTest
@testable import TacketApp

final class NativeCaptureMergeTests: XCTestCase {
    func testDesktopCaptureMergeSkipsRepeatedSnapshots() {
        let snapshot = """
        User
        Explain this function.
        Assistant
        It parses the file.
        ```swift
        let value = parse(input)
        ```
        User
        What about errors?
        Assistant
        It throws when input is invalid.
        """

        let merged = TacketModel.mergeNativeCaptureSnapshots([snapshot, snapshot, snapshot])

        XCTAssertEqual(occurrences(of: "Explain this function.", in: merged), 1)
        XCTAssertEqual(occurrences(of: "It throws when input is invalid.", in: merged), 1)
        XCTAssertTrue(merged.contains("```swift\nlet value = parse(input)\n```"))
    }

    func testDesktopCaptureMergeKeepsOnlyNewLinesFromOverlappingScrolls() {
        let first = """
        User
        Start at the top.
        Assistant
        First answer.
        User
        Continue.
        """
        let second = """
        Assistant
        First answer.
        User
        Continue.
        Assistant
        Second answer.
        User
        Finish.
        """

        let merged = TacketModel.mergeNativeCaptureSnapshots([first, second])

        XCTAssertEqual(
            merged,
            """
            User
            Start at the top.
            Assistant
            First answer.
            User
            Continue.
            Assistant
            Second answer.
            User
            Finish.
            """
        )
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
