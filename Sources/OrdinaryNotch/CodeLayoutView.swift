import SwiftUI

struct CodeLayoutView: View {
    let channels: [CodeChannel]
    let dashboard: CodeDashboard
    let now: Date
    var visible = true
    var openTask: (CodeTask) -> Void
    var openProvider: (CodeProvider) -> Void
    var navigationError: String?
    var body: some View {
        if channels.count == 1, let channel = channels.first {
            CodeTabView(dashboard: dashboard.forChannel(channel), now: now, visible: visible,
                        openProvider: { openProvider(channel.provider) }, openTask: openTask, navigationError: navigationError)
        } else {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: NotchGeometry.detailContentGap) {
                    DetailHeading {
                        Image(systemName: "terminal")
                    } title: { Text("Tasks") } accessory: {
                        Text(dashboard.runningCount > 0 ? "\(dashboard.runningCount) running" : "")
                            .font(AppFont.label).foregroundStyle(.white.opacity(0.55))
                    }
                    ForEach(dashboard.visible) { task in
                        CodeTaskRow(task: task, dashboard: dashboard, now: now, openTask: openTask)
                    }
                    if dashboard.visible.isEmpty {
                        Text("No active tasks").font(AppFont.subtitle).foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    }
                    if let navigationError { Text(navigationError).font(AppFont.label).foregroundStyle(.orange) }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Rectangle().fill(.white.opacity(0.09)).frame(width: 1).padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(channels) { channel in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                CodeLogo(provider: channel.provider, working: false).frame(width: 12, height: 12)
                                Text(channel.title(in: channels)).font(AppFont.section)
                            }
                            CodeUsageView(usage: dashboard.forChannel(channel).usage, now: now)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}
