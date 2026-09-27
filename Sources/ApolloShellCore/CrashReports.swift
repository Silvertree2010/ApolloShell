import Foundation

public struct CrashReportSettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case ask
        case always
        case never
    }

    public var mode: Mode
    public var handledUntil: Date?

    public init(mode: Mode = .ask, handledUntil: Date? = nil) {
        self.mode = mode
        self.handledUntil = handledUntil
    }

    private enum CodingKeys: String, CodingKey {
        case mode, handledUntil
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.mode, into: &mode)
        c.lenient(.handledUntil, into: &handledUntil)
    }
}

public enum CrashReportScan {
    public static let firstLookBack: TimeInterval = 3 * 24 * 3600
    public static let maxPerLaunch = 3

    public struct Candidate: Equatable, Sendable {
        public let url: URL
        public let modified: Date

        public init(url: URL, modified: Date) {
            self.url = url
            self.modified = modified
        }
    }

    public static func isOwnReport(_ fileName: String, processName: String) -> Bool {
        let prefix = processName + "-"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(".ips") else { return false }
        return fileName.dropFirst(prefix.count).first?.isNumber == true
    }

    public static func pending(_ all: [Candidate], handledUntil: Date?, now: Date) -> [Candidate] {
        let since = handledUntil ?? now.addingTimeInterval(-firstLookBack)
        let fresh = all.filter { $0.modified > since && $0.modified <= now }
            .sorted { $0.modified < $1.modified }
        return Array(fresh.suffix(maxPerLaunch))
    }
}

public struct SanitizedCrashReport: Equatable, Sendable {
    public let text: String
    public let appVersion: String
    public let build: String
    public let os: String
    public let arch: String
    public let crashedAt: Date
    public let pid: Int?
    public let launchedAt: Date?
}

public enum CrashReportSanitizer {
    static let headerKeys: Set<String> = [
        "app_name", "app_version", "build_version", "bundleID", "os_version",
        "bug_type", "timestamp", "name", "slice_uuid", "platform",
    ]
    static let bodyKeys: Set<String> = [
        "version", "osVersion", "captureTime", "procLaunch", "cpuType", "translated",
        "procName", "bundleInfo", "modelCode", "exception", "termination", "asi",
        "lastExceptionBacktrace", "ktriageinfo", "vmRegionInfo", "faultingThread",
        "threads", "usedImages", "legacyInfo", "bug_type",
    ]
    static let threadKeys: Set<String> = ["triggered", "queue", "name", "frames"]
    static let frameKeys: Set<String> = [
        "imageOffset", "imageIndex", "symbol", "symbolLocation", "sourceLine", "sourceFile", "inline",
    ]
    static let imageKeys: Set<String> = [
        "source", "arch", "base", "size", "uuid", "name",
        "CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
    ]

    public static func sanitize(_ raw: String) -> SanitizedCrashReport? {
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let header = object(parts[0]),
              let body = object(parts[1]) else { return nil }

        let cleanHeader = header.filter { headerKeys.contains($0.key) }
        var cleanBody = body.filter { bodyKeys.contains($0.key) }
        if let threads = body["threads"] as? [[String: Any]] {
            cleanBody["threads"] = threads.map(cleanThread)
        }
        if let frames = body["lastExceptionBacktrace"] as? [[String: Any]] {
            cleanBody["lastExceptionBacktrace"] = frames.map(cleanFrame)
        }
        if let images = body["usedImages"] as? [[String: Any]] {
            cleanBody["usedImages"] = images.map { $0.filter { imageKeys.contains($0.key) } }
        }

        guard let headerText = json(cleanHeader), let bodyText = json(cleanBody.mapValues(redacted)) else { return nil }
        let osVersion = body["osVersion"] as? [String: Any]
        let os = (header["os_version"] as? String)
            ?? [osVersion?["train"], osVersion?["build"]].compactMap { $0 as? String }.joined(separator: " ")
        let crashedAt = date(body["captureTime"]) ?? date(header["timestamp"]) ?? Date(timeIntervalSince1970: 0)
        return SanitizedCrashReport(
            text: headerText + "\n" + bodyText,
            appVersion: header["app_version"] as? String ?? "",
            build: header["build_version"] as? String ?? "",
            os: os,
            arch: arch(body["cpuType"] as? String),
            crashedAt: crashedAt,
            pid: body["pid"] as? Int,
            launchedAt: date(body["procLaunch"])
        )
    }

    static func redacted(_ value: Any) -> Any {
        switch value {
        case let text as String:
            return redactedPaths(text)
        case let list as [Any]:
            return list.map(redacted)
        case let object as [String: Any]:
            return object.mapValues(redacted)
        default:
            return value
        }
    }

    static func redactedPaths(_ text: String) -> String {
        guard text.contains("/Users/") else { return text }
        var result = ""
        var rest = Substring(text)
        while let range = rest.range(of: "/Users/") {
            result += rest[..<range.upperBound]
            rest = rest[range.upperBound...]
            let name = rest.prefix { $0 != "/" && $0 != "\"" && $0 != "'" && !$0.isWhitespace }
            if !name.isEmpty { result += "~" }
            rest = rest.dropFirst(name.count)
        }
        return result + rest
    }

    private static func cleanThread(_ thread: [String: Any]) -> [String: Any] {
        var clean = thread.filter { threadKeys.contains($0.key) }
        if let frames = thread["frames"] as? [[String: Any]] {
            clean["frames"] = frames.map(cleanFrame)
        }
        return clean
    }

    private static func cleanFrame(_ frame: [String: Any]) -> [String: Any] {
        var clean = frame.filter { frameKeys.contains($0.key) }
        if let file = clean["sourceFile"] as? String {
            clean["sourceFile"] = (file as NSString).lastPathComponent
        }
        return clean
    }

    private static func arch(_ cpuType: String?) -> String {
        switch cpuType {
        case "ARM-64": "arm64"
        case "X86-64": "x86_64"
        case let other?: other
        case nil: ""
        }
    }

    private static func object(_ text: Substring) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    private static func json(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SSSS Z", "yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

public enum CrashLogContext {
    public static let window: TimeInterval = 10 * 60
    public static let maxBytes = 64 * 1024

    public static func arguments(pid: Int, crashedAt: Date, launchedAt: Date?) -> [String] {
        let start = max(launchedAt ?? .distantPast, crashedAt.addingTimeInterval(-window))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        let predicate = """
            processIdentifier == \(pid) AND (category == "HIExceptions" \
            OR (subsystem == "com.apple.AppKit" AND category == "General") \
            OR eventMessage CONTAINS "Assertion failure")
            """
        return ["show", "--style", "ndjson",
                "--start", formatter.string(from: start),
                "--end", formatter.string(from: crashedAt.addingTimeInterval(5)),
                "--predicate", predicate]
    }

    public static func lines(fromNDJSON output: String) -> String {
        var result: [String] = []
        for line in output.split(separator: "\n") {
            guard let entry = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let message = entry["eventMessage"] as? String else { continue }
            let time = (entry["timestamp"] as? String).map(clockTime) ?? ""
            let subsystem = entry["subsystem"] as? String ?? ""
            let category = entry["category"] as? String ?? ""
            result.append("\(time) [\(subsystem):\(category)] \(message)")
        }
        return trimmed(result.joined(separator: "\n"))
    }

    private static func clockTime(_ stamp: String) -> String {
        let parts = stamp.split(separator: " ")
        guard parts.count >= 2 else { return stamp }
        let time = parts[1].prefix { $0 != "+" && $0 != "-" }
        return String(time.prefix(12))
    }

    static func trimmed(_ text: String) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var kept: [Substring] = []
        var size = 0
        for line in text.split(separator: "\n").reversed() {
            size += line.utf8.count + 1
            if size > maxBytes { break }
            kept.append(line)
        }
        return kept.reversed().joined(separator: "\n")
    }
}

public struct CrashReportUpload: Codable, Equatable, Sendable {
    public var appVersion: String
    public var build: String
    public var os: String
    public var arch: String
    public var crashedAt: String
    public var install: String
    public var report: String
    public var context: String?

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version", build, os, arch
        case crashedAt = "crashed_at", install, report, context
    }

    public init(_ report: SanitizedCrashReport, install: String, context: String?) {
        appVersion = report.appVersion
        build = report.build
        os = report.os
        arch = report.arch
        crashedAt = ISO8601DateFormatter().string(from: report.crashedAt)
        self.install = install
        self.report = report.text
        self.context = (context?.isEmpty ?? true) ? nil : context
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
