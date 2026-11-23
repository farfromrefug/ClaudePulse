import SwiftUI

/// Permission prompts held open by Pulse, with the buttons that answer them.
struct PermissionListView: View {
    let permissions: [PendingPermission]
    let sessionName: (String) -> String
    /// False for sessions Claude for Desktop runs: there is no terminal prompt
    /// waiting behind Pulse for them, so offering to defer to one is a dead end.
    let offersTerminalHandoff: (String) -> Bool
    let onDecision: (PendingPermission, PermissionDecision) -> Void
    let onFocusSession: (String) -> Void
    private let settings = PanelSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(permissions) { permission in
                PermissionRow(
                    permission: permission,
                    projectName: sessionName(permission.sessionId),
                    offersTerminalHandoff: offersTerminalHandoff(permission.sessionId),
                    onDecision: { onDecision(permission, $0) },
                    onFocusSession: { onFocusSession(permission.sessionId) }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(width: settings.contentWidth)
    }
}

struct PermissionRow: View {
    let permission: PendingPermission
    let projectName: String
    var offersTerminalHandoff: Bool = true
    let onDecision: (PermissionDecision) -> Void
    let onFocusSession: () -> Void
    private let settings = PanelSettings.shared

    /// Set by the row's own chevron, for the one prompt that needs more room
    /// than the size setting gives every prompt.
    @State private var expanded = false

    /// Options picked so far, per question, for a call that needs more than
    /// one click to answer.
    @State private var picks: [String: Set<String>] = [:]

    /// The size setting is the floor; expanding a single row lifts it.
    private var detailSize: ActionDetail {
        expanded ? .full : settings.actionDetail
    }

    private var detailText: String {
        detailSize.showsWholeInput ? permission.fullDetail : permission.detail
    }

    var body: some View {
        let s = settings.textSize.scale
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9 * s, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(permission.toolName)
                    .font(.system(size: 11 * s, weight: .semibold))
                    .foregroundStyle(.white)
                Text(projectName)
                    .font(.system(size: 9 * s))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if permission.hasMoreDetail || settings.actionDetail != .full {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9 * s, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 16, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "Show less" : "Show everything this call would do")
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(remaining(at: context.date))
                        .font(.system(size: 9 * s, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            if let questions = permission.questions {
                questionView(questions, scale: s)
            } else if !detailText.isEmpty {
                detailView(text: detailText, scale: s)
            }

            HStack(spacing: 5) {
                let words = permission.vocabulary
                if let questions = permission.questions {
                    // One question with one answer is answered by the click on
                    // it; anything bigger is sent once every question has one.
                    if !answersOnClick(questions) {
                        PermissionButton(title: "Send", tint: settings.accentColor, help: "Answer with the choices above") {
                            onDecision(.answer(chosenAnswers(for: questions)))
                        }
                        .opacity(isComplete(questions) ? 1 : 0.35)
                        .disabled(!isComplete(questions))
                    }
                } else {
                    PermissionButton(title: words.allow, tint: settings.accentColor) {
                        onDecision(.allow)
                    }
                }
                if permission.canAllowAlways {
                    PermissionButton(title: "Allow all", tint: settings.accentColor.opacity(0.75)) {
                        onDecision(.allowAlways)
                    }
                }
                PermissionButton(title: words.deny, tint: .red.opacity(0.8), help: words.denyHelp) {
                    onDecision(.deny)
                }
                Spacer(minLength: 0)
                if offersTerminalHandoff {
                    PermissionButton(
                        title: "Terminal",
                        tint: .white.opacity(0.25),
                        help: "Answer in the terminal instead"
                    ) {
                        onDecision(.deferToTerminal)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.orange.opacity(0.25), lineWidth: 0.5)
        )
        // The buttons swallow their own clicks, so this only fires on the rest
        // of the card — going to look at the session should not answer for it.
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { onFocusSession() }
        .help("Click to reveal this session — the buttons answer without leaving Pulse")
    }

    // MARK: - Questions

    private func answersOnClick(_ questions: [AskedQuestion]) -> Bool {
        questions.count == 1 && !questions[0].multiSelect
    }

    private func isComplete(_ questions: [AskedQuestion]) -> Bool {
        questions.allSatisfy { !(picks[$0.question] ?? []).isEmpty }
    }

    /// Labels in the order the options were offered, joined the way Claude
    /// Code joins the answer to a multi-select question.
    private func chosenAnswers(for questions: [AskedQuestion]) -> [String: String] {
        var answers: [String: String] = [:]
        for question in questions {
            let chosen = picks[question.question] ?? []
            answers[question.question] = question.options.map(\.label)
                .filter(chosen.contains)
                .joined(separator: ", ")
        }
        return answers
    }

    private func choose(_ label: String, for question: AskedQuestion, in questions: [AskedQuestion]) {
        if answersOnClick(questions) {
            onDecision(.answer([question.question: label]))
            return
        }
        var chosen = picks[question.question] ?? []
        if question.multiSelect {
            if chosen.contains(label) { chosen.remove(label) } else { chosen.insert(label) }
        } else {
            chosen = [label]
        }
        picks[question.question] = chosen
    }

    @ViewBuilder
    private func questionView(_ questions: [AskedQuestion], scale s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(questions, id: \.question) { question in
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.question)
                        .font(.system(size: 11 * s))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(question.options, id: \.label) { option in
                        QuestionOptionButton(
                            option: option,
                            selected: picks[question.question]?.contains(option.label) == true,
                            multiSelect: question.multiSelect
                        ) {
                            choose(option.label, for: question, in: questions)
                        }
                    }
                }
            }
        }
    }

    /// A compact prompt keeps its one-line summary; the larger sizes wrap and
    /// let the text run to the line budget the size setting allows.
    @ViewBuilder
    private func detailView(text: String, scale s: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10 * s, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(detailSize.lineLimit)
            .truncationMode(detailSize == .compact ? .middle : .tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func remaining(at date: Date) -> String {
        let seconds = max(0, Int(permission.expiresAt.timeIntervalSince(date).rounded()))
        return "\(seconds)s"
    }
}

private struct PermissionButton: View {
    let title: String
    let tint: Color
    var help: String?
    let action: () -> Void

    @State private var hovered = false
    private let settings = PanelSettings.shared

    var body: some View {
        let s = settings.textSize.scale
        Button(action: action) {
            Text(title)
                .font(.system(size: 10 * s, weight: .semibold))
                .foregroundStyle(.white.opacity(hovered ? 1.0 : 0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(hovered ? 0.55 : 0.3), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? "")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { hovered = hovering }
        }
    }
}

private struct QuestionOptionButton: View {
    let option: AskedQuestion.Option
    let selected: Bool
    let multiSelect: Bool
    let action: () -> Void

    @State private var hovered = false
    private let settings = PanelSettings.shared

    var body: some View {
        let s = settings.textSize.scale
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if multiSelect {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 10 * s))
                        .foregroundStyle(.white.opacity(selected ? 0.9 : 0.4))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 10 * s, weight: .semibold))
                        .foregroundStyle(.white.opacity(hovered || selected ? 1.0 : 0.85))
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 9 * s))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                settings.accentColor.opacity(selected ? 0.5 : (hovered ? 0.35 : 0.2)),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { hovered = hovering }
        }
    }
}
