import SwiftUI
import QuartzCore

/// Cached template artwork; the compositor animates opacity without a polling timer.
struct CodeLogo: View {
    let provider: CodeProvider
    let working: Bool
    var visible = true
    @Environment(\.notchReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var pulsing: Bool { working && visible && !reduceMotion && !systemReduceMotion }
    var body: some View {
        CodeLogoLayers(provider: provider, moving: pulsing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(provider.title + (working ? " working" : ""))
    }
}

/// An explicit layer animation survives SwiftUI's once-per-second elapsed-time updates.
struct CodeLogoLayers: NSViewRepresentable {
    let provider: CodeProvider
    let moving: Bool
    func makeNSView(context: Context) -> LogoView { LogoView() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LogoView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 12, height: proposal.height ?? 12)
    }
    func updateNSView(_ view: LogoView, context: Context) { view.update(provider: provider, moving: moving) }
    static func dismantleNSView(_ view: LogoView, coordinator: ()) { view.layer?.removeAllAnimations() }
    final class LogoView: NSImageView {
        private var provider: CodeProvider?
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        init() {
            super.init(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
            wantsLayer = true
            imageScaling = .scaleProportionallyUpOrDown
            contentTintColor = .white
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func update(provider: CodeProvider, moving: Bool) {
            if self.provider != provider { self.provider = provider; image = ProviderArtwork.image(provider) }
            guard let layer else { return }
            if moving {
                guard layer.animation(forKey: "workingPulse") == nil else { return }
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1; pulse.toValue = 0.25
                pulse.duration = 1.6; pulse.autoreverses = true; pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(pulse, forKey: "workingPulse")
            } else {
                layer.removeAnimation(forKey: "workingPulse")
                layer.opacity = 1
            }
        }
    }
}

enum ProviderArtwork {
    private static let images: [CodeProvider: NSImage] = Dictionary(uniqueKeysWithValues: CodeProvider.allCases.map { provider in
        let name = provider.rawValue + ".svg"
        var loaded: NSImage?
        if let url = Bundle.main.resourceURL?.appendingPathComponent("ProviderLogos").appendingPathComponent(name) {
            loaded = NSImage(contentsOf: url)
        }
        #if DEBUG
        if loaded == nil {
            let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/ProviderLogos")
            loaded = NSImage(contentsOf: development.appendingPathComponent(name))
        }
        #endif
        let image = loaded ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: provider.title)!
        image.isTemplate = true
        return (provider, image)
    })
    static func image(_ provider: CodeProvider) -> NSImage { images[provider]! }
}

struct CodexStatusValue: View {
    let activity: CodexActivity
    let now: Date
    var body: some View {
        Group {
            switch activity.presentation(at: now) {
            case .working:
                Text(activity.elapsed(at: now).map(CodexDuration.format) ?? "—").foregroundStyle(.white)
            case .complete: statusSymbol("checkmark.circle.fill", color: Color(nsColor: .systemGreen))
            case .input:
                statusSymbol(activity.statusSymbolName ?? "questionmark.bubble.fill",
                             color: activity.attention == "approval" ? Color(nsColor: .systemOrange) : .white)
            case .warning:
                statusSymbol(activity.statusSymbolName ?? "exclamationmark.triangle.fill",
                             color: activity.state == "failed" ? Color(nsColor: .systemRed) : Color(nsColor: .systemOrange))
            case .stopped, .idle: Text("—").foregroundStyle(.white)
            }
        }.help(activity.presentationLabel(at: now))
    }
    private func statusSymbol(_ name: String, color: Color) -> some View {
        Image(systemName: name).renderingMode(.template).symbolRenderingMode(.monochrome)
            .font(AppFont.title).foregroundStyle(color)
            .accessibilityLabel(activity.presentationLabel(at: now))
    }
}
