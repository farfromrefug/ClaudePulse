import XCTest
@testable import ccpulse

final class LiveUsageTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Response

    func testDecodesWindowsAndResetTimes() throws {
        let body = """
        {"five_hour":{"utilization":28.0,"resets_at":"2027-01-15T10:00:00.000000+00:00"},
         "seven_day":{"utilization":95.5,"resets_at":"2027-01-18T08:00:00Z"},
         "limits":[
           {"kind":"weekly_scoped","percent":40,"resets_at":"2027-01-18T08:00:00Z","scope":{"model":{"display_name":"Opus"}}},
           {"kind":"weekly_scoped","percent":10,"scope":{"model":{"display_name":"Sonnet 4"}}},
           {"kind":"session","percent":99}]}
        """
        let snapshot = try XCTUnwrap(ClaudeUsageAPI.decode(Data(body.utf8), now: now))
        XCTAssertEqual(snapshot.fiveHour?.usedPercentage, 28)
        XCTAssertEqual(snapshot.sevenDay?.usedPercentage, 95.5)
        XCTAssertEqual(snapshot.sevenDayOpus?.usedPercentage, 40)
        XCTAssertEqual(snapshot.sevenDaySonnet?.usedPercentage, 10)
        XCTAssertNotNil(snapshot.fiveHour?.resetsAt)
        XCTAssertNotNil(snapshot.sevenDay?.resetsAt)
        XCTAssertEqual(snapshot.updatedAt, now)
    }

    func testNullWindowsAreLeftOut() throws {
        let body = #"{"five_hour":null,"seven_day":{"utilization":3,"resets_at":null}}"#
        let snapshot = try XCTUnwrap(ClaudeUsageAPI.decode(Data(body.utf8), now: now))
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.sevenDay?.usedPercentage, 3)
        XCTAssertNil(snapshot.sevenDay?.resetsAt)
    }

    func testEmptyOrUnreadableResponseIsNoReading() {
        XCTAssertNil(ClaudeUsageAPI.decode(Data("{}".utf8), now: now))
        XCTAssertNil(ClaudeUsageAPI.decode(Data("nope".utf8), now: now))
    }

    // MARK: - Login

    func testTokenIsReadFromTheCredentialsPayload() {
        let payload = #"{"claudeAiOauth":{"accessToken":" tok ","expiresAt":1900000000000}}"#
        XCTAssertEqual(try? ClaudeUsageAPI.token(in: Data(payload.utf8), now: now).get(), "tok")
    }

    func testExpiredTokenIsNotSent() {
        let payload = #"{"claudeAiOauth":{"accessToken":"tok","expiresAt":1700000000000}}"#
        XCTAssertEqual(ClaudeUsageAPI.token(in: Data(payload.utf8), now: now), .failure(.expiredLogin))
    }

    func testPayloadWithoutALoginIsRefused() {
        XCTAssertEqual(ClaudeUsageAPI.token(in: Data("{}".utf8), now: now), .failure(.noLogin))
        XCTAssertEqual(ClaudeUsageAPI.token(in: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8), now: now),
                       .failure(.noLogin))
    }

    func testRequestCarriesTheOAuthHeaders() {
        let request = ClaudeUsageAPI.request(token: "tok")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
    }

    // MARK: - Expiry

    func testWindowPastItsResetNoLongerReadsAsFull() {
        let snapshot = UsageSnapshot(
            fiveHour: RateLimitWindow(usedPercentage: 90, resetsAt: now.addingTimeInterval(-60)),
            sevenDay: RateLimitWindow(usedPercentage: 80, resetsAt: now.addingTimeInterval(3_600)),
            updatedAt: now.addingTimeInterval(-7_200)
        )
        let current = snapshot.current(now: now)
        XCTAssertEqual(current.fiveHour?.usedPercentage, 0)
        XCTAssertNil(current.fiveHour?.resetsAt)
        XCTAssertEqual(current.sevenDay?.usedPercentage, 80)
    }

    func testWindowWithUnknownResetIsKept() {
        let snapshot = UsageSnapshot(
            fiveHour: RateLimitWindow(usedPercentage: 90, resetsAt: nil), updatedAt: now
        )
        XCTAssertEqual(snapshot.current(now: now).fiveHour?.usedPercentage, 90)
    }
}
