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

    func testDesktopCaptureMergeCollapsesRepeatedCodexWindowTextWithOcrVariation() {
        let repeated = """
        <->0
        Answer greeting
        Hey Codex, how's it going?
        Outputs
        No artifacts yet
        Hey Maddie! I'm here and warmed up, somewhere between "ready to debug a gnarly stack trace" and "happy to
        Sources
        just hang out for a minute." How's your day going?
        No sources yet
        Ask for follow-up changes
        + O Full access v
        5.5 Medium v & 1)
        <->0
        Answer greeting
        Hey Codex, how's it going?
        Outputs
        No artifacts yet
        Hey Maddie! I'm here and warmed up, somewhere between "ready to debug a gnarly stack trace" and "happy to
        Sources
        just hang out for a minute." How's your day going?
        No sources yet
        Ask for follow-up changes
        + O Full access v
        5.5 Medium v ?
        <->0
        Answer greeting
        Hey Codex, how's it going?
        Outputs
        No artifacts yet
        Hey Maddie! I'm here and warmed up, somewhere between "ready to debug a gnarly stack trace" and "happy to
        Sources
        just hang out for a minute." How's your day going?
        No sources yet
        Ask for follow-up changes
        + O Full access v
        5.5 Medium v (1)
        """

        let merged = TacketModel.mergeNativeCaptureSnapshots([repeated])

        XCTAssertEqual(occurrences(of: "Answer greeting", in: merged), 1)
        XCTAssertEqual(occurrences(of: "Hey Codex, how's it going?", in: merged), 1)
        XCTAssertEqual(occurrences(of: "Hey Maddie!", in: merged), 1)
        XCTAssertFalse(merged.contains("No artifacts yet"))
        XCTAssertFalse(merged.contains("Ask for follow-up changes"))
        XCTAssertFalse(merged.contains("Full access"))
    }

    func testDesktopCaptureMergeCollapsesRepeatedCodexWindowTextWithTruncatedTitleVariation() {
        let repeated = """
        +-> 0
        Answer greeting
        Hey Codex, how's it going?
        Outputs
        No artifacts yet
        Hey Maddie! I'm here and warmed up, somewhere between "ready to debug a gnarly stack trace" and "happy to
        Sources
        just hang out for a minute." How's your day going?
        No sources yet
        Ask for follow-up changes
        + O Full access v
        5.5 Medium v & 1)
        Answer greeting...
        Hey Codex, how's it going?
        Outputs
        No artifacts yet
        Hey Maddie! I'm here and warmed up, somewhere between "ready to debug a gnarly stack trace" and "happy to
        Sources
        just hang out for a minute." How's your day going?
        No sources yet
        Ask for follow-up changes
        + O Full access v
        5.5 Medium v ?
        """

        let merged = TacketModel.mergeNativeCaptureSnapshots([repeated])

        XCTAssertEqual(
            merged,
            """
            Answer greeting
            Hey Codex, how's it going?
            Hey Maddie! I'm here and warmed up, somewhere between "ready to debug a gnarly stack trace" and "happy to
            just hang out for a minute." How's your day going?
            """
        )
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
