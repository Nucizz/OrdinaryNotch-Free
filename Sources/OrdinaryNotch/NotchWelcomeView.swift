import SwiftUI

/// Native port of Chánh Đại's Apple Hello Effect. See Resources/AppleHello-LICENSE.txt.
struct NotchWelcomeView: View {
    let reduceMotion: Bool
    var getStarted: () -> Void = {}
    @State private var firstStroke: CGFloat = 0
    @State private var remainingStroke: CGFloat = 0
    @State private var ready = false
    @State private var animationID: UUID?

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                HelloLettering(firstStroke: true).trim(from: 0, to: reduceMotion ? 1 : firstStroke)
                    .stroke(.white, style: StrokeStyle(lineWidth: 14.8883 * 230 / 638, lineCap: .round, lineJoin: .round))
                HelloLettering(firstStroke: false).trim(from: 0, to: reduceMotion ? 1 : remainingStroke)
                    .stroke(.white, style: StrokeStyle(lineWidth: 14.8883 * 230 / 638, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 230, height: 230 * 200 / 638)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hello")
            Button("Get Started", action: getStarted)
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(WelcomeButtonStyle(reduceMotion: reduceMotion))
                .disabled(!reduceMotion && !ready)
                .accessibilityHint(ready || reduceMotion ? "Open Settings" : "Available when the greeting finishes")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: reduceMotion) {
            let id = UUID()
            animationID = id
            ready = reduceMotion
            firstStroke = reduceMotion ? 1 : 0
            remainingStroke = reduceMotion ? 1 : 0
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8)) { firstStroke = 1 }
            do { try await Task.sleep(for: .seconds(0.7)) } catch { return }
            guard !Task.isCancelled, animationID == id else { return }
            withAnimation(.easeInOut(duration: 2.8), completionCriteria: .removed) {
                remainingStroke = 1
            } completion: {
                guard animationID == id else { return }
                ready = true
            }
        }
        .onDisappear { animationID = nil }
    }
}

private struct WelcomeButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.black : Color.white.opacity(0.4))
            .frame(width: 116, height: 32)
            .background(isEnabled ? Color.white.opacity(configuration.isPressed ? 0.8 : 1) : Color.white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isEnabled)
    }
}

private struct HelloLettering: Shape {
    var firstStroke: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if firstStroke {
            p.move(to: CGPoint(x: 8.69214, y: 166.553))
            p.addCurve(to: CGPoint(x: 89.8191, y: 98.0295), control1: CGPoint(x: 36.2393, y: 151.239), control2: CGPoint(x: 61.3409, y: 131.548))
            p.addCurve(to: CGPoint(x: 120.122, y: 31.0026), control1: CGPoint(x: 109.203, y: 75.1488), control2: CGPoint(x: 119.625, y: 49.0228))
            p.addCurve(to: CGPoint(x: 101.759, y: 7.43883), control1: CGPoint(x: 120.37, y: 17.6036), control2: CGPoint(x: 113.836, y: 7.43883))
            p.addCurve(to: CGPoint(x: 74.7122, y: 40.9363), control1: CGPoint(x: 88.3598, y: 7.43883), control2: CGPoint(x: 79.9231, y: 17.6036))
            p.addCurve(to: CGPoint(x: 54.1166, y: 190.356), control1: CGPoint(x: 69.005, y: 66.5793), control2: CGPoint(x: 64.7866, y: 96.0036))
        } else {
            p.move(to: CGPoint(x: 55.1624, y: 181.135))
            p.addCurve(to: CGPoint(x: 107.963, y: 98.0479), control1: CGPoint(x: 60.6251, y: 133.114), control2: CGPoint(x: 81.4118, y: 98.0479))
            p.addCurve(to: CGPoint(x: 131.071, y: 128.817), control1: CGPoint(x: 123.844, y: 98.0479), control2: CGPoint(x: 133.937, y: 110.703))
            p.addCurve(to: CGPoint(x: 125.408, y: 163.06), control1: CGPoint(x: 129.457, y: 139.487), control2: CGPoint(x: 127.587, y: 150.405))
            p.addCurve(to: CGPoint(x: 152.122, y: 191.348), control1: CGPoint(x: 122.869, y: 178.941), control2: CGPoint(x: 130.128, y: 191.348))
            p.addCurve(to: CGPoint(x: 237.097, y: 145.915), control1: CGPoint(x: 184.197, y: 191.348), control2: CGPoint(x: 219.189, y: 173.523))
            p.addCurve(to: CGPoint(x: 245.928, y: 119.884), control1: CGPoint(x: 243.198, y: 136.509), control2: CGPoint(x: 245.68, y: 128.073))
            p.addCurve(to: CGPoint(x: 222.851, y: 93.8296), control1: CGPoint(x: 246.176, y: 104.996), control2: CGPoint(x: 237.739, y: 93.8296))
            p.addCurve(to: CGPoint(x: 189.6, y: 142.465), control1: CGPoint(x: 203.992, y: 93.8296), control2: CGPoint(x: 189.6, y: 115.17))
            p.addCurve(to: CGPoint(x: 239.208, y: 192.341), control1: CGPoint(x: 189.6, y: 171.745), control2: CGPoint(x: 205.481, y: 192.341))
            p.addCurve(to: CGPoint(x: 359.199, y: 75.8585), control1: CGPoint(x: 285.066, y: 192.341), control2: CGPoint(x: 335.86, y: 137.292))
            p.addCurve(to: CGPoint(x: 368.26, y: 31.1512), control1: CGPoint(x: 365.788, y: 58.513), control2: CGPoint(x: 368.26, y: 42.4065))
            p.addCurve(to: CGPoint(x: 352.131, y: 7.55823), control1: CGPoint(x: 368.26, y: 17.8057), control2: CGPoint(x: 364.042, y: 7.55823))
            p.addCurve(to: CGPoint(x: 325.829, y: 30.9129), control1: CGPoint(x: 340.469, y: 7.55823), control2: CGPoint(x: 332.777, y: 16.6141))
            p.addCurve(to: CGPoint(x: 309.203, y: 98.4549), control1: CGPoint(x: 317.688, y: 47.4967), control2: CGPoint(x: 311.667, y: 71.4162))
            p.addCurve(to: CGPoint(x: 349.936, y: 191.348), control1: CGPoint(x: 303, y: 166.301), control2: CGPoint(x: 316.896, y: 191.348))
            p.addCurve(to: CGPoint(x: 457.286, y: 75.6686), control1: CGPoint(x: 390, y: 191.348), control2: CGPoint(x: 434.542, y: 135.534))
            p.addCurve(to: CGPoint(x: 466.275, y: 31.1512), control1: CGPoint(x: 463.803, y: 58.513), control2: CGPoint(x: 466.275, y: 42.4065))
            p.addCurve(to: CGPoint(x: 450.146, y: 7.55823), control1: CGPoint(x: 466.275, y: 17.8057), control2: CGPoint(x: 462.057, y: 7.55823))
            p.addCurve(to: CGPoint(x: 423.844, y: 30.9129), control1: CGPoint(x: 438.484, y: 7.55823), control2: CGPoint(x: 430.792, y: 16.6141))
            p.addCurve(to: CGPoint(x: 407.218, y: 98.4549), control1: CGPoint(x: 415.703, y: 47.4967), control2: CGPoint(x: 409.682, y: 71.4162))
            p.addCurve(to: CGPoint(x: 444.416, y: 191.348), control1: CGPoint(x: 401.015, y: 166.301), control2: CGPoint(x: 414.911, y: 191.348))
            p.addCurve(to: CGPoint(x: 499.471, y: 138.402), control1: CGPoint(x: 473.874, y: 191.348), control2: CGPoint(x: 489.877, y: 165.67))
            p.addCurve(to: CGPoint(x: 544.935, y: 94.8221), control1: CGPoint(x: 508.955, y: 111.447), control2: CGPoint(x: 520.618, y: 94.8221))
            p.addCurve(to: CGPoint(x: 580.916, y: 137.75), control1: CGPoint(x: 565.035, y: 94.8221), control2: CGPoint(x: 580.916, y: 109.71))
            p.addCurve(to: CGPoint(x: 535.362, y: 192.341), control1: CGPoint(x: 580.916, y: 168.768), control2: CGPoint(x: 560.792, y: 192.093))
            p.addCurve(to: CGPoint(x: 499.774, y: 147.179), control1: CGPoint(x: 512.984, y: 192.589), control2: CGPoint(x: 498.285, y: 174.475))
            p.addCurve(to: CGPoint(x: 543.943, y: 94.8221), control1: CGPoint(x: 501.511, y: 116.907), control2: CGPoint(x: 519.873, y: 94.8221))
            p.addCurve(to: CGPoint(x: 578.682, y: 107.725), control1: CGPoint(x: 557.839, y: 94.8221), control2: CGPoint(x: 569.51, y: 100.999))
            p.addCurve(to: CGPoint(x: 630.047, y: 96.7186), control1: CGPoint(x: 603.549, y: 125.866), control2: CGPoint(x: 622.709, y: 114.656))
        }
        let scale = min(rect.width / 638, rect.height / 200)
        return p.applying(CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
