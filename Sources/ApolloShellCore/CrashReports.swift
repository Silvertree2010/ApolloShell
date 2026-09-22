import Foundation

/// Absturzberichte (Nexus > Updates > Crash reports).
///
/// macOS schreibt bei jedem Absturz eine `.ips`-Datei nach
/// `~/Library/Logs/DiagnosticReports`. Beim naechsten Start sieht die Shell
/// dort nach, fragt (oder nicht, je nach Wahl) und schickt eine bereinigte
/// Fassung an den Crash-Endpunkt. Nichts davon laeuft ohne Zustimmung.
public struct CrashReportSettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Nach jedem Absturz fragen (Vorgabe).
        case ask
        /// Ohne Rueckfrage senden.
        case always
        /// Nie senden, auch nicht fragen.
        case never
    }

    public var mode: Mode
    /// Bis zu diesem Zeitpunkt sind alle Berichte erledigt (gesendet,
    /// abgelehnt oder zu alt). `nil`: noch nie nachgesehen.
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

/// Welche Berichte beim Start anstehen.
public enum CrashReportScan {
    /// Beim allerersten Nachsehen nur so weit zurueck - aeltere Abstuerze
    /// betreffen meist eine laengst ersetzte Fassung.
    public static let firstLookBack: TimeInterval = 3 * 24 * 3600
    /// Hoechstens so viele auf einmal; der Rest gilt als erledigt.
    public static let maxPerLaunch = 3

    public struct Candidate: Equatable, Sendable {
        public let url: URL
        public let modified: Date

        public init(url: URL, modified: Date) {
            self.url = url
            self.modified = modified
        }
    }

    /// Dateien der Shell selbst: `ApolloShell-2026-09-22-123221.ips`.
    /// Fremde Apps, andere Arten (`.diag`, `.spin`) und Prozesse mit
    /// laengerem Namen (`ApolloShell-dbg-2026-...`) bleiben aussen vor:
    /// nach dem Bindestrich muss das Datum kommen.
    public static func isOwnReport(_ fileName: String, processName: String) -> Bool {
        let prefix = processName + "-"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(".ips") else { return false }
        return fileName.dropFirst(prefix.count).first?.isNumber == true
    }

    /// Die neuesten `maxPerLaunch` Berichte nach `handledUntil`, aelteste
    /// zuerst (so kommt der Dialog in der Reihenfolge der Abstuerze).
    public static func pending(_ all: [Candidate], handledUntil: Date?, now: Date) -> [Candidate] {
        let since = handledUntil ?? now.addingTimeInterval(-firstLookBack)
        let fresh = all.filter { $0.modified > since && $0.modified <= now }
            .sorted { $0.modified < $1.modified }
        return Array(fresh.suffix(maxPerLaunch))
    }
}

/// Eine `.ips`-Datei, auf das Noetige gekuerzt.
///
/// Die Datei besteht aus zwei JSON-Teilen: eine Kopfzeile, dann der Rumpf.
/// Uebernommen wird nur, was eine Liste ausdruecklich erlaubt - kein
/// Geraeteschluessel, keine Kennungen, keine Pfade, keine Register.
public struct SanitizedCrashReport: Equatable, Sendable {
    /// Kopfzeile + Rumpf, wieder im `.ips`-Format.
    public let text: String
    public let appVersion: String
    public let build: String
    public let os: String
    public let arch: String
    public let crashedAt: Date
    /// Prozessnummer und Startzeit: nur lokal, um die Logzeilen davor zu
    /// finden. Gehen nicht mit.
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

    /// `nil`: kein lesbarer Bericht.
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

        guard let headerText = json(cleanHeader), let bodyText = json(cleanBody) else { return nil }
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

    private static func cleanThread(_ thread: [String: Any]) -> [String: Any] {
        var clean = thread.filter { threadKeys.contains($0.key) }
        if let frames = thread["frames"] as? [[String: Any]] {
            clean["frames"] = frames.map(cleanFrame)
        }
        return clean
    }

    private static func cleanFrame(_ frame: [String: Any]) -> [String: Any] {
        var clean = frame.filter { frameKeys.contains($0.key) }
        // Quellpfade koennen den Benutzernamen des Bauenden enthalten.
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

    /// "2026-09-22 12:32:18.1997 +0200" oder "2026-09-22 12:32:21.00 +0200".
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

/// Die Logzeilen kurz vor dem Absturz, die ihn oft erst erklaeren.
///
/// AppKit faengt Objective-C-Exceptions ab und schreibt sie nur ins Log.
/// Passiert das mitten in einem Swift-Task, stuerzt die App erst spaeter an
/// ganz anderer Stelle ab - der Bericht allein zeigt dann die falsche Stelle
/// (so am 22.09.2026: Exception im Dock-Menue, Absturz im Hover).
public enum CrashLogContext {
    /// So weit vor dem Absturz wird gesucht.
    public static let window: TimeInterval = 10 * 60
    /// Obergrenze fuer den mitgeschickten Text; es zaehlen die letzten Zeilen.
    public static let maxBytes = 64 * 1024

    /// Argumente fuer `/usr/bin/log show`: nur dieser Prozess, nur
    /// Exceptions und Fehler, die AppKit meldet.
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

    /// Aus der ndjson-Ausgabe lesbare Zeilen machen:
    /// `12:32:18.076 [com.apple.AppKit:General] View is not in any window`.
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

    /// "2026-09-22 12:32:18.076543+0200" -> "12:32:18.076".
    private static func clockTime(_ stamp: String) -> String {
        let parts = stamp.split(separator: " ")
        guard parts.count >= 2 else { return stamp }
        let time = parts[1].prefix { $0 != "+" && $0 != "-" }
        return String(time.prefix(12))
    }

    /// Zu lang: die letzten Zeilen behalten, sie stehen dem Absturz am naechsten.
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

/// Was an den Endpunkt geht. Feldnamen wie in der API des Workers.
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

    /// Der Rumpf der Anfrage; lesbar eingerueckt, weil dieselben Bytes auch
    /// in der Vorschau des Dialogs stehen.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
