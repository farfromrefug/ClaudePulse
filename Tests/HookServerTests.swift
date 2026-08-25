import XCTest
@testable import ccpulse

final class HookServerTests: XCTestCase {
    private var server: HookServer?
    private var portFile: URL!

    override func setUp() {
        super.setUp()
        portFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccpulse-test-\(UUID().uuidString)/port")
    }

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    /// Posts a hook request and returns the response body.
    private func post(port: UInt16, body: String, headers: [String: String] = [:], timeout: TimeInterval = 5) throws -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook")!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = timeout

        var result: String?
        var failure: Error?
        let done = expectation(description: "response")
        URLSession.shared.dataTask(with: request) { data, _, error in
            failure = error
            result = data.map { String(decoding: $0, as: UTF8.self) }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: timeout + 5)
        if let failure { throw failure }
        return try XCTUnwrap(result)
    }

    private func startServer(_ onEvent: @escaping (HookEvent, HookConnection) -> Void) throws -> UInt16 {
        let server = HookServer(portRange: 19390...19399, portFileURL: portFile, onEvent: onEvent)
        try server.start()
        self.server = server
        return server.port
    }

    func testDeliversEventAndRespondsEmpty() throws {
        var received: HookEvent?
        let port = try startServer { event, connection in
            received = event
            connection.respondEmpty()
        }

        let body = try post(port: port, body: """
        {"session_id":"abc","hook_event_name":"PreToolUse","cwd":"/tmp","tool_name":"Bash"}
        """)

        XCTAssertEqual(body, "{}")
        XCTAssertEqual(received?.sessionId, "abc")
        XCTAssertEqual(received?.toolName, "Bash")
    }


    func testRespondsOnlyOnce() throws {
        let port = try startServer { _, connection in
            connection.respond(json: ["systemMessage": "first"])
            connection.respondEmpty()
        }

        let body = try post(port: port, body: #"{"session_id":"a","hook_event_name":"Stop"}"#)
        XCTAssertTrue(body.contains("first"), body)
    }

    /// A body split across TCP segments must still decode.
    func testReadsBodyLargerThanOneSegment() throws {
        var received: HookEvent?
        let port = try startServer { event, connection in
            received = event
            connection.respondEmpty()
        }

        let padding = String(repeating: "x", count: 300_000)
        _ = try post(port: port, body: """
        {"session_id":"big","hook_event_name":"PreToolUse","tool_name":"Write","prompt":"\(padding)"}
        """)

        XCTAssertEqual(received?.sessionId, "big")
        XCTAssertEqual(received?.prompt?.count, 300_000)
    }
}
