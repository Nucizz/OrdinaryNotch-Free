import Foundation
import Combine
import ActivityCore

@MainActor
final class AgentActionViewModel: ObservableObject {
    @Published private(set) var prompts: [AgentPrompt] = []
    @Published private(set) var error: String?
    @Published private(set) var sending = false
    @Published private var previewPrompt: AgentPrompt?
    var isPreviewing: Bool { previewPrompt != nil }
    func preview(_ sample: AgentPromptPreview) {
        guard !sending else { return }
        previewPrompt = sample.prompt
        measuredPrompt = nil; error = nil
        focus()
    }
    func dismissPreview() { previewPrompt = nil; error = nil }
    @Published private var measuredPrompt: (id: String, height: CGFloat)?
    var promptHeight: CGFloat {
        guard let current else { return 0 }
        if measuredPrompt?.id == current.id { return measuredPrompt!.height }
        return current.questions.first?.options.isEmpty == true ? 210 : 340
    }
    func measurePrompt(id: String, height: CGFloat) {
        guard current?.id == id, height.isFinite, height > 0 else { return }
        let value = ceil(height)
        guard measuredPrompt?.id != id || measuredPrompt?.height != value else { return }
        measuredPrompt = (id, value)
    }
    @Published private var deferred: Set<String> = []
    var current: AgentPrompt? { previewPrompt ?? prompts.first { !deferred.contains($0.id) } }
    var focus: () -> Void = {}
    private let claude = ClaudePromptService()
    private let codex = CodexPromptService()
    private let queue = DispatchQueue(label: "ordinary.agent-actions", qos: .utility)
    private var busy = false
    private var lastRefresh = Date.distantPast
    private var completed: Set<String> = []
    private var approvalFirstSeen: [String: Date] = [:]
    private var deferredClaudeTasks: Set<String> = []
    private static func taskKey(_ task: CodeTask) -> String { (task.profileID ?? "") + ":" + (task.threadID ?? task.id) }
    private var channels: [CodeChannel] = []
    private var configured: Set<String> = []
    private var enabled = true
    private var refreshGeneration = UUID()
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value; refreshGeneration = UUID(); lastRefresh = .distantPast
        if !value {
            claude.suspend() // Pending hooks fall through to their original prompt.
            prompts = []; approvalFirstSeen = [:]; deferred = []; deferredClaudeTasks = []; error = nil
        }
    }
    func refresh(tasks: [CodeTask], channels: [CodeChannel], now: Date = Date()) {
        guard enabled else { return }
        self.channels = channels
        guard !busy, now.timeIntervalSince(lastRefresh) >= 1 else { return }
        busy = true; lastRefresh = now
        let profiles = channels.filter { $0.provider == .claude }.map { ClaudeProfiles().profile($0.account) }
        claude.configure(profiles: profiles)
        deferredClaudeTasks.formIntersection(Set(tasks.filter { $0.activity.needsInput }.map(Self.taskKey)))
        let deferredClaude = deferredClaudeTasks
        let pendingTasks = tasks.filter { $0.provider == .codex && $0.shouldDisplay && $0.activity.needsInput }
        let codex = codex, claude = claude, generation = refreshGeneration
        let upgrades = profiles.filter { configured.insert($0.id).inserted }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/OrdinaryActivityBridge")
        queue.async { [weak self] in
            for profile in upgrades {
                let file = profile.root.appendingPathComponent("settings.json")
                // Upgrade only the already-enabled Ordinary Notch hooks.
                if ClaudeHookSetup.installed(at: file),
                   let data = try? Data(contentsOf: file), !String(decoding: data, as: UTF8.self).contains("--interactive") {
                    try? ClaudeHookSetup.install(executable: executable, at: file)
                }
            }
            let hooked = claude.prompts
            let otherClaude = tasks.filter { task in
                task.provider == .claude && task.shouldDisplay && task.activity.needsInput &&
                    !deferredClaude.contains((task.profileID ?? "") + ":" + (task.threadID ?? task.id)) &&
                    !hooked.contains { $0.task.threadID == task.threadID && $0.task.profileID == task.profileID }
            }.map { CodexPromptService.handoff($0) }
            let prompts = pendingTasks.flatMap { codex.prompts(for: $0) } + hooked + otherClaude
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.busy = false
                guard self.enabled, self.refreshGeneration == generation, self.channels == channels else { return }
                self.apply(self.stablePrompts(prompts))
            }
        }
    }
    /// A request resolved between refreshes must never flash an approval prompt.
    /// Every refresh comes from the live request channel, not a transcript guess.
    func stablePrompts(_ values: [AgentPrompt], now: Date = Date()) -> [AgentPrompt] {
        let ids = Set(values.map(\.id))
        approvalFirstSeen = approvalFirstSeen.filter { ids.contains($0.key) }
        return values.filter { prompt in
            guard prompt.task.provider == .codex, [.command, .fileChange, .handoff].contains(prompt.kind) else { return true }
            let firstSeen = approvalFirstSeen[prompt.id] ?? now
            approvalFirstSeen[prompt.id] = firstSeen
            return now.timeIntervalSince(firstSeen) >= 1
        }
    }
    func apply(_ values: [AgentPrompt]) {
        guard enabled else { return }
        let ids = Set(values.map(\.id))
        completed.formIntersection(ids); deferred.formIntersection(ids)
        let previous = current?.id
        var seen = Set<String>()
        let incoming = values.filter { !completed.contains($0.id) && seen.insert($0.id).inserted }
        let byID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        let retained = prompts.compactMap { byID[$0.id] }
        let retainedIDs = Set(retained.map(\.id))
        let filtered = retained + incoming.filter { !retainedIDs.contains($0.id) }
        if prompts != filtered { prompts = filtered }
        if current?.id != previous { error = nil }
    }
    func showPending() { deferred.removeAll(); focus() }
    func later() {
        if isPreviewing { dismissPreview(); return }
        guard let prompt = current, !sending else { return }
        if prompt.task.provider == .claude && prompt.kind != .handoff { try? claude.respond(prompt, answer: nil) }
        if prompt.task.provider == .claude { deferredClaudeTasks.insert(Self.taskKey(prompt.task)) }
        deferred.insert(prompt.id); error = nil
    }
    func submit(_ answer: AgentAnswer) {
        // Samples are local presentation state, never requests sent to an agent.
        if isPreviewing { dismissPreview(); return }
        guard let prompt = current, prompt.kind != .handoff, !sending else { return }
        sending = true; error = nil
        let claude = claude, codex = codex
        queue.async { [weak self] in
            let result: Result<Void, Error> = Result {
                if prompt.task.provider == .claude { try claude.respond(prompt, answer: answer) }
                else { try codex.respond(prompt, answer: answer) }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sending = false
                switch result {
                case .success:
                    if prompt.task.provider == .claude { self.deferredClaudeTasks.insert(Self.taskKey(prompt.task)) }
                    self.completed.insert(prompt.id); self.prompts.removeAll { $0.id == prompt.id }
                case .failure(let failure): if self.current?.id == prompt.id { self.error = failure.localizedDescription }
                }
            }
        }
    }
}
