import AppKit
import ApolloShellCore
import os

@MainActor
final class CrashReporter {
    static var endpoint: URL {
        UserDefaults.standard.string(forKey: "crashReportEndpoint").flatMap(URL.init(string:))
            ?? URL(string: "https://apolloshell-crashes.pages.dev/v1/reports")!
    }
    private static let delay: TimeInterval = 8

    private let settings: ShellSettingsStore
    private let installKind: InstallKind
    private let log = Logger(category: "crashreports")
    private var busy = false

    init(settings: ShellSettingsStore,
         installKind: InstallKind = .detect(resourcesURL: Bundle.main.resourceURL)) {
        self.settings = settings
        self.installKind = installKind
    }

    func checkAfterLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay) { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        guard !busy else { return }
        let now = Date()
        let pending = CrashReportScan.pending(Self.candidates(), handledUntil: settings.settings.crashReports.handledUntil,
                                              now: now)
        guard !pending.isEmpty else { return }
        if settings.settings.crashReports.mode == .never {
            markHandled(until: pending.last!.modified)
            return
        }
        busy = true
        let install = installKind == .homebrew ? "homebrew" : "dmg"
        Task { [weak self] in
            var prepared: [(CrashReportScan.Candidate, CrashReportUpload)] = []
            for candidate in pending {
                guard let upload = await Self.prepare(candidate, install: install) else { continue }
                prepared.append((candidate, upload))
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(prepared, lastSeen: pending.last!.modified) }
            }
        }
    }

    private func handle(_ prepared: [(CrashReportScan.Candidate, CrashReportUpload)], lastSeen: Date) {
        defer { busy = false }
        guard !prepared.isEmpty else { return markHandled(until: lastSeen) }
        for (candidate, upload) in prepared {
            switch settings.settings.crashReports.mode {
            case .never:
                markHandled(until: candidate.modified)
            case .always:
                send(upload, handledUntil: candidate.modified)
            case .ask:
                switch ask(upload) {
                case true?: send(upload, handledUntil: candidate.modified)
                case false?: markHandled(until: candidate.modified)
                case nil: return
                }
            }
        }
    }

    private func ask(_ upload: CrashReportUpload) -> Bool? {
        let alert = NSAlert()
        alert.messageText = String(localized: "ApolloShell quit unexpectedly")
        alert.informativeText = String(localized: """
            Send the crash report to the developer? It helps find the bug. \
            It contains the ApolloShell and macOS versions, your Mac model and where in the code \
            the crash happened - no files, names, device IDs or anything you typed.
            """)
        alert.addButton(withTitle: String(localized: "Send"))
        alert.addButton(withTitle: String(localized: "Don't Send"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Do this every time (change it in Nexus > Updates)")
        alert.accessoryView = Self.preview(upload)
        NSApp.activate()
        let response = alert.runModal()
        guard response != .abort else { return nil }
        let send = response == .alertFirstButtonReturn
        if alert.suppressionButton?.state == .on {
            settings.settings.crashReports.mode = send ? .always : .never
        }
        return send
    }

    private func send(_ upload: CrashReportUpload, handledUntil: Date) {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = upload.encoded()
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if (200..<300).contains(status) {
                        self.log.notice("Absturzbericht gesendet")
                        self.markHandled(until: handledUntil)
                    } else if (400..<500).contains(status), status != 429 {
                        self.log.error("Absturzbericht abgelehnt: \(status, privacy: .public)")
                        self.markHandled(until: handledUntil)
                    } else {
                        self.log.error("Absturzbericht nicht gesendet: \(status, privacy: .public) \(error?.localizedDescription ?? "", privacy: .public)")
                    }
                }
            }
        }.resume()
    }

    private func markHandled(until date: Date) {
        let current = settings.settings.crashReports.handledUntil ?? .distantPast
        if date > current { settings.settings.crashReports.handledUntil = date }
    }

    private static func candidates() -> [CrashReportScan.Candidate] {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
        let name = ProcessInfo.processInfo.processName
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.compactMap { url in
            guard CrashReportScan.isOwnReport(url.lastPathComponent, processName: name),
                  let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { return nil }
            return .init(url: url, modified: modified)
        }
    }

    nonisolated private static func prepare(_ candidate: CrashReportScan.Candidate,
                                            install: String) async -> CrashReportUpload? {
        guard let raw = try? String(contentsOf: candidate.url, encoding: .utf8),
              let report = CrashReportSanitizer.sanitize(raw) else { return nil }
        var context: String?
        if let pid = report.pid,
           let result = await Subprocess.output("/usr/bin/log", CrashLogContext.arguments(
               pid: pid, crashedAt: report.crashedAt, launchedAt: report.launchedAt)) {
            context = CrashLogContext.lines(fromNDJSON: result.text)
        }
        return CrashReportUpload(report, install: install, context: context)
    }

    private static func preview(_ upload: CrashReportUpload) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 460, height: 180)
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            var parts = ["ApolloShell \(upload.appVersion) (\(upload.build)), \(upload.os), \(upload.arch), \(upload.install)",
                         upload.report]
            if let context = upload.context { parts.append(context) }
            text.string = parts.joined(separator: "\n\n")
        }
        return scroll
    }
}
