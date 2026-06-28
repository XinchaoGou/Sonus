import Foundation

struct AppVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var values: [Int] = []
        for part in parts.prefix(4) {
            guard let value = Int(part) else { return nil }
            values.append(value)
        }
        while values.count < 3 {
            values.append(0)
        }
        components = values
    }

    static var current: AppVersion? {
        guard let string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return AppVersion(string)
    }

    var displayString: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}
