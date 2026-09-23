import ApolloShellCore
import Foundation
import Testing

/// Kuenstlicher Bericht im Aufbau einer echten `.ips`-Datei, mit allem,
/// was nicht mitgehen darf.
private let sampleIPS = """
{"app_name":"ApolloShell","timestamp":"2026-09-22 12:32:21.00 +0200","app_version":"0.1.4.1","build_version":"340","bundleID":"io.github.silvertree2010.apolloshell","os_version":"macOS 26.6.2 (25G83)","bug_type":"309","name":"ApolloShell","incident_id":"C5AB207E-0000-0000-0000-000000000000","share_with_app_devs":0}
{"pid":43684,"userID":501,"procPath":"/Users/someone/Applications/ApolloShell.app/Contents/MacOS/ApolloShell","procName":"ApolloShell","procLaunch":"2026-09-22 12:21:37.4200 +0200","captureTime":"2026-09-22 12:32:18.1997 +0200","cpuType":"ARM-64","modelCode":"Mac16,7","crashReporterKey":"FFA5F0B7-0000-0000-0000-000000000000","storeInfo":{"deviceIdentifierForVendor":"5F811D95-0000"},"sleepWakeUUID":"9C50","bootSessionUUID":"93B2","osVersion":{"train":"macOS 26.6.2","build":"25G83"},"exception":{"type":"EXC_BAD_ACCESS","signal":"SIGSEGV"},"faultingThread":0,"threads":[{"triggered":true,"id":57266094,"queue":"com.apple.main-thread","threadState":{"x":[{"value":4267754718184}]},"frames":[{"imageOffset":100,"imageIndex":0,"symbol":"swift_getObjectType","symbolLocation":4},{"imageOffset":200,"imageIndex":1,"symbol":"main","sourceFile":"/Users/someone/src/LauncherApp.swift","sourceLine":34}]}],"usedImages":[{"name":"libswiftCore.dylib","path":"/usr/lib/swift/libswiftCore.dylib","arch":"arm64","base":1,"size":2,"uuid":"a"},{"name":"ApolloShell","path":"/Users/someone/Applications/ApolloShell.app/Contents/MacOS/ApolloShell","arch":"arm64","base":3,"size":4,"uuid":"b"}]}
"""

@Suite("Absturzberichte: bereinigen")
struct CrashReportSanitizerTests {
    @Test("Kennungen, Pfade und Register gehen nicht mit")
    func dropsPersonalFields() throws {
        let report = try #require(CrashReportSanitizer.sanitize(sampleIPS))
        for secret in ["crashReporterKey", "FFA5F0B7", "deviceIdentifierForVendor", "5F811D95",
                       "sleepWakeUUID", "bootSessionUUID", "incident_id", "userID", "procPath",
                       "/Users/someone", "threadState", "4267754718184", "43684"] {
            #expect(!report.text.contains(secret), "\(secret) steht noch drin")
        }
    }

    @Test("Was zur Fehlersuche noetig ist, bleibt")
    func keepsWhatDebuggingNeeds() throws {
        let report = try #require(CrashReportSanitizer.sanitize(sampleIPS))
        for kept in ["swift_getObjectType", "EXC_BAD_ACCESS", "\"LauncherApp.swift\"", "libswiftCore.dylib",
                     "com.apple.main-thread", "\"faultingThread\":0"] {
            #expect(report.text.contains(kept), "\(kept) fehlt")
        }
        #expect(report.appVersion == "0.1.4.1")
        #expect(report.build == "340")
        #expect(report.os == "macOS 26.6.2 (25G83)")
        #expect(report.arch == "arm64")
        #expect(report.pid == 43684)
        #expect(report.launchedAt != nil)
    }

    @Test("Ergebnis ist wieder eine .ips: Kopfzeile, dann Rumpf")
    func staysInIPSFormat() throws {
        let report = try #require(CrashReportSanitizer.sanitize(sampleIPS))
        let again = try #require(CrashReportSanitizer.sanitize(report.text))
        #expect(again.text == report.text)
    }

    @Test("Zeitpunkt aus captureTime")
    func readsCrashTime() throws {
        let report = try #require(CrashReportSanitizer.sanitize(sampleIPS))
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-09-22T10:32:18Z"))
        #expect(abs(report.crashedAt.timeIntervalSince(expected)) < 1)
    }

    @Test("Kein Bericht, kein Ergebnis")
    func rejectsGarbage() {
        #expect(CrashReportSanitizer.sanitize("") == nil)
        #expect(CrashReportSanitizer.sanitize("kein json\nauch nicht") == nil)
        #expect(CrashReportSanitizer.sanitize("{\"a\":1}") == nil)
    }
}

@Suite("Absturzberichte: was ansteht")
struct CrashReportScanTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func candidate(_ name: String, ago: TimeInterval) -> CrashReportScan.Candidate {
        .init(url: URL(fileURLWithPath: "/tmp/\(name)"), modified: now.addingTimeInterval(-ago))
    }

    @Test("Nur eigene .ips-Dateien")
    func onlyOwnFiles() {
        #expect(CrashReportScan.isOwnReport("ApolloShell-2026-09-22-123221.ips", processName: "ApolloShell"))
        #expect(!CrashReportScan.isOwnReport("ApolloShell-2026-09-22-123221.diag", processName: "ApolloShell"))
        #expect(!CrashReportScan.isOwnReport("Finder-2026-09-19-000335.ips", processName: "ApolloShell"))
        #expect(!CrashReportScan.isOwnReport("ApolloShellHelper-2026.ips", processName: "ApolloShell"))
        #expect(!CrashReportScan.isOwnReport("ApolloShell-dbg-2026-09-21-052110.ips", processName: "ApolloShell"))
    }

    @Test("Nach handledUntil, aelteste zuerst")
    func afterHandled() {
        let all = [candidate("a", ago: 300), candidate("b", ago: 100), candidate("c", ago: 200)]
        let pending = CrashReportScan.pending(all, handledUntil: now.addingTimeInterval(-250), now: now)
        #expect(pending.map(\.url.lastPathComponent) == ["c", "b"])
    }

    @Test("Beim ersten Mal nur drei Tage zurueck")
    func firstLookBack() {
        let all = [candidate("alt", ago: 4 * 24 * 3600), candidate("neu", ago: 3600)]
        #expect(CrashReportScan.pending(all, handledUntil: nil, now: now).map(\.url.lastPathComponent) == ["neu"])
    }

    @Test("Hoechstens drei, die neuesten")
    func capsCount() {
        let all = (1...5).map { candidate("\($0)", ago: TimeInterval($0) * 10) }
        #expect(CrashReportScan.pending(all, handledUntil: nil, now: now).map(\.url.lastPathComponent) == ["3", "2", "1"])
    }
}

@Suite("Absturzberichte: Logzeilen und Upload")
struct CrashLogContextTests {
    @Test("ndjson wird zu lesbaren Zeilen")
    func formatsLines() {
        let ndjson = """
        {"timestamp":"2026-09-22 12:32:18.076543+0200","subsystem":"com.apple.AppKit","category":"General","eventMessage":"View is not in any window"}
        kaputt
        {"timestamp":"2026-09-22 12:32:18.084000+0200","subsystem":"com.apple.hiservices","category":"HIExceptions","eventMessage":"FAULT: NSInternalInconsistencyException"}
        """
        #expect(CrashLogContext.lines(fromNDJSON: ndjson) == """
        12:32:18.076 [com.apple.AppKit:General] View is not in any window
        12:32:18.084 [com.apple.hiservices:HIExceptions] FAULT: NSInternalInconsistencyException
        """)
    }

    @Test("Zu lang: die letzten Zeilen bleiben")
    func keepsTail() {
        let line = String(repeating: "x", count: 1000)
        let text = (0..<200).map { "\($0) \(line)" }.joined(separator: "\n")
        let lines = CrashLogContext.lines(fromNDJSON: "") + text
        let kept = CrashLogContextTests.trim(lines)
        #expect(kept.utf8.count <= CrashLogContext.maxBytes)
        #expect(kept.hasSuffix("199 \(line)"))
    }

    private static func trim(_ text: String) -> String {
        // Ueber den oeffentlichen Weg: eine ndjson-Zeile je Textzeile.
        let ndjson = text.split(separator: "\n").map { line in
            let data = try! JSONSerialization.data(withJSONObject: ["eventMessage": String(line)])
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n")
        return CrashLogContext.lines(fromNDJSON: ndjson)
    }

    @Test("Suche beginnt beim Start, hoechstens zehn Minuten zurueck")
    func argumentsWindow() {
        let crash = Date(timeIntervalSince1970: 1_000_000)
        let args = CrashLogContext.arguments(pid: 42, crashedAt: crash, launchedAt: crash.addingTimeInterval(-60))
        #expect(args.contains("--predicate"))
        #expect(args.last?.contains("processIdentifier == 42") == true)
        let early = CrashLogContext.arguments(pid: 42, crashedAt: crash, launchedAt: nil)
        #expect(early != args)
    }

    @Test("Upload traegt die Feldnamen des Workers")
    func uploadFields() throws {
        let report = try #require(CrashReportSanitizer.sanitize(sampleIPS))
        let upload = CrashReportUpload(report, install: "dmg", context: "")
        let object = try #require(try JSONSerialization.jsonObject(with: upload.encoded()) as? [String: Any])
        #expect(Set(object.keys) == ["app_version", "build", "os", "arch", "crashed_at", "install", "report"])
        #expect(object["crashed_at"] as? String == "2026-09-22T10:32:18Z")
    }

    @Test("Einstellung liest sich nachsichtig")
    func settingsLenient() throws {
        let data = Data(#"{"mode":"irgendwas","handledUntil":"kaputt"}"#.utf8)
        let settings = try JSONDecoder().decode(CrashReportSettings.self, from: data)
        #expect(settings == CrashReportSettings())
    }
}
