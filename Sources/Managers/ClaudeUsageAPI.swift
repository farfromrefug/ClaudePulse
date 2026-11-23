import Foundation
import Security

/// Reads the account's rate limits from Anthropic with the login Claude Code
/// already holds.
///
/// Claude Code's own `/usage` is this call. It keeps its OAuth login in the
/// macOS Keychain (`Claude Code-credentials`) — or in `~/.claude/.credentials.json`
/// where there is no Keychain — and Pulse only ever reads it, never refreshes
/// or writes it: Claude Code renews the token whenever it runs.
enum ClaudeUsageAPI {

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"

    static var credentialsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    enum Failure: Error, Equatable {
        case noLogin
        case expiredLogin
        case rejected(status: Int)
        case unreadable
    }

    // MARK: - Login

    /// The access token, or nil when Claude Code has no usable login here.
    static func accessToken(now: Date = Date(), file: URL? = nil) -> Result<String, Failure> {
        let raw = keychainPayload() ?? (try? Data(contentsOf: file ?? credentialsFileURL))
        guard let raw else { return .failure(.noLogin) }
        return token(in: raw, now: now)
    }

    static func token(in payload: Data, now: Date) -> Result<String, Failure> {
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = (oauth["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return .failure(.noLogin) }
        // Epoch milliseconds. A token past its time is refused anyway; waiting
        // for Claude Code to renew it beats a request that is certain to fail.
        if let expiresAt = oauth["expiresAt"] as? Double, expiresAt / 1_000 <= now.timeIntervalSince1970 {
            return .failure(.expiredLogin)
        }
        return .success(token)
    }

    private static func keychainPayload() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    // MARK: - Request

    static func request(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli/pulse (external, cli)", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func fetch(
        session: URLSession = .shared,
        now: Date = Date(),
        completion: @escaping (Result<UsageSnapshot, Failure>) -> Void
    ) {
        switch accessToken(now: now) {
        case .failure(let failure):
            completion(.failure(failure))
        case .success(let token):
            session.dataTask(with: request(token: token)) { data, response, _ in
                guard let http = response as? HTTPURLResponse, let data else {
                    return completion(.failure(.unreadable))
                }
                guard http.statusCode == 200 else {
                    return completion(.failure(.rejected(status: http.statusCode)))
                }
                guard let snapshot = decode(data, now: Date()) else {
                    return completion(.failure(.unreadable))
                }
                completion(.success(snapshot))
            }.resume()
        }
    }

    // MARK: - Response

    /// `five_hour` and `seven_day` carry `utilization` (already 0–100) and an
    /// ISO-8601 `resets_at`. Per-model weekly limits arrive as `limits` entries
    /// of kind `weekly_scoped`, named by the model they cover.
    static func decode(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        func window(utilization: Any?, resetsAt: Any?) -> RateLimitWindow? {
            guard let percent = (utilization as? NSNumber)?.doubleValue else { return nil }
            return RateLimitWindow(usedPercentage: percent, resetsAt: date(resetsAt))
        }
        func named(_ key: String) -> RateLimitWindow? {
            guard let entry = json[key] as? [String: Any] else { return nil }
            return window(utilization: entry["utilization"], resetsAt: entry["resets_at"])
        }

        var opus: RateLimitWindow?
        var sonnet: RateLimitWindow?
        for limit in json["limits"] as? [[String: Any]] ?? [] where limit["kind"] as? String == "weekly_scoped" {
            let model = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
            guard let reading = window(utilization: limit["percent"], resetsAt: limit["resets_at"]) else { continue }
            switch model?.lowercased() {
            case let name? where name.contains("opus"): opus = reading
            case let name? where name.contains("sonnet"): sonnet = reading
            default: break
            }
        }

        let snapshot = UsageSnapshot(
            fiveHour: named("five_hour"),
            sevenDay: named("seven_day"),
            sevenDayOpus: opus,
            sevenDaySonnet: sonnet,
            updatedAt: now
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
