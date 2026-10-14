import SwiftUI

/// Settings and the lock screen share the same content, spacing and controls.
struct LockScreenActivityView: View {
    let snapshot: LockScreenActivitySnapshot
    var lockScreenAppearance = false
    var pendingAction: String?
    var action: (LockScreenActivityAction) -> Void = { _ in }
    var availableOutputs: () -> [AudioOutput.Device] = { [] }
    var selectOutput: (AudioOutput.Device, MusicContentIdentity) -> Bool = { _, _ in false }
    @State private var outputError: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: LockScreenActivityLayout.cardSpacing) {
                        ForEach(snapshot.rows) { row in
                            activity(row)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18).padding(.vertical, 14)
                                .frame(minHeight: row.preferredHeight, alignment: .center)
                                .modifier(LockScreenActivityCardSurface())
                                .accessibilityElement(children: .contain)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .frame(minHeight: max(0, viewport.size.height - LockScreenActivityLayout.scrollEdgeHeight * 2), alignment: .bottom)
                    .padding(.horizontal, LockScreenActivityLayout.edgeInset)
                    .padding(.vertical, LockScreenActivityLayout.scrollEdgeHeight)
                    .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.2), value: snapshot.rows.map(\.id))
                }.scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.never)
                    .modifier(LockScreenActivityScrollEdges())
            }
            if let pendingAction {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").accessibilityHidden(true)
                    Text(pendingAction)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Cancel") { action(.cancelOpen) }
                }.font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .modifier(LockScreenActivityCardSurface())
                    .padding(.horizontal, LockScreenActivityLayout.edgeInset)
                    .padding(.bottom, LockScreenActivityLayout.edgeInset)
            }
        }
        .modifier(LockScreenNativeButtons())
        .controlSize(.regular)
        .foregroundStyle(.primary)
        .environment(\.colorScheme, lockScreenAppearance ? .dark : colorScheme)
        .onChange(of: snapshot.rows.first(where: { $0.kind == .media })?.media?.identity) { _, _ in
            outputError = nil
        }

    }

    @ViewBuilder private func activity(_ row: LockScreenActivityRow) -> some View {
        switch row.kind {
        case .media: media(row)
        case .codex: code(row)
        case .timer, .stopwatch: clock(row)
        }
    }

    private func media(_ row: LockScreenActivityRow) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Group {
                    if let artwork = row.artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Rectangle().fill(.quaternary)
                            Image(systemName: "music.note").font(.title).foregroundStyle(.secondary)
                        }
                    }
                }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.headline).lineLimit(1).help(row.title)
                    Text(row.subtitle).font(.body).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                LockScreenPlaybackWaveform(playing: row.media?.isPlaying == true)
            }
            if let media = row.media {
                LockScreenMediaTimeline(media: media, value: row.value) { seconds, identity in
                    action(.seek(seconds, identity))
                }
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 32, height: 32).accessibilityHidden(true)
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    mediaButton("Previous track", symbol: "backward.end.fill", command: .previous, row: row)
                    mediaButton(row.media?.isPlaying == true ? "Pause" : "Play", symbol: row.media?.isPlaying == true ? "pause.fill" : "play.fill",
                        command: .playpause, row: row)
                    mediaButton("Next track", symbol: "forward.end.fill", command: .next, row: row)
                }
                Spacer(minLength: 0)
                Group {
                    if let media = row.media {
                        LockScreenAudioOutputButton(media: media, availableOutputs: availableOutputs) { device in
                            outputError = selectOutput(device, media.identity) ? nil
                                : "Couldn’t select this output. It may have disconnected."
                        }
                        .id(media.identity)
                    } else {
                        Color.clear.accessibilityHidden(true)
                    }
                }.frame(width: 32, height: 32)
            }
            if let outputError {
                Text(outputError).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func mediaButton(_ title: String, symbol: String, command: LockScreenActivityAction.MediaCommand,
                             row: LockScreenActivityRow) -> some View {
        Button {
            if let identity = row.media?.identity { action(.media(command, identity)) }
        } label: {
            Label(title, systemImage: symbol)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }.labelStyle(.iconOnly)
            .buttonStyle(LockScreenPlayerButtonStyle())
            .disabled(row.media == nil)
            .help(title)
    }

    private func code(_ row: LockScreenActivityRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label([row.code?.provider, row.code?.account].compactMap { $0 }.joined(separator: " · "), systemImage: "terminal")
                    .foregroundStyle(.secondary)
                Spacer()
                if !row.subtitle.isEmpty {
                    Label(row.subtitle, systemImage: row.code?.statusSymbol ?? "hammer.fill")
                        .foregroundStyle(row.code?.needsInput == true ? Color.orange : Color.secondary)
                        .lineLimit(1)
                }
            }.font(.caption)
            Text(row.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let detail = row.code?.detail, !detail.isEmpty {
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let fraction = row.progress, fraction.isFinite {
                ProgressView(value: min(1, max(0, fraction))).controlSize(.small)
                    .accessibilityLabel("Task progress")
            }
            elapsed(row)
        }
    }

    private func elapsed(_ row: LockScreenActivityRow) -> some View {
        HStack(spacing: 4) {
            if !row.value.isEmpty {
                Image(systemName: "clock").foregroundStyle(.secondary)
                Text(row.value).monospacedDigit()
            }
        }.font(.body).fixedSize().accessibilityLabel("Elapsed \(row.value)")
    }

    private func clock(_ row: LockScreenActivityRow) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(row.title, systemImage: row.kind.symbol)
                        .font(.headline).lineLimit(1).help(row.title)
                    Text([row.subtitle, row.clockDetail].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(row.value).font(.title)
                    .monospacedDigit().foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.65)
                Button { action(.open(row.id)) } label: {
                    Label("Unlock to open \(row.title) in Clock", systemImage: "arrow.up.forward.app")
                }.labelStyle(.iconOnly)
                    .help("Open Clock after unlocking")
            }
            if let fraction = row.progress, fraction.isFinite {
                ProgressView(value: min(1, max(0, fraction))).tint(.orange).controlSize(.small)
                    .accessibilityLabel("Timer progress")
            }
        }
    }

    private func export(_ row: LockScreenActivityRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(row.title, systemImage: row.kind.symbol).font(.headline)
                Spacer()
                Text(row.value).monospacedDigit()
            }
            Text(row.subtitle).font(.callout).foregroundStyle(.secondary)
            if let fraction = row.progress, fraction.isFinite {
                ProgressView(value: min(1, max(0, fraction))).controlSize(.small)
                    .accessibilityLabel("Export progress")
            }
        }
    }

}

/// Native button semantics with an icon-only surface for the player.
private struct LockScreenPlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(LockScreenPlayerControlEffect(pressed: configuration.isPressed))
    }
}

struct LockScreenPlayerControlEffect: ViewModifier {
    var pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .scaleEffect(reduceMotion || !enabled ? 1 : (pressed ? 0.90 : (hovered ? 1.10 : 1)))
            .opacity(enabled ? (pressed ? 0.7 : 1) : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
            .onHover { hovered = $0 }
    }
}

private struct LockScreenPlaybackWaveform: View {
    var playing: Bool
    @State private var visible = false

    var body: some View {
        Waveform(active: playing, visible: visible)
            .frame(width: 40, height: 32)
            .onAppear { visible = true }
            .onDisappear { visible = false }
    }
}

/// Apple draws the controls, including their glass, hover and pressed states.
private struct LockScreenNativeButtons: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct LockScreenActivityCardSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct LockScreenActivityPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let content = NSHostingView(rootView: LockScreenActivityView(snapshot: .preview))
        content.sizingOptions = []
        // Scrolling works in the preview; sample controls have no side effects.
        return content
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
