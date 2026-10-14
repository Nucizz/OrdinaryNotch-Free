import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    var symbol: String?
    var note: String?
    @ViewBuilder var content: Content
    init(_ title: String, symbol: String? = nil, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.symbol = symbol; self.note = note; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).foregroundStyle(SettingsStyle.secondary) }
                Text(title).accessibilityAddTraits(.isHeader)
                if let note { SettingsHelpButton(title: title, text: note) }
            }.font(.system(size: 13, weight: .semibold))
            GroupBox {
                VStack(spacing: 0) { content }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
            }
        }.id(title)
    }
}
struct SettingsDivider: View {
    var body: some View { Divider() }
}
struct SettingsRow<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var detail: String? = nil
    @ViewBuilder var content: Content
    init(_ title: String, symbol: String? = nil, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.symbol = symbol; self.detail = detail; self.content = content()
    }
    var body: some View {
        HStack(spacing: 10) {
            if let symbol { Image(systemName: symbol).foregroundStyle(SettingsStyle.secondary).frame(width: 18) }
            HStack(spacing: 4) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                if let detail { SettingsHelpButton(title: title, text: detail) }
            }
            Spacer(minLength: 16)
            content
        }.frame(minHeight: 24).padding(.vertical, 8)
    }
}
struct SettingsNumberRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    var step = 1
    var body: some View {
        SettingsRow(title) {
            SettingsNumberField(title: title, value: $value, range: range).frame(width: 64)
            Text(unit).foregroundStyle(SettingsStyle.secondary).frame(width: 22, alignment: .leading)
            Stepper(title, value: $value, in: range, step: step).labelsHidden().fixedSize().pointingCursor()
        }
    }
}

struct SettingsDurationRow: View {
    let title: String
    @Binding var seconds: Int
    var minimum = 1
    var maximum = DurationText.timerRange.upperBound
    var body: some View {
        SettingsRow(title) {
            SettingsDurationField(title: title, seconds: $seconds, minimum: minimum, maximum: maximum).frame(width: 160)
        }
    }
}
