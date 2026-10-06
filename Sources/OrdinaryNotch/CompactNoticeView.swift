import SwiftUI

/// Every brief alert uses the same compact typography and content layout.
struct CompactNoticeView: View {
    let symbol: String
    let title: String
    let detail: String
    var value: String? = nil
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            accent.frame(width: 16, height: 20)
                .mask {
                    Image(systemName: symbol).renderingMode(.template)
                        .symbolRenderingMode(.monochrome).font(AppFont.compact)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(accent)
                Text(detail).foregroundStyle(.white.opacity(0.65))
            }
            .font(AppFont.compact).lineLimit(1)
            if let value {
                Spacer(minLength: 8)
                Text(value).font(AppFont.compact).monospacedDigit()
                    .foregroundStyle(accent).fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
