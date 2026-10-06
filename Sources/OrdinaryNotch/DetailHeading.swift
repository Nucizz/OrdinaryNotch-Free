import SwiftUI

/// Every expanded tab reserves the same space for its icon, title and optional actions.
struct DetailHeading<Icon: View, Title: View, Accessory: View>: View {
    let icon: Icon
    let title: Title
    let accessory: Accessory

    init(@ViewBuilder icon: () -> Icon, @ViewBuilder title: () -> Title, @ViewBuilder accessory: () -> Accessory) {
        self.icon = icon(); self.title = title(); self.accessory = accessory()
    }

    init(_ title: String, systemImage: String) where Icon == Image, Title == Text, Accessory == EmptyView {
        self.init(icon: { Image(systemName: systemImage) }, title: { Text(title) }, accessory: { EmptyView() })
    }

    var body: some View {
        HStack(spacing: NotchGeometry.detailHeadingGap) {
            icon.font(AppFont.detailIcon)
                .frame(width: NotchGeometry.detailIconSize, height: NotchGeometry.detailIconSize)
                .accessibilityHidden(true)
            title.font(AppFont.detailTitle).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 4)
            HStack(spacing: 6) { accessory }.font(AppFont.button)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: NotchGeometry.detailHeadingHeight)
    }
}
