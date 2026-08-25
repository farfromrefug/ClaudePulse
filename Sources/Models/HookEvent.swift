import Foundation

struct HookEvent: Decodable {
    let sessionId: String
    let hookEventName: String
    let cwd: String?
    let toolName: String?
    let notificationType: String?
    let prompt: String?
    let toolInput: JSONValue?
    let toolUseId: String?
    let permissionSuggestions: [JSONValue]?
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
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case permissionSuggestions = "permission_suggestions"
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
