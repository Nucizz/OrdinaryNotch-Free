import SwiftUI

/// The same Free tab content is rendered by the notch and its settings preview.
struct NotchTabContentView: View {
    let tab: NotchTab
    @ObservedObject var model: NotchViewModel
    var previewCamera: CameraViewModel?
    var body: some View {
        switch tab {
        case .overview:
            HStack(alignment: .top, spacing: model.isIsland ? 12 : 18) {
                MusicView(music: model.music, preferences: model.preferences).frame(maxWidth: .infinity)
                Rectangle().fill(.white.opacity(0.09)).frame(width: 1).padding(.vertical, 4)
                AgendaView(agenda: model.agenda, full: false).frame(width: model.isIsland ? 160 : NotchGeometry.detailSidebarWidth)
            }
        case .focus:
            FocusView(clock: model.clock, preferences: model.preferences, now: model.now, visible: model.expanded)
        case .shelf: FileShelfView(model: model.fileShelf)
        case .codex:
            CodeLayoutView(channels: model.codeChannels, dashboard: model.codeDashboard, now: model.now,
                visible: model.expanded, openTask: model.codexMonitor.openTask,
                openProvider: model.openCodeProvider, navigationError: model.codexMonitor.navigationError)
        case .mirror: MirrorView(camera: previewCamera ?? model.camera, openPhotoBooth: model.openPhotoBooth)
        case .fans: FanTabView(service: model.fans)
        }
    }
}
