import SwiftUI

/// One native, segmented HH:mm:ss editor for every configurable duration.
struct SettingsDurationField: NSViewRepresentable {
    let title: String
    @Binding var seconds: Int
    var minimum = DurationText.timerRange.lowerBound
    var maximum = DurationText.timerRange.upperBound
    var allowsNone = false
    @Environment(\.isEnabled) private var enabled
    static let midnight = Date(timeIntervalSinceReferenceDate: 0)

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinuteSecond
        picker.datePickerMode = .single
        picker.locale = Locale(identifier: "en_GB")
        picker.timeZone = TimeZone(secondsFromGMT: 0)
        picker.calendar = Calendar(identifier: .gregorian)
        picker.isBezeled = true
        picker.drawsBackground = true
        picker.controlSize = .large
        picker.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }
    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.isEnabled = enabled
        picker.setAccessibilityLabel(title)
        picker.toolTip = "Hours : minutes : seconds" + (allowsNone ? ". 00:00:00 means no timeout." : "")
        picker.minDate = Self.midnight.addingTimeInterval(Double(allowsNone ? 0 : minimum))
        picker.maxDate = Self.midnight.addingTimeInterval(Double(maximum))
        let value = Self.midnight.addingTimeInterval(Double(seconds))
        if picker.dateValue != value { picker.dateValue = value }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        SettingsNativeField.size(nsView, proposal: proposal)
    }
    final class Coordinator: NSObject {
        var parent: SettingsDurationField
        init(_ parent: SettingsDurationField) { self.parent = parent }
        @objc func changed(_ picker: NSDatePicker) {
            let proposed = Int(picker.dateValue.timeIntervalSince(SettingsDurationField.midnight).rounded())
            let value = min(parent.maximum, max(parent.allowsNone ? 0 : parent.minimum, proposed))
            if parent.seconds != value { parent.seconds = value }
            picker.dateValue = SettingsDurationField.midnight.addingTimeInterval(Double(value))
        }
    }
}
