import Foundation

/// Positions are relative to the center of the physical or simulated cutout.
struct CompactActivityLayout {
    private static let partSpacing: CGFloat = 6
    enum Side { case left, right }
    enum Region { case leftWing, rightWing, mainIsland, offIsland }

    struct Position {
        let side: Side
        let region: Region
        let width: CGFloat
        let offset: CGFloat
    }

    struct Placement: Identifiable {
        let activity: CompactActivity
        /// Zero is the highest visible priority.
        let priority: Int
        let primary: Position
        let secondary: Position?
        var id: CompactActivity { activity }
    }

    struct Content {
        let activity: CompactActivity
        let primaryWidth: CGFloat
        let secondaryWidth: CGFloat
        var leftWidth: CGFloat { activity.primarySide == .left ? primaryWidth : secondaryWidth }
        var rightWidth: CGFloat { activity.primarySide == .right ? primaryWidth : secondaryWidth }
        var combinedWidth: CGFloat { primaryWidth + partSpacing + secondaryWidth }
    }

    let placements: [Placement]
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let width: CGFloat
    let wingExtent: CGFloat
    let mainWidth: CGFloat
    let detachedWidth: CGFloat
    var detachedSpan: CGFloat { detachedWidth > 0 ? detachedWidth + NotchGeometry.islandSeparation : 0 }

    /// Physical notch: one activity spans both wings, or two activities each occupy a wing.
    /// Dynamic Island: the main activity spans the cutout; only the second activity's primary
    /// content appears in a detached capsule. Coordinates keep the main cutout centered.
    init(contents: [Content], centerWidth: CGFloat, minimumWidth: CGFloat = 0, style: NotchStyle = .notch,
         presentation: NotchActivityPresentation = .detailed,
         outerPadding: CGFloat = NotchGeometry.compactOuterPadding) {
        let visible = Array(contents.prefix(2))
        if style == .island {
            leftWidth = visible.first?.leftWidth ?? 0
            rightWidth = visible.first?.rightWidth ?? 0
            let contentWidth = max(leftWidth, rightWidth)
            mainWidth = max(minimumWidth, centerWidth + 2 * (contentWidth > 0 ? contentWidth + outerPadding : 0))
            let second = visible.dropFirst().first
            detachedWidth = second.map { max(NotchGeometry.islandCompactHeight, $0.primaryWidth + 16) } ?? 0
            let span = detachedWidth > 0 ? detachedWidth + NotchGeometry.islandSeparation : 0
            width = mainWidth + span
            wingExtent = (mainWidth - centerWidth) / 2
            var result: [Placement] = []
            if let first = visible.first {
                let left = Position(side: .left, region: .mainIsland, width: first.leftWidth,
                                    offset: -mainWidth / 2 + outerPadding + first.leftWidth / 2)
                let right = Position(side: .right, region: .mainIsland, width: first.rightWidth,
                                     offset: mainWidth / 2 - outerPadding - first.rightWidth / 2)
                result.append(Placement(activity: first.activity, priority: 0,
                                        primary: first.activity.primarySide == .left ? left : right,
                                        secondary: first.activity.primarySide == .left ? right : left))
            }
            if let second {
                result.append(Placement(activity: second.activity, priority: 1,
                                        primary: Position(side: .right, region: .offIsland, width: second.primaryWidth,
                                                          offset: mainWidth / 2 + NotchGeometry.islandSeparation + detachedWidth / 2),
                                        secondary: nil))
            }
            placements = result
            return
        }
        let paired = visible.count == 2
        if paired && presentation == .compact {
            // Highest priority claims its preferred wing; the other primary takes the free wing.
            let firstSide = visible[0].activity.primarySide
            let left = visible[firstSide == .left ? 0 : 1]
            let right = visible[firstSide == .right ? 0 : 1]
            leftWidth = left.primaryWidth
            rightWidth = right.primaryWidth
            width = max(minimumWidth, centerWidth + 2 * (max(leftWidth, rightWidth) + outerPadding))
            mainWidth = width
            detachedWidth = 0
            wingExtent = (width - centerWidth) / 2
            let edge = width / 2 - outerPadding
            placements = visible.enumerated().map { rank, content in
                let side: Side = rank == 0 ? firstSide : (firstSide == .left ? .right : .left)
                return Placement(activity: content.activity, priority: rank,
                                 primary: Position(side: side, region: side == .left ? .leftWing : .rightWing,
                                                   width: content.primaryWidth,
                                                   offset: side == .left ? -edge + content.primaryWidth / 2 : edge - content.primaryWidth / 2),
                                 secondary: nil)
            }
            return
        }
        leftWidth = visible.first.map { paired ? $0.combinedWidth : $0.leftWidth } ?? 0
        rightWidth = visible.last.map { paired ? $0.combinedWidth : $0.rightWidth } ?? 0
        let contentWidth = max(leftWidth, rightWidth)
        width = max(minimumWidth, centerWidth + 2 * (contentWidth > 0 ? contentWidth + outerPadding : 0))
        mainWidth = width
        detachedWidth = 0
        wingExtent = (width - centerWidth) / 2
        let leftEdge = -width / 2 + outerPadding
        let rightEdge = width / 2 - outerPadding
        placements = visible.enumerated().map { rank, content in
            let wing: Side = rank == 0 ? .left : .right
            let start = wing == .left ? leftEdge : rightEdge - content.combinedWidth
            let left = Position(side: paired ? wing : .left, region: paired && wing == .right ? .rightWing : .leftWing, width: content.leftWidth,
                                offset: (paired ? start : leftEdge) + content.leftWidth / 2)
            let right = Position(side: paired ? wing : .right, region: paired && wing == .left ? .leftWing : .rightWing, width: content.rightWidth,
                                 offset: paired ? start + content.leftWidth + Self.partSpacing + content.rightWidth / 2
                                                : rightEdge - content.rightWidth / 2)
            let primary = content.activity.primarySide == .left ? left : right
            let secondary = content.activity.primarySide == .left ? right : left
            return Placement(activity: content.activity, priority: rank, primary: primary, secondary: secondary)
        }
    }
}
