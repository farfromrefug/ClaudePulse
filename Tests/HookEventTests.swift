import XCTest
@testable import ccpulse

final class HookEventTests: XCTestCase {

    func testDecodeFullEvent() throws {
        let json = """
        {
            "session_id": "abc-123",
            "hook_event_name": "UserPromptSubmit",
            "cwd": "/Users/test/project",
            "tool_name": "Read",
            "notification_type": "info",
            "prompt": "fix the bug"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)
        XCTAssertEqual(event.sessionId, "abc-123")
        XCTAssertEqual(event.hookEventName, "UserPromptSubmit")
        XCTAssertEqual(event.cwd, "/Users/test/project")
        XCTAssertEqual(event.toolName, "Read")
        XCTAssertEqual(event.notificationType, "info")
        XCTAssertEqual(event.prompt, "fix the bug")
    }

    func testDecodeMinimalEvent() throws {
        let json = """
        {
            "session_id": "abc-123",
            "hook_event_name": "Stop"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)
        XCTAssertEqual(event.sessionId, "abc-123")
        XCTAssertEqual(event.hookEventName, "Stop")
        XCTAssertNil(event.cwd)
        XCTAssertNil(event.toolName)
        XCTAssertNil(event.notificationType)
        XCTAssertNil(event.prompt)
    }

    // MARK: - Editor sessions

    func testExtensionSessionIsEditorEvenWhenEditorWasStartedFromITerm() {
        let origin = TerminalOrigin(headers: [
            "x-pulse-term-program": "iTerm.app",
            "x-pulse-iterm-session": "w0t0p0:ABC",
            "x-pulse-vscode-ipc": "/Users/me/Library/Application Support/Code/1.9-main.sock"
        ])
        XCTAssertTrue(origin.isVSCodeFamily)
    }

    func testEntrypointNamesExtension() {
        XCTAssertTrue(TerminalOrigin(headers: ["x-pulse-entrypoint": "claude-vscode"]).isVSCodeFamily)
        XCTAssertFalse(TerminalOrigin(headers: ["x-pulse-entrypoint": "cli", "x-pulse-term-program": "iTerm.app"]).isVSCodeFamily)
    }

    func testEditorIsNamedByIpcHookPath() {
        XCTAssertEqual(SessionOpener.editorBundleId(forIpcHook: "/Users/me/Library/Application Support/Cursor/main.sock"),
                       "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(SessionOpener.editorBundleId(forIpcHook: "/Users/me/Library/Application Support/Code/main.sock"),
                       "com.microsoft.VSCode")
        XCTAssertEqual(SessionOpener.editorBundleId(forIpcHook: "/Users/me/Library/Application Support/Code - Insiders/main.sock"),
                       "com.microsoft.VSCodeInsiders")
        XCTAssertNil(SessionOpener.editorBundleId(forIpcHook: "/tmp/vscode-ipc.sock"))
    }
}
