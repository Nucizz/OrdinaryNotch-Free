import SwiftUI

/// Short content transitions sit inside the existing notch surface spring.
enum NotchMotion {
    static func activity(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.46, dampingFraction: 0.76)
    }
    static func content(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.42, dampingFraction: 0.82)
    }
    static func replacement(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 5)),
            removal: .opacity.combined(with: .offset(y: -3)))
    }
    static func compact(expanded: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.10) }
        return expanded ? .easeOut(duration: 0.08) : activity(reduceMotion: false).delay(0.12)
    }
    static func header(expanded: Bool, reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.10 : (expanded ? 0.18 : 0.10))
            .delay(reduceMotion || !expanded ? 0 : 0.035)
    }
    static func details(expanded: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.10) }
        return expanded ? .spring(response: 0.42, dampingFraction: 0.82).delay(0.04) : .easeOut(duration: 0.12)
    }
}
