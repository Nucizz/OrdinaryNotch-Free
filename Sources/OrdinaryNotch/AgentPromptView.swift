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
            VStack(spacing: 12) { header; Divider() }
                .promptMeasure("header")
            ScrollViewReader { proxy in
                ScrollView {
                    promptContent.fixedSize(horizontal: false, vertical: true)
                        .promptMeasure("content")
                }
                .onChange(of: selected) { _, index in
                    if let index { proxy.scrollTo(index) }
                }
            }
            .frame(height: min(measured["content"] ?? 24, max(44, maximumHeight - (measured["header"] ?? 48) - (measured["footer"] ?? 100) - 40)))
            VStack(alignment: .leading, spacing: 10) {
                if let question { answerField(question) }
                if let error = model.error ?? (navigationAttempted ? navigationError : nil) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
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
                if question.multiple, let selected { choose(selected); return .handled }
                return .ignored
            }
            if key.key == .return { advanceOrSend(); return .handled }
            guard !question.options.isEmpty else { return .ignored }
            let delta = key.key == .downArrow ? 1 : -1
            let index = ((selected ?? (delta > 0 ? -1 : 0)) + delta + question.options.count) % question.options.count
            if !question.multiple { choose(index) } else { selected = index }
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
                            .buttonStyle(AgentPromptButtonStyle(filled: isChosen(option), outlined: question.multiple && selected == index))
                            .disabled(model.sending)
                            .id(index)
                            .accessibilityLabel("\(index + 1). \(option)")
                            .accessibilityValue(isChosen(option) ? "Selected" : "Not selected")
                            .accessibilityHint(index < 9 ? "Press \(index + 1) to select, then Return to send." : "Select, then Return to send.")
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
                }.buttonStyle(.plain).foregroundStyle(.white).disabled(model.isPreviewing).help(model.isPreviewing ? "Sample task" : "Open this task")
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
        return "\(numbers) select · Return \(action)"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if prompt.questions.isEmpty && prompt.kind != .handoff {
                AgentPromptActionButton(title: "Always Allow") {
                    model.submit(AgentAnswer(approve: true, alwaysAllow: true))
                }.disabled(prompt.alwaysAllowPayload == nil)
                    .help(prompt.alwaysAllowScope ?? "A reusable permission is not available for this action")
            } else {
                AgentPromptActionButton(title: "Later", shortcut: prompt.questions.isEmpty ? nil : "⎋", action: model.later)
                    .help("Leave this request pending")
            }
            if model.sending { ProgressView().controlSize(.small).accessibilityLabel("Sending response") }
            Spacer(minLength: 8)
            if !prompt.questions.isEmpty {
                if questionIndex > 0 {
                    AgentPromptActionButton(title: "Back") { questionIndex -= 1; selected = nil }
                }
                AgentPromptActionButton(title: questionIndex < prompt.questions.count - 1 ? "Next" : "Send", prominent: true, shortcut: "↩", action: advanceOrSend)
                    .disabled((answers[question?.id ?? ""] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if prompt.kind == .handoff {
                AgentPromptActionButton(title: "Open Task…", prominent: true, action: openSource)
            } else {
                AgentPromptActionButton(title: "Deny", shortcut: "⎋") { model.submit(AgentAnswer(approve: false)) }
                AgentPromptActionButton(title: "Allow", prominent: true, shortcut: "↩") { model.submit(AgentAnswer(approve: true)) }
                    .disabled(!prompt.canApprove)
            }
        }.disabled(model.sending).help(shortcutHint)
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
        guard let question, question.options.indices.contains(index) else { return }
        selected = index; editing = false; promptFocused = true
        writtenAnswers[question.id] = ""
        let option = question.options[index]
        if question.multiple {
            var indices = multipleSelections[question.id] ?? []
            if indices.contains(index) { indices.remove(index) } else { indices.insert(index) }
            multipleSelections[question.id] = indices
            answers[question.id] = indices.sorted().map { question.options[$0] }.joined(separator: ", ")
        } else { answers[question.id] = option }
    }
    private func advanceOrSend() {
        guard !model.sending, let question, !(answers[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if questionIndex < prompt.questions.count - 1 { questionIndex += 1; selected = nil; editing = false }
        else if canSend { model.submit(AgentAnswer(answers: answers)) }
    }
}

/// Ordinary Notch controls keep native button semantics with monochrome states.
private struct AgentPromptActionButton: View {
    let title: String
    var prominent = false
    var shortcut: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let shortcut { Text(shortcut).font(.system(size: 11)).opacity(0.6).accessibilityHidden(true) }
            }.padding(.horizontal, 12).frame(minHeight: 32)
        }
        .buttonStyle(AgentPromptButtonStyle(filled: prominent))
        .keyboardShortcut(shortcut == "↩" ? KeyboardShortcut.defaultAction : (shortcut == "⎋" ? KeyboardShortcut.cancelAction : nil))
    }
}

private struct AgentPromptButtonStyle: ButtonStyle {
    var filled = false
    var outlined = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(filled ? Color.black : Color.white)
            .background(filled ? Color.white.opacity(configuration.isPressed ? 0.75 : 1) :
                            Color.white.opacity(configuration.isPressed ? 0.2 : (hovering ? 0.14 : 0.07)),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(focused || outlined ? 0.8 : (filled ? 0 : 0.14)), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.35)
            .onHover { hovering = $0 }
            .focusEffectDisabled()
    }
}

private struct AgentPromptMeasureKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
private extension View {
    func promptMeasure(_ section: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: AgentPromptMeasureKey.self, value: [section: ceil(proxy.size.height)])
        })
    }
}
