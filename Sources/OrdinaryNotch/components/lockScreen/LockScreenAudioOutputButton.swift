import SwiftUI

/// Uses the same AppKit menu and input target as the notch, with the player's icon treatment.
struct LockScreenAudioOutputButton: View {
    var media: LockScreenActivityRow.Media
    var availableOutputs: () -> [AudioOutput.Device]
    var select: (AudioOutput.Device) -> Void
    @State private var pressed = false
    @State private var focused = false

    var body: some View {
        Image(systemName: media.outputSymbol)
            .font(.title2).foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            .overlay {
                NotchPressAndHoldTarget(label: "Choose Audio Output", value: media.outputName ?? "None",
                    hint: "Choose audio output", menuLabel: "Audio Output", menuItems: [], action: {},
                    menuOnClick: true, loadMenuItems: menuItems,
                    pressed: $pressed, focused: $focused)
            }
            .modifier(LockScreenPlayerControlEffect(pressed: pressed))
            .help("Choose audio output. Current: \(media.outputName ?? "None")")
    }

    private func menuItems() -> [NotchButtonMenuItem] {
        let devices = availableOutputs()
        guard !devices.isEmpty else {
            return [.init(title: "No audio outputs available", enabled: false, action: {})]
        }
        return devices.map { device in
            .init(title: device.route.name, selected: device.selected, symbol: device.route.symbol,
                  action: { select(device) })
        }
    }
}
