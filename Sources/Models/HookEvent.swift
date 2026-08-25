import Foundation

struct HookEvent: Decodable {
    let sessionId: String
    let hookEventName: String
    let cwd: String?
    let toolName: String?
    let notificationType: String?
    let prompt: String?
    let transcriptPath: String?
    let permissionMode: String?
    let message: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case toolName = "tool_name"
        case notificationType = "notification_type"
        case prompt
        case transcriptPath = "transcript_path"
        case permissionMode = "permission_mode"
        case message
        case reason
    }
}

enum SessionState: String {
    case idle
    case working
    case waitingForUser = "waiting_for_user"
    case stale
}
