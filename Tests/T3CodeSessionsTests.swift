import XCTest
@testable import ccpulse

final class T3CodeSessionsTests: XCTestCase {

    private var idFile: URL!

    override func setUpWithError() throws {
        idFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pulse-t3-env-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: idFile)
    }

    // MARK: - Origin

    func testEntrypointNamesT3Code() {
        XCTAssertTrue(TerminalOrigin(headers: ["x-pulse-entrypoint": "t3-code"]).isT3Code)
    }

    func testThreadIdNamesT3Code() {
        let origin = TerminalOrigin(headers: ["x-pulse-t3-thread": "bb6ba79b"])
        XCTAssertTrue(origin.isT3Code)
        XCTAssertEqual(origin.t3CodeThreadId, "bb6ba79b")
        XCTAssertFalse(origin.isEmpty)
    }

    func testTerminalSessionIsNotT3Code() {
        XCTAssertFalse(TerminalOrigin(headers: [
            "x-pulse-entrypoint": "cli", "x-pulse-term-program": "iTerm.app",
        ]).isT3Code)
    }

    // MARK: - Links

    func testThreadLinkNamesEnvironmentAndThread() throws {
        try "f9ec21de-85c7\n".write(to: idFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(
            T3CodeSessions.threadURL(threadId: "bb6ba79b-d05b", environmentIdFile: idFile)?.absoluteString,
            "t3code://threads/f9ec21de-85c7/bb6ba79b-d05b"
        )
    }

    func testNoLinkWithoutEnvironmentId() {
        XCTAssertNil(T3CodeSessions.threadURL(threadId: "bb6ba79b", environmentIdFile: idFile))
    }

    func testNoLinkForThreadIdThatCouldEscapeThePath() throws {
        try "f9ec21de".write(to: idFile, atomically: true, encoding: .utf8)
        XCTAssertNil(T3CodeSessions.threadURL(threadId: "../new", environmentIdFile: idFile))
        XCTAssertNil(T3CodeSessions.threadURL(threadId: "", environmentIdFile: idFile))
    }
}
