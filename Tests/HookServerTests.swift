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

    func testParsesTerminalHeaders() throws {
        var received: HookEvent?
        let port = try startServer { event, connection in
            received = event
            connection.respondEmpty()
        }

        _ = try post(
            port: port,
            body: #"{"session_id":"abc","hook_event_name":"SessionStart"}"#,
            headers: [
                "X-Pulse-Term-Program": "iTerm.app",
                "X-Pulse-Iterm-Session": "w0t1p0:UUID-1"
            ]
        )

        XCTAssertEqual(received?.origin?.termProgram, "iTerm.app")
        XCTAssertEqual(received?.origin?.itermSessionId, "w0t1p0:UUID-1")
    }

    /// Env vars Claude Code cannot resolve arrive as empty strings; those must
    /// not be mistaken for a real terminal.
    func testEmptyHeadersProduceNoOrigin() throws {
        var received: HookEvent?
        let port = try startServer { event, connection in
            received = event
            connection.respondEmpty()
        }

        _ = try post(
            port: port,
            body: #"{"session_id":"abc","hook_event_name":"SessionStart"}"#,
            headers: ["X-Pulse-Term-Program": "", "X-Pulse-Iterm-Session": ""]
        )

        XCTAssertNil(received?.origin)
    }

    /// The whole point of the HTTP transport: a permission prompt can hold the
    /// request open and answer it later with a decision.
    func testDeferredPermissionResponse() throws {
        let port = try startServer { _, connection in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                connection.respond(json: SessionManager.hookOutput(for: .allow, suggestions: []))
            }
        }

        let body = try post(port: port, body: """
        {"session_id":"abc","hook_event_name":"PermissionRequest","tool_name":"Bash"}
        """)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let specific = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(specific["decision"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual(decision["behavior"] as? String, "allow")
    }

    func testRespondsOnlyOnce() throws {
        let port = try startServer { _, connection in
            connection.respond(json: SessionManager.hookOutput(for: .deny, suggestions: []))
            connection.respondEmpty()
        }

        let body = try post(port: port, body: #"{"session_id":"a","hook_event_name":"PermissionRequest"}"#)
        XCTAssertTrue(body.contains("deny"), body)
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
        {"session_id":"big","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"content":"\(padding)"}}
        """)

        XCTAssertEqual(received?.sessionId, "big")
        XCTAssertEqual(received?.toolInput?["content"]?.stringValue?.count, 300_000)
    }

    /// Claude Code hangs up on a hook it has stopped waiting for — a timeout,
    /// a session ending, a ^C. Writing the answer to that dead socket used to
    /// raise SIGPIPE and kill Pulse outright, leaving no crash report to
    /// explain it.
    ///
    /// The signal itself cannot be provoked from here — XCTest's host process
    /// already ignores SIGPIPE, so an unfixed build would survive this test
    /// while the app it ships dies. What is checked instead is the thing that
    /// keeps the app alive: the connection carries SO_NOSIGPIPE, so the write
    /// returns EPIPE, and answering a socket nobody is listening to leaves the
    /// server running.
    func testAnsweringAConnectionTheClientHungUpOnDoesNotKillTheProcess() throws {
        var held: HookConnection?
        let arrived = expectation(description: "hook arrived")
        // The liveness check at the end sends a second hook through the same
        // handler; only the first one is being waited for.
        arrived.assertForOverFulfill = false
        let lock = NSLock()
        let port = try startServer { _, connection in
            lock.lock()
            let isFirst = held == nil
            if isFirst { held = connection }
            lock.unlock()
            // The first hook is the one abandoned mid-flight; the one after it
            // is the liveness check and wants a normal answer.
            if isFirst { arrived.fulfill() } else { connection.respondEmpty() }
        }

        // A raw socket, so the request can be abandoned mid-flight the way a
        // cancelled hook abandons its own.
        let client = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(client, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                connect(client, raw, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connected, 0)

        let body = #"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash"}"#
        let request = """
        POST /hook HTTP/1.1\r
        Host: 127.0.0.1\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        _ = request.withCString { send(client, $0, strlen($0), 0) }
        wait(for: [arrived], timeout: 5)

        XCTAssertTrue(try XCTUnwrap(held).suppressesSIGPIPE,
                      "the accepted socket must report EPIPE rather than signalling")

        // The client gives up before the answer comes, exactly as a hook that
        // has timed out does.
        close(client)
        Thread.sleep(forTimeInterval: 0.2)
        held?.respondEmpty()

        // Still alive, and still answering — which is the whole point.
        let response = try post(port: port, body: #"{"session_id":"s2","hook_event_name":"Stop"}"#)
        XCTAssertNotNil(response)
    }
}
