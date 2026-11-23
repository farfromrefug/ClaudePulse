import XCTest
@testable import ccpulse

final class QuestionAnswerTests: XCTestCase {

    private let input = """
    {"questions":[
      {"question":"Which one?","header":"Pick","multiSelect":false,
       "options":[{"label":"Allow","description":"go"},{"label":"Confirm","description":"yes"}]},
      {"question":"Which extras?","header":"Extras","multiSelect":true,
       "options":[{"label":"A","description":"a"},{"label":"B","description":"b"}]}
    ]}
    """

    private func toolInput(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testParsesQuestionsAndOptions() throws {
        let questions = try XCTUnwrap(AskedQuestion.parse(try toolInput(input)))
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions[0].question, "Which one?")
        XCTAssertEqual(questions[0].options.map(\.label), ["Allow", "Confirm"])
        XCTAssertFalse(questions[0].multiSelect)
        XCTAssertTrue(questions[1].multiSelect)
    }

    func testPartlyUnderstoodCallIsLeftToTheTerminal() throws {
        let broken = try toolInput("""
        {"questions":[{"question":"Ok?","options":[{"label":"Yes"}]},{"question":"No options"}]}
        """)
        XCTAssertNil(AskedQuestion.parse(broken))
        XCTAssertNil(AskedQuestion.parse(nil))
    }

    func testOnlyAskUserQuestionOffersChoices() throws {
        let value = try toolInput(input)
        func permission(_ tool: String) -> PendingPermission {
            PendingPermission(id: "1", sessionId: "s", toolName: tool, toolInput: value,
                              suggestions: [], timeout: 60, responder: { _ in })
        }
        XCTAssertNotNil(permission("AskUserQuestion").questions)
        XCTAssertNil(permission("Bash").questions)
    }

    func testAnswerHandsTheInputBackWithAnswersFilledIn() throws {
        let value = try toolInput(input)
        let output = SessionManager.hookOutput(
            for: .answer(["Which one?": "Allow"]), suggestions: [], toolInput: value
        )
        let hook = try XCTUnwrap(output["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["hookEventName"] as? String, "PermissionRequest")
        let decision = try XCTUnwrap(hook["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        let updated = try XCTUnwrap(decision["updatedInput"] as? [String: Any])
        XCTAssertEqual((updated["questions"] as? [Any])?.count, 2)
        XCTAssertEqual((updated["answers"] as? [String: String])?["Which one?"], "Allow")
    }
}
