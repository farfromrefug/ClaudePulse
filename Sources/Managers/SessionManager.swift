import Foundation

@Observable
class SessionManager {
    var sessions: [String: Session] = [:]
    var activeSessionId: String?
    private var stalenessTimer: Timer?

    init() {
        startStalenessCheck()
    }

    var activeSession: Session? {
        // Prefer the user-selected session, but auto-switch to a running one
        if let id = activeSessionId, let selected = sessions[id], selected.isActive {
            return selected
        }
        // Find any actively running session
        if let running = sessions.values.first(where: { $0.isActive }) {
            return running
        }
        // Fall back to user-selected or first
        if let id = activeSessionId, let selected = sessions[id] {
            return selected
        }
        return sessions.values.first
    }

    var activeSessionCount: Int {
        sessions.values.filter { $0.isActive }.count
    }

    var sortedSessions: [Session] {
        sessions.values.sorted { a, b in
            // Active sessions first, then by most recent event
            if a.isActive != b.isActive { return a.isActive }
            return a.lastEventTime > b.lastEventTime
        }
    }

    func handleEvent(_ event: HookEvent, connection: HookConnection) {
        // Nothing here defers a reply yet, so the hook is released at once.
        connection.respondEmpty()
        handleEvent(event)
    }

    func handleEvent(_ event: HookEvent) {
        if event.hookEventName == "SessionEnd" {
            sessions.removeValue(forKey: event.sessionId)
            if activeSessionId == event.sessionId {
                activeSessionId = sessions.keys.first
            }
            return
        }

        let session: Session
        if let existing = sessions[event.sessionId] {
            session = existing
        } else {
            session = Session(id: event.sessionId, cwd: event.cwd)
            sessions[event.sessionId] = session
            if activeSessionId == nil {
                activeSessionId = event.sessionId
            }
        }
        session.handleEvent(event)
    }

    func selectSession(_ id: String) {
        if sessions[id] != nil {
            activeSessionId = id
        }
    }

    private func startStalenessCheck() {
        stalenessTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkStaleness()
        }
    }

    private func checkStaleness() {
        let now = Date()
        for (id, session) in sessions {
            let elapsed = now.timeIntervalSince(session.lastEventTime)
            if elapsed > 1800 { // 30 min — remove
                sessions.removeValue(forKey: id)
                if activeSessionId == id {
                    activeSessionId = sessions.keys.first
                }
            } else if elapsed > 600 { // 10 min — mark stale
                session.state = .stale
            } else if session.isActive && elapsed > 30 { // 30 sec with no event — back to idle
                session.state = .idle
            }
        }
    }
}
