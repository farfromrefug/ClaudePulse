import XCTest
@testable import ccpulse

/// Hooks mark the edges of a turn, not the middle. These cover the silence in
/// between, which used to be read as "finished".
final class SessionLivenessTests: XCTestCase {

    private var transcript: URL!

    override func setUpWithError() throws {
        transcript = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pulse-liveness-\(UUID().uuidString).jsonl")
        try "{}".write(to: transcript, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: transcript)
    }

    private func event(_ name: String, tool: String? = nil) -> HookEvent {
        var json = #"{"session_id":"s","hook_event_name":"\#(name)","cwd":"/repo","transcript_path":"\#(transcript.path)""#
        if let tool { json += #","tool_name":"\#(tool)""# }
        json += "}"
        return try! JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    }

    private func touch(_ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: transcript.path)
    }

    /// A build that runs for minutes sends PreToolUse and then nothing until it
    /// finishes. That gap is the tool working, not the session going idle.
    func testAToolStillRunningKeepsTheSessionBusy() throws {
        let session = Session(id: "s")
        session.handleEvent(event("PreToolUse", tool: "Bash"))
        try touch(Date().addingTimeInterval(-600))

        XCTAssertTrue(session.toolInFlight)
        XCTAssertTrue(session.looksBusy(quietFor: 30))
    }

    func testAFinishedToolLetsTheSessionGoQuiet() throws {
        let session = Session(id: "s")
        session.handleEvent(event("PreToolUse", tool: "Bash"))
        session.handleEvent(event("PostToolUse", tool: "Bash"))
        try touch(Date().addingTimeInterval(-600))

        XCTAssertFalse(session.toolInFlight)
        XCTAssertFalse(session.looksBusy(quietFor: 30))
    }

    /// Claude appends to the transcript as a turn streams, so a file touched a
    /// moment ago is a session mid-sentence.
    func testARecentlyWrittenTranscriptCountsAsBusy() throws {
        let session = Session(id: "s")
        session.handleEvent(event("Stop"))
        try touch(Date().addingTimeInterval(-5))

        XCTAssertTrue(session.looksBusy(quietFor: 30))
    }

    func testAnUntouchedTranscriptDoesNot() throws {
        let session = Session(id: "s")
        session.handleEvent(event("Stop"))
        try touch(Date().addingTimeInterval(-120))

        XCTAssertFalse(session.looksBusy(quietFor: 30))
    }

    /// A session Pulse has never seen a transcript for has nothing to go on,
    /// and must not be held busy for ever on the strength of that.
    func testNoTranscriptIsNotBusy() {
        let session = Session(id: "s")
        XCTAssertFalse(session.looksBusy(quietFor: 30))
    }

    /// A new prompt starts a turn, so whatever tool was in flight is not.
    func testANewPromptClearsAToolInFlight() {
        let session = Session(id: "s")
        session.handleEvent(event("PreToolUse", tool: "Bash"))
        session.handleEvent(event("UserPromptSubmit"))
        XCTAssertFalse(session.toolInFlight)
    }
}
