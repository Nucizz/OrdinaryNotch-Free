import SwiftUI

struct CodeTabView: View {
    let dashboard: CodeDashboard
    let now: Date
    var visible = true
    var openProvider: () -> Void = {}
    var openTask: (CodeTask) -> Void = { _ in }
    var navigationError: String?
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: NotchGeometry.detailContentGap) {
                DetailHeading {
                    CodeLogo(provider: dashboard.provider, working: false)
                } title: { Text(dashboard.provider.title) } accessory: {
                    if dashboard.provider == .claude { openButton }
                }
                if dashboard.visible.isEmpty {
                    Text("Ready when you are").font(AppFont.body)
                    Text("Start a task in \(dashboard.provider.title).").font(AppFont.subtitle).foregroundStyle(.white.opacity(0.55))
                } else {
                    ForEach(dashboard.visible) { task in taskRow(task) }
                }
                if let navigationError {
                    Text(navigationError).font(AppFont.label).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(.white.opacity(0.09)).frame(width: 1).padding(.vertical, 4)
            VStack(alignment: .leading, spacing: NotchGeometry.detailContentGap) {
                DetailHeading {
                    Image(systemName: "chart.bar")
                } title: {
                    if dashboard.runningCount > 0 {
                        Text("\(dashboard.runningCount) \(dashboard.runningCount == 1 ? "task" : "tasks") running").font(AppFont.section)
                    } else if dashboard.waitingCount > 0 {
                        Text("\(dashboard.waitingCount) awaiting input").font(AppFont.section)
                    } else { Text("Usage").font(AppFont.section) }
                } accessory: {
                    if dashboard.runningCount > 0 && dashboard.waitingCount > 0 {
                        Label("\(dashboard.waitingCount)", systemImage: "questionmark.bubble").font(AppFont.label)
                            .help("\(dashboard.waitingCount) tasks awaiting input")
                    }
                }
                CodeUsageView(usage: dashboard.usage, now: now, showsReset: true)
            }.frame(width: NotchGeometry.detailSidebarWidth, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .topLeading)
        }.frame(maxHeight: .infinity, alignment: .top)
    }
    private var openButton: some View {
        Button {
            openProvider()
        } label: {
            HStack(spacing: 7) {
                Text("Open Claude")
                Image(systemName: "arrow.up.right").font(AppFont.label)
            }.font(AppFont.button).padding(.horizontal, 8).frame(height: NotchGeometry.detailHeadingHeight)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(NotchHoverButtonStyle())
            .help("Open Claude in your browser")
    }
    private func taskRow(_ task: CodeTask) -> some View {
        CodeTaskRow(task: task, dashboard: dashboard, now: now, openTask: openTask)
    }
}

struct CodeTaskRow: View {
    let task: CodeTask
    let dashboard: CodeDashboard
    let now: Date
    var openTask: (CodeTask) -> Void
    var body: some View {
        Button { openTask(task) } label: {
            HStack(alignment: .top, spacing: 8) {
                CodeTaskStatusIcon(activity: task.activity, now: now).frame(width: 14, height: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.activity.title).font(AppFont.body).lineLimit(1).help(task.activity.title)
                    HStack(spacing: 4) {
                        if dashboard.tasks.contains(where: { $0.provider != task.provider }) {
                            CodeLogo(provider: task.provider, working: false).frame(width: 10, height: 10)
                        }
                        Text(task.activity.project ?? task.provider.title).lineLimit(1)
                        Spacer(minLength: 0)
                        if task.activity.isWorking, let elapsed = task.activity.elapsed(at: now) {
                            Text(CodexDuration.format(elapsed)).monospacedDigit().fixedSize()
                        }
                    }.font(AppFont.label).foregroundStyle(.white.opacity(0.55))
                }
            }.frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .contentShape(Rectangle())
        }.buttonStyle(NotchHoverButtonStyle())
            .disabled(task.conversationURL == nil)
            .help(task.conversationURL == nil ? "A link to this task is unavailable" : "Open \(task.activity.title)")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(task.provider.title), \(task.activity.title), \(task.activity.presentationLabel(at: now)), \(task.activity.project ?? "")")
            .accessibilityHint(task.conversationURL == nil ? "" : "Opens this conversation in its account’s app")
    }
}

struct CodeTaskStatusIcon: View {
    let activity: CodexActivity
    let now: Date
    var body: some View {
        Group {
            if activity.presentation(at: now) == .working {
                Image(systemName: "circle.dotted").foregroundStyle(.white)
            } else if activity.presentation(at: now) == .stopped {
                Image(systemName: "pause.circle").foregroundStyle(.white)
            } else { CodexStatusValue(activity: activity, now: now) }
        }.font(AppFont.symbol).help(activity.presentationLabel(at: now))
    }
}
