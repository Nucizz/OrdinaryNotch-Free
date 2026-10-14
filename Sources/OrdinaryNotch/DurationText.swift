import Foundation

/// Shared duration syntax. Bare numbers mean minutes; two-part clock notation is minutes:seconds.
enum DurationText {
    static let timerRange = 1...86_399
    static func parse(_ text: String, maximum: Int = timerRange.upperBound, allowsNone: Bool = false, wholeMinutes: Bool = false) -> Int? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if allowsNone && ["none", "0"].contains(input) { return 0 }
        guard !input.isEmpty, maximum > 0 else { return nil }
        func digits(_ text: String) -> Int? {
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(text)
        }
        var total = 0
        func add(_ number: Int, multiplier: Int) -> Bool {
            guard number <= (maximum - total) / multiplier else { return false }
            total += number * multiplier
            return true
        }
        if input.contains(":") {
            let parts = input.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard (2...3).contains(parts.count) else { return nil }
            let values = parts.compactMap(digits)
            guard values.count == parts.count, values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
            for (value, multiplier) in zip(values, parts.count == 3 ? [3600, 60, 1] : [60, 1]) {
                guard add(value, multiplier: multiplier) else { return nil }
            }
        } else if let minutes = digits(input) {
            guard add(minutes, multiplier: 60) else { return nil }
        } else {
            let expression = try! NSRegularExpression(pattern: #"(\d+)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)"#)
            let string = input as NSString
            let matches = expression.matches(in: input, range: NSRange(location: 0, length: string.length))
            guard !matches.isEmpty else { return nil }
            var end = 0
            var units: Set<Character> = []
            for match in matches {
                guard string.substring(with: NSRange(location: end, length: match.range.location - end))
                    .trimmingCharacters(in: .whitespaces).isEmpty,
                    let value = digits(string.substring(with: match.range(at: 1))),
                    let unit = string.substring(with: match.range(at: 2)).first,
                    units.insert(unit).inserted,
                    add(value, multiplier: unit == "h" ? 3600 : unit == "m" ? 60 : 1) else { return nil }
                end = NSMaxRange(match.range)
            }
            guard string.substring(from: end).trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        }
        guard total > 0, !wholeMinutes || total % 60 == 0 else { return nil }
        return total
    }
    static func format(_ seconds: Int) -> String {
        guard seconds > 0 else { return "None" }
        return [(seconds / 3600, "h"), (seconds % 3600 / 60, "m"), (seconds % 60, "s")]
            .filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }
}
