import Foundation

enum HeaderButtonDropTarget: Equatable {
    case position(NotchWing, Int)
    case disabled
}

enum NotchTab: String, CaseIterable, Codable {
    case overview = "Overview", focus = "Clock", codex = "Codex", shelf = "File Shelf"
    case fans = "Fans", mirror = "Mirror"

    var title: String {
        switch self {
        case .overview: "Media"
        case .codex: "Code & AI"
        case .mirror: "Camera"
        default: rawValue
        }
    }
    var icon: String {
        switch self {
        case .overview: "music.note"
        case .focus: "timer"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .shelf: "tray"
        case .fans: "fan"
        case .mirror: "web.camera"
        }
    }
}

enum NotchWing: String, CaseIterable { case left = "Left", right = "Right" }

struct NotchTabPosition: Hashable {
    let wing: NotchWing
    let index: Int
}

enum NotchHeaderControl: String, Codable, CaseIterable {
    case pin, visibility
    var title: String { self == .pin ? "Pin" : "Visibility Mode" }
    var icon: String { self == .pin ? "pin" : "eye" }
}

struct NotchTabLayout: Codable, Equatable {
    static let pin = "Pin"
    static let visibility = "Visibility"
    static let settings = "Settings"
    static let optionalControls = [visibility, settings]
    static var catalog: [String] { NotchTab.allCases.map(\.rawValue) + [pin] + optionalControls }
    static func title(for item: String) -> String {
        NotchTab(rawValue: item)?.title ?? (item == visibility ? "Fullscreen Mode" : item)
    }
    static func icon(for item: String) -> String {
        NotchTab(rawValue: item)?.icon ?? (item == pin ? "pin" : item == visibility ? "eye" : "gearshape")
    }
    static let capacity = 5
    var left = ["Overview", "Clock", "Codex", "File Shelf"]
    var right = ["Fans", "Mirror", pin]
    var hidePin = false

    mutating func setControl(_ item: String, visible: Bool) {
        guard Self.optionalControls.contains(item) else { return }
        if !visible { left.removeAll { $0 == item }; right.removeAll { $0 == item }; return }
        guard !(left + right).contains(item) else { return }
        if right.count < Self.capacity { right.append(item) }
        else if left.count < Self.capacity { left.append(item) }
    }

    func items(in wing: NotchWing) -> [String] { wing == .left ? left : right }
    func wing(of item: String) -> NotchWing { left.contains(item) ? .left : .right }
    mutating func place(_ item: String, in wing: NotchWing, at index: Int) {
        guard (left + right).contains(item), index >= 0, index < Self.capacity else { return }
        place(item, in: wing)
        var items = items(in: wing)
        items.removeAll { $0 == item }
        items.insert(item, at: min(index, items.count))
        if wing == .left { left = items } else { right = items }
    }
    func canMove(_ item: String, by offset: Int) -> Bool {
        let ordered = left + right
        guard abs(offset) == 1, let index = ordered.firstIndex(of: item) else { return false }
        return ordered.indices.contains(index + offset)
    }
    mutating func move(_ item: String, by offset: Int) {
        guard canMove(item, by: offset) else { return }
        var items = items(in: wing(of: item))
        guard let index = items.firstIndex(of: item) else { return }
        guard items.indices.contains(index + offset) else {
            place(item, in: left.contains(item) ? .right : .left)
            return
        }
        items.swapAt(index, index + offset)
        if left.contains(item) { left = items } else { right = items }
    }
    mutating func place(_ item: String, in wing: NotchWing) {
        guard (left + right).contains(item), self.wing(of: item) != wing else { return }
        // Cross at the center boundary; exchange the boundary item if that wing is full.
        if items(in: wing).count >= Self.capacity {
            if wing == .left, let index = right.firstIndex(of: item) {
                right[index] = left.removeLast()
                left.append(item)
            } else if wing == .right, let index = left.firstIndex(of: item) {
                left[index] = right.removeFirst()
                right.insert(item, at: 0)
            }
            return
        }
        left.removeAll { $0 == item }; right.removeAll { $0 == item }
        if wing == .left { left.append(item) } else { right.insert(item, at: 0) }
    }
    func normalized() -> Self {
        let defaults = Self()
        let valid = Self.catalog
        var seen: Set<String> = []
        var result = self
        result.left = left.filter { valid.contains($0) && seen.insert($0).inserted }
        result.right = right.filter { valid.contains($0) && seen.insert($0).inserted }
        let missing = (defaults.left + defaults.right).filter { !seen.contains($0) }
        for item in missing {
            if defaults.left.contains(item) { result.left.append(item) } else { result.right.append(item) }
        }
        while result.left.count > Self.capacity { result.right.append(result.left.removeLast()) }
        while result.right.count > Self.capacity { result.left.append(result.right.removeLast()) }
        return result
    }
}
