import SwiftUI

/// Short content transitions sit inside the existing notch surface spring.
enum NotchMotion {
    static func content(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.10 : 0.24)
    }
    static func replacement(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 5)),
            removal: .opacity.combined(with: .offset(y: -3)))
    }
    static func compact(expanded: Bool, reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.10 : (expanded ? 0.08 : 0.16))
            .delay(reduceMotion || expanded ? 0 : 0.10)
    }
    static func header(expanded: Bool, reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.10 : (expanded ? 0.18 : 0.10))
            .delay(reduceMotion || !expanded ? 0 : 0.035)
    }
    static func details(expanded: Bool, reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.10 : (expanded ? 0.24 : 0.12))
            .delay(reduceMotion || !expanded ? 0 : 0.06)
    }
}
