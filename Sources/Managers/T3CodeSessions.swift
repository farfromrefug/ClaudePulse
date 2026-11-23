import Foundation

/// Finds the T3 Code thread behind a session.
///
/// T3 Code runs Claude Code through the SDK, so its sessions arrive as ordinary
/// hook events with `CLAUDE_CODE_ENTRYPOINT=t3-code` and `T3CODE_THREAD_ID` in
/// the environment. The app registers a `t3code://` scheme, and
/// `t3code://threads/<environment id>/<thread id>` navigates to a thread. The
/// environment id is not part of the session's environment; the app keeps it in
/// `<data dir>/userdata/environment-id`.
enum T3CodeSessions {

    static let bundleIdentifier = "com.t3tools.t3code"

    static var environmentIdURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".t3/userdata/environment-id")
    }

    /// A link that opens the thread, or nil when either id is unavailable.
    static func threadURL(threadId: String, environmentIdFile: URL? = nil) -> URL? {
        guard isSafeRouteComponent(threadId),
              let raw = try? String(contentsOf: environmentIdFile ?? environmentIdURL, encoding: .utf8) else {
            return nil
        }
        let environmentId = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeRouteComponent(environmentId) else { return nil }
        return URL(string: "t3code://threads/\(environmentId)/\(threadId)")
    }

    /// Both ids end up in a URL path, one of them straight from a hook header.
    private static func isSafeRouteComponent(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
