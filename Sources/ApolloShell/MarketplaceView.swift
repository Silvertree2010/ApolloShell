import ApolloShellCore
import SwiftUI

/// The Marketplace sheet behind Nexus > Themes: browse and install themes,
/// sign in with GitHub, submit your own, and - for the admin - review.
struct MarketplaceView: View {
    @State var store: MarketplaceStore
    let themes: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    enum Tab: Hashable { case browse, mine, review }
    @State private var tab: Tab = .browse
    @State private var detail: MarketTheme?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch tab {
                case .browse: browse
                case .mine: MarketplaceMineView(store: store, themes: themes)
                case .review: MarketplaceReviewView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 760, height: 580)
        .task { await store.refresh() }
        .sheet(item: $detail) { theme in
            MarketplaceDetailView(store: store, theme: theme)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } }
        )) {
            Button("OK") { store.actionError = nil }
        } message: {
            Text(store.actionError ?? "")
        }
        .alert(store.notice ?? "", isPresented: Binding(
            get: { store.notice != nil }, set: { if !$0 { store.notice = nil } }
        )) {
            Button("OK") { store.notice = nil }
        }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 12) {
            Text("Marketplace").font(.title2.weight(.bold))
            Picker("", selection: $tab) {
                Text("Browse").tag(Tab.browse)
                Text("My themes").tag(Tab.mine)
                if store.user?.isAdmin == true {
                    Text("Review (\(store.queue.count))").tag(Tab.review)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            MarketplaceAccountButton(store: store)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Link("Terms", destination: URL(string: "https://silvertree2010.github.io/ApolloShell/terms.html")!)
            Link("Privacy", destination: URL(string: "https://silvertree2010.github.io/ApolloShell/privacy.html")!)
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .font(.callout)
        .padding(12)
    }

    // MARK: Browse

    @ViewBuilder
    private var browse: some View {
        switch store.load {
        case .idle:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading where store.themes.isEmpty:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message) where store.themes.isEmpty:
            ContentUnavailableView {
                Label("Marketplace unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await store.refresh() } }
            }
        default:
            if store.themes.isEmpty {
                ContentUnavailableView("No themes yet", systemImage: "paintpalette",
                                       description: Text("Be the first: submit one under My themes."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(store.themes) { theme in
                            MarketplaceCard(store: store, theme: theme, dark: colorScheme == .dark) {
                                detail = theme
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

// MARK: - Card

private struct MarketplaceCard: View {
    let store: MarketplaceStore
    let theme: MarketTheme
    let dark: Bool
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                ThemePreview(theme: .marketplace(theme), dark: dark)
            }
            .buttonStyle(.plain)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.name).font(.headline).lineLimit(1)
                    Text("by \(theme.author)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                MarketplaceInstallButton(store: store, theme: theme)
            }
        }
    }
}

struct MarketplaceInstallButton: View {
    let store: MarketplaceStore
    let theme: MarketTheme

    var body: some View {
        switch store.state(of: theme) {
        case .notInstalled:
            Button("Get") { store.install(theme) }
                .buttonStyle(.borderedProminent)
        case .updateAvailable:
            Button("Update") { store.install(theme) }
                .buttonStyle(.borderedProminent)
        case .installed:
            Button("Use") { store.apply(theme) }
        }
    }
}

// MARK: - Detail

private struct MarketplaceDetailView: View {
    let store: MarketplaceStore
    let theme: MarketTheme
    @Environment(\.dismiss) private var dismiss
    @State private var reporting = false
    @State private var reportReason = ""

    var body: some View {
        let preview = Theme.marketplace(theme)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    ThemePreview(theme: preview, dark: false)
                    Text("Light").font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    ThemePreview(theme: preview, dark: true)
                    Text("Dark").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.name).font(.title2.weight(.bold))
                Text("by \(theme.author) · version \(theme.version)").foregroundStyle(.secondary)
                if !theme.description.isEmpty { Text(theme.description) }
                Text(theme.attribution.isEmpty ? "License: \(theme.license)"
                                               : "License: \(theme.license) · \(theme.attribution)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Report…") { reporting = true }
                if store.state(of: theme) != .notInstalled {
                    Button("Remove", role: .destructive) { store.uninstall(theme) }
                }
                Spacer()
                Button("Close") { dismiss() }
                MarketplaceInstallButton(store: store, theme: theme)
            }
        }
        .padding(20)
        .frame(width: 620)
        .alert("Report this theme", isPresented: $reporting) {
            TextField("What is wrong with it?", text: $reportReason)
            Button("Send") {
                let reason = reportReason
                reportReason = ""
                Task { await store.report(theme, reason: reason) }
            }
            Button("Cancel", role: .cancel) { reportReason = "" }
        } message: {
            Text("For content that is illegal, offensive or copies someone else's work. A theme reported three times is hidden until it is reviewed.")
        }
    }
}

// MARK: - Account

private struct MarketplaceAccountButton: View {
    let store: MarketplaceStore
    @State private var confirmsDelete = false

    var body: some View {
        if let user = store.user {
            Menu("@\(user.login)") {
                Button("Sign out") { Task { await store.signOut() } }
                Divider()
                Button("Delete account and themes…", role: .destructive) { confirmsDelete = true }
            }
            .fixedSize()
            .confirmationDialog("Delete your Marketplace account?", isPresented: $confirmsDelete) {
                Button("Delete", role: .destructive) { Task { await store.deleteAccount() } }
            } message: {
                Text("Your themes leave the Marketplace. Copies others installed stay on their Macs.")
            }
        } else {
            MarketplaceSignInButton(store: store)
        }
    }
}

struct MarketplaceSignInButton: View {
    let store: MarketplaceStore

    var body: some View {
        switch store.signIn {
        case .idle:
            Button("Sign in with GitHub") { store.startSignIn() }
                .disabled(!store.signInAvailable)
                .help(store.signInAvailable ? "" : "Sign-in is not set up in this build yet.")
        case let .waiting(code):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Enter").foregroundStyle(.secondary)
                Text(code.userCode).font(.body.monospaced().weight(.semibold)).textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                }
                Button("Cancel") { store.cancelSignIn() }
            }
        case let .failed(message):
            HStack(spacing: 8) {
                Text(message).foregroundStyle(.secondary).lineLimit(1)
                Button("Try again") { store.startSignIn() }
            }
        }
    }
}

// MARK: - My themes

private struct MarketplaceMineView: View {
    let store: MarketplaceStore
    let themes: ThemeStore
    @State private var submitting = false
    @State private var replacing: MarketOwnTheme?

    var body: some View {
        if !store.isSignedIn {
            ContentUnavailableView {
                Label("Share your themes", systemImage: "square.and.arrow.up")
            } description: {
                Text("Sign in with GitHub to submit a theme. The Marketplace only sees your public GitHub profile.")
            } actions: {
                MarketplaceSignInButton(store: store)
            }
        } else {
            List {
                Section {
                    Button("Submit a theme…") { submitting = true }
                } footer: {
                    Text("A new theme, or a new name or description, is reviewed before it goes live. New colours for a published theme go live at once.")
                }
                Section("Yours") {
                    if store.mine.isEmpty {
                        Text("Nothing submitted yet.").foregroundStyle(.secondary)
                    }
                    ForEach(store.mine) { own in
                        HStack(spacing: 12) {
                            ThemePreview(theme: .marketplace(own.theme), dark: false).frame(width: 96)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(own.name).font(.headline)
                                Text(status(of: own)).font(.callout).foregroundStyle(.secondary)
                                if let reason = own.reason, !reason.isEmpty {
                                    Text(reason).font(.callout).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button("New version…") { replacing = own }
                            Button("Delete", role: .destructive) { Task { await store.delete(own) } }
                        }
                    }
                }
            }
            .sheet(isPresented: $submitting) {
                MarketplaceSubmitView(store: store, themes: themes, replacing: nil)
            }
            .sheet(item: $replacing) { own in
                MarketplaceSubmitView(store: store, themes: themes, replacing: own)
            }
        }
    }

    private func status(of own: MarketOwnTheme) -> String {
        switch own.status {
        case .pending: String(localized: "Waiting for review · version \(own.version)")
        case .published: String(localized: "Live · version \(own.version)")
        case .rejected: String(localized: "Not accepted")
        case .hidden: String(localized: "Hidden")
        }
    }
}

private struct MarketplaceSubmitView: View {
    let store: MarketplaceStore
    let themes: ThemeStore
    let replacing: MarketOwnTheme?
    @Environment(\.dismiss) private var dismiss
    @State private var choice: String?
    @State private var agreed = false
    @State private var sending = false

    private var chosen: Theme? { themes.available.first { $0.identifier == choice } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(replacing.map { "New version of \($0.name)" } ?? String(localized: "Submit a theme"))
                .font(.title2.weight(.bold))
            Picker("Theme", selection: $choice) {
                Text("Choose…").tag(String?.none)
                ForEach(themes.available, id: \.identifier) { theme in
                    Text(theme.title).tag(Optional(theme.identifier))
                }
            }
            if let chosen {
                HStack(spacing: 12) {
                    ThemePreview(theme: chosen, dark: false)
                    ThemePreview(theme: chosen, dark: true)
                }
                switch store.canonical(for: chosen) {
                case .success:
                    if chosen.value(ThemeTextToken.themeName)?.isEmpty ?? true {
                        Label("Give it a name first: --apollo-theme-name in the file.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                case .failure(.usesFiles):
                    Label("This theme uses images. The Marketplace takes plain CSS themes only for now.",
                          systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                case .failure(.noTokens):
                    Label("There is nothing in this theme the shell knows.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Toggle(isOn: $agreed) {
                Text("I made this theme or may share it, and publish it under CC0 (free for anyone to use). I agree to the Terms.")
            }
            Text("The preview is made from the theme itself. Author, homepage and anything the shell does not know are left out.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(replacing == nil ? "Submit" : "Upload") {
                    guard let chosen else { return }
                    sending = true
                    Task {
                        await store.submit(chosen, replacing: replacing)
                        sending = false
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend || sending)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var canSend: Bool {
        guard agreed, let chosen, case .success = store.canonical(for: chosen) else { return false }
        return !(chosen.value(ThemeTextToken.themeName)?.isEmpty ?? true)
    }
}

// MARK: - Review (admin)

private struct MarketplaceReviewView: View {
    let store: MarketplaceStore
    @State private var asking: (MarketQueueItem, Action)?
    @State private var reason = ""

    enum Action { case reject, hide, ban }

    var body: some View {
        if store.queue.isEmpty {
            ContentUnavailableView("Nothing to review", systemImage: "checkmark.seal")
        } else {
            List(store.queue) { item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        ThemePreview(theme: .marketplace(item.theme.theme), dark: false).frame(width: 150)
                        ThemePreview(theme: .marketplace(item.theme.theme), dark: true).frame(width: 150)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.theme.name).font(.headline)
                        Text("by \(item.theme.author) · version \(item.theme.version) · \(item.theme.status.rawValue)")
                            .font(.callout).foregroundStyle(.secondary)
                        if !item.theme.description.isEmpty { Text(item.theme.description) }
                        if item.previousCSS != nil {
                            Text("Update: name or description changed.").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(Array(item.reports.enumerated()), id: \.offset) { _, report in
                            Text("Report: \(report.reason)").font(.callout).foregroundStyle(.orange)
                        }
                        HStack {
                            if item.theme.status == .hidden {
                                Button("Show again") { Task { await store.decide(.unhide, item) } }
                            } else {
                                Button("Approve") { Task { await store.decide(.approve, item) } }
                                    .buttonStyle(.borderedProminent)
                                Button("Reject…") { ask(item, .reject) }
                                Button("Hide…") { ask(item, .hide) }
                            }
                            Button("Ban author…", role: .destructive) { ask(item, .ban) }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }
            .alert("Reason", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
                TextField("Shown to the author", text: $reason)
                Button("Send") { send() }.disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { asking = nil; reason = "" }
            } message: {
                Text("The author sees this reason.")
            }
        }
    }

    private func ask(_ item: MarketQueueItem, _ action: Action) {
        reason = ""
        asking = (item, action)
    }

    private func send() {
        guard let (item, action) = asking else { return }
        let text = reason
        asking = nil
        reason = ""
        Task {
            switch action {
            case .reject: await store.decide(.reject, item, reason: text)
            case .hide: await store.decide(.hide, item, reason: text)
            case .ban: await store.ban(authorOf: item, reason: text)
            }
        }
    }
}
