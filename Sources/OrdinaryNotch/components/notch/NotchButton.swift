import SwiftUI

private struct NotchPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var notchIsPreview: Bool {
        get { self[NotchPreviewKey.self] }
        set { self[NotchPreviewKey.self] = newValue }
    }
}

enum NotchControlMetrics {
    static let size: CGFloat = 28
    static let cornerRadius: CGFloat = 8
    static let selectedOpacity = 0.14
}

/// A notch button can be square or wide, never taller than it is wide.
/// Measure the complete label so the rule also covers multiline and larger controls.
struct NotchButtonLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let label = subviews.first else { return .zero }
        let size = label.sizeThatFits(proposal)
        return CGSize(width: max(size.width, size.height), height: size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
            proposal: ProposedViewSize(bounds.size))
    }
}

/// Compact controls on the black notch surface. Settings use native macOS controls instead.
struct NotchButtonStyle: ButtonStyle {
    enum Appearance { case plain, standard, selected, prominent }
    var appearance: Appearance
    var cornerRadius: CGFloat
    var outlined: Bool
    var padded: Bool
    var scalesOnHover: Bool
    init(_ appearance: Appearance = .standard, cornerRadius: CGFloat = NotchControlMetrics.cornerRadius, outlined: Bool = false, padded: Bool = true, scalesOnHover: Bool = true) {
        self.appearance = appearance; self.cornerRadius = cornerRadius
        self.outlined = outlined; self.padded = padded
        self.scalesOnHover = scalesOnHover
    }
    init(prominent: Bool) { self.init(prominent ? .prominent : .standard) }

    func makeBody(configuration: Configuration) -> some View {
        NotchButtonLayout {
            configuration.label
                .font(AppFont.button)
                .padding(.horizontal, padded && appearance != .plain ? 10 : 0)
                .frame(minHeight: appearance == .plain || !padded ? nil : NotchControlMetrics.size)
        }
        .modifier(NotchButtonSurface(appearance: appearance, cornerRadius: cornerRadius,
            outlined: outlined, pressed: configuration.isPressed, scalesOnHover: scalesOnHover))
    }
}

/// Shared drawing for SwiftUI buttons and native press-and-hold input targets.
private struct NotchButtonSurface: ViewModifier {
    var appearance: NotchButtonStyle.Appearance
    var cornerRadius: CGFloat = NotchControlMetrics.cornerRadius
    var outlined = false
    var pressed = false
    var nativeFocused = false
    var scalesOnHover = true
    @Environment(\.isEnabled) private var enabled
    @Environment(\.notchIsPreview) private var preview
    @Environment(\.isFocused) private var focused
    @Environment(\.colorSchemeContrast) private var contrast

    private var filled: Bool { appearance == .selected || appearance == .prominent }
    private var fill: Color {
        switch appearance {
        case .plain: .clear
        case .standard: .white.opacity(0.10)
        case .selected: .white
        case .prominent: Color(nsColor: .systemOrange)
        }
    }
    func body(content: Content) -> some View {
        content
            .foregroundStyle(filled ? Color.black : Color.white)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(
                Color.white.opacity(focused || nativeFocused || outlined ? 0.9 : (appearance == .plain || filled ? 0 : (contrast == .increased ? 0.6 : 0.14))),
                lineWidth: focused || nativeFocused ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(enabled || preview ? (pressed ? 0.75 : 1) : 0.4)
            .modifier(NotchHoverEffect(pressed: pressed, cornerRadius: cornerRadius, scalesOnHover: scalesOnHover))
            .focusEffectDisabled()
    }
}

struct NotchIconButton: View {
    let symbol: String
    let label: String
    var value = ""
    var hint = ""
    var selected = false
    var width: CGFloat = NotchControlMetrics.size
    var height: CGFloat = NotchControlMetrics.size
    var tint: Color = .white
    var symbolFont: Font = AppFont.body
    var menuItems: [NotchButtonMenuItem] = []
    var menuLabel = "More options"
    var action: () -> Void
    @State private var pressed = false
    @State private var nativeFocused = false

    var body: some View {
        Group {
            if menuItems.isEmpty {
                Button(action: action) { icon }
                    .buttonStyle(NotchButtonStyle(.plain))
            } else {
                NotchButtonLayout { icon.accessibilityHidden(true) }
                    .overlay {
                        NotchPressAndHoldTarget(label: label, value: value, hint: hint,
                            menuLabel: menuLabel, menuItems: menuItems, action: action,
                            pressed: $pressed, focused: $nativeFocused)
                    }
                    .modifier(NotchButtonSurface(appearance: .plain, pressed: pressed, nativeFocused: nativeFocused))
            }
        }
        .notchHint(hint.isEmpty ? label : hint)
        .accessibilityLabel(label).accessibilityValue(value).accessibilityHint(hint)
    }

    private var icon: some View {
        Image(systemName: symbol).font(symbolFont).symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: max(height, width), height: height)
            .background(selected ? Color.white.opacity(NotchControlMetrics.selectedOpacity) : .clear,
                in: RoundedRectangle(cornerRadius: NotchControlMetrics.cornerRadius))
    }
}

/// Reuses the notch surface and native input target, with a menu on a normal click.
struct NotchMenuButton<Label: View>: View {
    var title: String
    var value: String
    var hint: String
    var appearance: NotchButtonStyle.Appearance = .standard
    @Binding var isPresented: Bool
    var items: () -> [NotchButtonMenuItem]
    @ViewBuilder var label: Label
    @State private var pressed = false
    @State private var focused = false

    var body: some View {
        NotchButtonLayout { label.accessibilityHidden(true) }
            .overlay {
                NotchPressAndHoldTarget(label: title, value: value, hint: hint,
                    menuLabel: title, menuItems: [], action: {}, menuOnClick: true,
                    loadMenuItems: items, menuVisibilityChanged: { isPresented = $0 },
                    pressed: $pressed, focused: $focused)
            }
            .modifier(NotchButtonSurface(appearance: appearance,
                pressed: pressed, nativeFocused: focused))
            .notchHint(hint)
    }
}
