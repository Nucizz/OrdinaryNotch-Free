import SwiftUI
import AppKit

/// Shared text roles. Small text uses a single readable size and weight throughout the app.
enum AppFont {
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12, weight: .regular)
    static let subtitle = Font.system(size: 11, weight: .regular)
    static let label = Font.system(size: 10, weight: .medium)
    static let section = Font.system(size: 11, weight: .semibold)
    static let detailTitle = section
    static let detailIcon = Font.system(size: 12, weight: .medium)
    static let button = Font.system(size: 11, weight: .medium)
    static let compact = Font.system(size: 10, weight: .medium)
    static let compactNS = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    static let value = Font.system(size: 16, weight: .medium, design: .rounded)
    static let counter = Font.system(size: 26, weight: .medium, design: .rounded)
    static let noticeTitle = Font.system(size: 17, weight: .semibold)
    static let settingsTitle = Font.system(size: 22, weight: .semibold)
    static let settingsBody = Font.system(size: 13, weight: .regular)
    static let symbol = Font.system(size: 12, weight: .medium)
    static let largeSymbol = Font.system(size: 16, weight: .medium)
    static let heroSymbol = Font.system(size: 28, weight: .medium)
}
