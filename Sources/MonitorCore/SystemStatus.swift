import Foundation
import Darwin

public enum HistoryRange: Double, CaseIterable, Sendable {
    case oneHour = 3600, sixHours = 21600, oneDay = 86400
    public var title: String { "\(Int(rawValue / 3600))h" }
}

public enum UptimeFormatter {
    public static func string(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 2) else { return "—" }
        let minutes = Int(seconds / 60)
        if minutes == 0 { return "不足1分钟" }
        let days = minutes / 1440, hours = minutes % 1440 / 60, remainder = minutes % 60
        if days > 0 { return "\(days)天 \(hours)小时 \(remainder)分" }
        if hours > 0 { return "\(hours)小时 \(remainder)分" }
        return "\(remainder)分"
    }
}

public enum PublicIPProvider: String, Codable, CaseIterable, Sendable {
    case ipip
    public var title: String { "IPIP（国内）" }
    public var endpoint: URL { URL(string: "https://myip.ipip.net")! }
}

/// Only the public address and ISO region are retained from the diagnostic response.
public struct PublicIPLocation: Equatable, Sendable {
    public let address: String
    public let countryCode: String?
    public var flag: String {
        guard let countryCode else { return "🌐" }
        return countryCode.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }.map(String.init).joined()
    }
    public var countryName: String { countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) } ?? "未知" }
    public init?(ipipText: String) {
        guard ipipText.utf8.count <= 8192,
              let expression = try? NSRegularExpression(pattern: "当前\\s*IP[：:]\\s*(\\S+)\\s+来自于[：:]\\s*(.+)"),
              let match = expression.firstMatch(in: ipipText, range: NSRange(ipipText.startIndex..., in: ipipText)),
              let addressRange = Range(match.range(at: 1), in: ipipText),
              let countryRange = Range(match.range(at: 2), in: ipipText) else { return nil }
        let country = ipipText[countryRange].split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        let aliases = ["中国": "CN", "香港": "HK", "中国香港": "HK", "澳门": "MO", "中国澳门": "MO", "台湾": "TW", "中国台湾": "TW"]
        let locale = Locale(identifier: "zh_CN")
        let code = aliases[country] ?? Locale.Region.isoRegions.first {
            locale.localizedString(forRegionCode: $0.identifier) == country
        }?.identifier
        self.init(trace: "ip=\(ipipText[addressRange])\nloc=\(code ?? "XX")\n")
    }
    public init?(trace: String) {
        guard trace.utf8.count <= 8192 else { return nil }
        var fields: [String: String] = [:]
        for line in trace.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let key = String(pair[0])
            guard key == "ip" || key == "loc" else { continue }
            guard fields[key] == nil else { return nil }
            fields[key] = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let address = fields["ip"], address.utf8.count < 128 else { return nil }
        var ipv4 = in_addr(), ipv6 = in6_addr()
        guard inet_pton(AF_INET, address, &ipv4) == 1 || inet_pton(AF_INET6, address, &ipv6) == 1 else { return nil }
        let code = fields["loc"]?.uppercased()
        let valid = code.map { $0.utf8.count == 2 && $0.utf8.allSatisfy { $0 >= 65 && $0 <= 90 } && Locale.Region.isoRegions.contains { $0.identifier == code } } ?? false
        self.address = address; self.countryCode = valid ? code : nil
    }
}
