import SwiftUI

struct AgentPromptView: View {
    @ObservedObject var model: AgentActionViewModel
    let prompt: AgentPrompt
    let openTask: (CodeTask) -> Bool
    var maximumHeight: CGFloat = .infinity
    var navigationError: String? = nil
    @State private var measured: [String: CGFloat] = [:]
    @State private var navigationAttempted = false
    @State private var answers: [String: String] = [:]
    @State private var writtenAnswers: [String: String] = [:]
    @State private var questionIndex = 0
    @State private var selected: Int? = nil
    @State private var multipleSelections: [String: Set<Int>] = [:]
    @FocusState private var editing: Bool
    @FocusState private var promptFocused: Bool
    private var question: AgentQuestion? { prompt.questions.indices.contains(questionIndex) ? prompt.questions[questionIndex] : nil }
    private var canSend: Bool {
        prompt.questions.allSatisfy { !(answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 12) {
                header
                if prompt.questions.isEmpty { Divider() }
            }
                .promptMeasure("header")
            ScrollViewReader { proxy in
                ScrollView {
                    promptContent.fixedSize(horizontal: false, vertical: true)
                        .id("question-top")
                        .promptMeasure("content")
                }
                .promptScrollEdgesHidden()
                .onChange(of: selected) { _, index in
                    if let index { proxy.scrollTo(index) }
                }
                .onChange(of: questionIndex) { _, _ in proxy.scrollTo("question-top", anchor: .top) }
            }
            .frame(height: min(measured["content"] ?? 24, max(44, maximumHeight - (measured["header"] ?? 48) - (measured["footer"] ?? 100) - 40)))
            VStack(alignment: .leading, spacing: 10) {
                if let question { answerField(question) }
                if let error = model.error ?? (navigationAttempted ? navigationError : nil) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if prompt.questions.isEmpty { Divider() }
                footer
            }.fixedSize(horizontal: false, vertical: true).promptMeasure("footer")
        }
        .tint(.white)
        .controlSize(.large)
        .padding(.bottom, 4)
        .fixedSize(horizontal: false, vertical: true)
        .promptMeasure("total")
        .onPreferenceChange(AgentPromptMeasureKey.self) { values in
            if measured != values { measured = values }
            if let height = values["total"] { model.measurePrompt(id: prompt.id, height: height + 16) }
        }
        .focusable().focusEffectDisabled().focused($promptFocused)
        .simultaneousGesture(TapGesture().onEnded { model.focus(); if !editing { promptFocused = true } })
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space, .return, .escape], phases: .down) { key in
            guard !model.sending else { return .handled }
            guard key.modifiers.isEmpty else { return .ignored }
            if prompt.questions.isEmpty && prompt.kind != .handoff {
                if key.key == .escape { model.submit(AgentAnswer(approve: false)); return .handled }
                if key.key == .return && prompt.canApprove { model.submit(AgentAnswer(approve: true)); return .handled }
                return .ignored
            }
            if key.key == .escape { model.later(); return .handled }
            if editing && key.key == .return { advanceOrSend(); return .handled }
            guard !editing, let question else { return .ignored }
            if key.key == .leftArrow || key.key == .rightArrow {
                questionIndex = min(max(0, questionIndex + (key.key == .rightArrow ? 1 : -1)), prompt.questions.count - 1)
                selected = nil; return .handled
            }
            if key.key == .space {
                if let selected { choose(selected); return .handled }
                return .ignored
            }
            if key.key == .return {
                if !question.multiple, let selected { choose(selected) }
                else { advanceOrSend() }
                return .handled
            }
            guard !question.options.isEmpty else { return .ignored }
            let delta = key.key == .downArrow ? 1 : -1
            let index = ((selected ?? (delta > 0 ? -1 : 0)) + delta + question.options.count) % question.options.count
            // Browsing choices must never send an answer. Click, a number key,
            // Space or Return explicitly activates the highlighted option.
            selected = index
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { key in
            guard key.modifiers.isEmpty, !editing, !model.sending, let number = Int(key.characters), number > 0,
                  let question, question.options.indices.contains(number - 1) else { return .ignored }
            choose(number - 1)
            return .handled
        }
    }
    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let question {
                Text(question.title).font(.system(size: 13, weight: .semibold)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !question.options.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                            Button { choose(index) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .frame(width: 24, height: 24)
                                        .background(isChosen(option) ? Color.black.opacity(0.08) : Color.white.opacity(0.1),
                                                    in: RoundedRectangle(cornerRadius: 6))
                                    optionLabel(question, index: index, option: option)
                                    if isChosen(option) {
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                                            .frame(height: 24).accessibilityHidden(true)
                                    }
                                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(NotchButtonStyle(isChosen(option) ? .selected : .standard,
                                outlined: selected == index, padded: false, scalesOnHover: false))
                            .disabled(model.sending)
                            .id(index)
                            .notchHint("\(question.multiple ? "Select" : "Answer") \(option)")
                            .accessibilityLabel("\(index + 1). \(option)")
                            .accessibilityIdentifier("agent-option-\(question.id)-\(index)")
                            .accessibilityValue(isChosen(option) ? "Selected" : "Not selected")
                            .accessibilityHint(question.multiple ? "Select any choices, then press Return to continue." :
                                "Answers this question immediately.\(index < 9 ? " Shortcut: \(index + 1)." : "")")
                        }
                    }
                }
            } else {
                Text(prompt.kind == .handoff ? "Continue in the app" : "Allow this action?")
                    .font(.system(size: 13, weight: .semibold))
                Text(prompt.detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                if let scope = prompt.alwaysAllowScope {
                    Text("Always Allow applies to: " + scope).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if prompt.kind != .handoff {
                    Text("A reusable permission isn’t available for this action.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 2)
    }

    private func answerField(_ question: AgentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(question.options.isEmpty ? "Your Answer" : "Other Answer")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !question.options.isEmpty {
                    Text(shortcutHint).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
            TextField("Type an answer…", text: Binding(get: { writtenAnswers[question.id] ?? "" }, set: { writtenAnswers[question.id] = $0; answers[question.id] = $0; selected = nil; multipleSelections.removeValue(forKey: question.id) }), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...3)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(editing ? 0.65 : 0.16), lineWidth: 1))
                .focused($editing).accessibilityLabel("Your answer")
                .onSubmit { advanceOrSend() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            CodeLogo(provider: prompt.task.provider, working: false).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(prompt.task.provider == .codex ? "Codex" : "Claude") · \(prompt.accountTitle)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Button { openSource() } label: {
                    HStack(spacing: 5) {
                        Text(prompt.task.activity.taskName ?? prompt.task.activity.title).lineLimit(1)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    }.font(.system(size: 13, weight: .semibold))
                }.buttonStyle(NotchButtonStyle(.plain)).foregroundStyle(.white).disabled(model.isPreviewing).notchHint(model.isPreviewing ? "Sample task" : "Open this task")
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(model.isPreviewing ? "Developer preview" : prompt.questions.isEmpty ? (prompt.kind == .handoff ? "Action needed" : "Access request") : "Question \(questionIndex + 1) of \(prompt.questions.count)")
                    .font(.system(size: 11, weight: .medium))
                if model.prompts.count > 1 { Text("\(model.prompts.count) waiting").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }

    private func optionLabel(_ question: AgentQuestion, index: Int, option: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(option).font(.system(size: 12, weight: .medium))
            if question.descriptions.indices.contains(index), !question.descriptions[index].isEmpty {
                Text(question.descriptions[index]).font(.system(size: 11)).opacity(0.65)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .disabled(model.sending)
    }

    private var shortcutHint: String {
        if prompt.kind == .handoff { return "Continue with the full request in the app." }
        if prompt.questions.isEmpty { return "Return to allow · Esc to deny" }
        let count = min(question?.options.count ?? 0, 9)
        let numbers = count > 1 ? "1–\(count)" : "1"
        let action = questionIndex < prompt.questions.count - 1 ? "next" : "send"
        if question?.multiple == true { return "\(numbers) toggle · Return \(action)" }
        return "\(numbers) answer · ↑↓ browse"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if prompt.questions.isEmpty && prompt.kind != .handoff {
                NotchActionButton(title: "Always Allow", hint: prompt.alwaysAllowScope ?? "A reusable permission is not available for this action") {
                    model.submit(AgentAnswer(approve: true, alwaysAllow: true))
                }.disabled(prompt.alwaysAllowPayload == nil)
            } else {
                NotchActionButton(title: "Later", shortcut: prompt.questions.isEmpty ? nil : "⎋", hint: "Leave this request pending", action: model.later)
            }
            if model.sending { ProgressView().controlSize(.small).accessibilityLabel("Sending response") }
            Spacer(minLength: 8)
            if !prompt.questions.isEmpty {
                if questionIndex > 0 {
                    NotchActionButton(title: "Back", hint: "Go to the previous question") { questionIndex -= 1; selected = nil }
                }
                NotchActionButton(title: questionIndex < prompt.questions.count - 1 ? "Next" : "Send", prominent: true, shortcut: "↩", hint: questionIndex < prompt.questions.count - 1 ? "Go to the next question" : "Send your answers to the agent", action: advanceOrSend)
                    .disabled((answers[question?.id ?? ""] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if prompt.kind == .handoff {
                NotchActionButton(title: "Open Task…", prominent: true, hint: "Open this task in its app", action: openSource)
            } else {
                NotchActionButton(title: "Deny", shortcut: "⎋", hint: "Deny this action") { model.submit(AgentAnswer(approve: false)) }
                NotchActionButton(title: "Allow", prominent: true, shortcut: "↩", hint: "Allow this action once") { model.submit(AgentAnswer(approve: true)) }
                    .disabled(!prompt.canApprove)
            }
        }.disabled(model.sending)
    }

    private func openSource() {
        navigationAttempted = true
        if openTask(prompt.task) { model.later() }
    }
    private func isChosen(_ option: String) -> Bool {
        guard let question else { return false }
        if question.multiple, let index = question.options.firstIndex(of: option) { return multipleSelections[question.id]?.contains(index) == true }
        return answers[question.id] == option
    }
    private func choose(_ index: Int) {
        guard !model.sending, let question, question.options.indices.contains(index) else { return }
        selected = index; editing = false; promptFocused = true
        writtenAnswers[question.id] = ""
        let option = question.options[index]
        if question.multiple {
            var indices = multipleSelections[question.id] ?? []
            if indices.contains(index) { indices.remove(index) } else { indices.insert(index) }
            multipleSelections[question.id] = indices
            answers[question.id] = indices.sorted().map { question.options[$0] }.joined(separator: ", ")
        } else {
            answers[question.id] = option
            advanceOrSend()
        }
    }
    private func advanceOrSend() {
        guard !model.sending, let question, !(answers[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if questionIndex < prompt.questions.count - 1 { questionIndex += 1; selected = nil; editing = false }
        else if canSend { model.submit(AgentAnswer(answers: answers)) }
        else if let unanswered = prompt.questions.firstIndex(where: { (answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            questionIndex = unanswered; selected = nil; editing = false
        }
    }
}

private struct AgentPromptMeasureKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
private extension View {
    @ViewBuilder func promptScrollEdgesHidden() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectHidden() }
        else { self }
    }
    func promptMeasure(_ section: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: AgentPromptMeasureKey.self, value: [section: ceil(proxy.size.height)])
        })
    }
}
