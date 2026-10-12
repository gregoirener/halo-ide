import SwiftUI

struct SourceControlView: View {
    @Bindable var workspace: Workspace
    @Bindable var scm: SourceControl
    @FocusState private var messageFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if workspace.root == nil {
                    emptyState
                } else if !scm.isRepository {
                    notARepository
                } else {
                    branchBar
                    commitBox
                    if let error = scm.lastError { errorBanner(error) }
                    if !scm.staged.isEmpty {
                        changeSection("Staged Changes", scm.staged, staged: true)
                    }
                    changeSection("Changes", scm.unstaged, staged: false)
                    githubSection
                    if !scm.commits.isEmpty { historySection }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .onAppear { scm.refresh(folder: workspace.root) }
    }

    // MARK: Pieces

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open a folder to use source control.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.haloSecondary)
            Button("Clone Repository…") { workspace.cloneRepository() }
                .buttonStyle(.glass)
        }
        .padding(.top, 8)
    }

    private var notARepository: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This folder isn’t tracked by Git yet.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.haloSecondary)
            Button { scm.initialize() } label: {
                Text("Initialize Repository").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.haloAction)
            .disabled(Git.executable == nil)
            Button { workspace.publishToGitHub() } label: {
                Text("Publish to GitHub").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            if Git.executable == nil {
                Text("Git isn’t installed. Run xcode-select --install in the terminal.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.haloTertiary)
            }
        }
        .padding(.top, 8)
    }

    private var branchBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(scm.branches, id: \.self) { branch in
                    Button {
                        scm.checkout(branch)
                    } label: {
                        if branch == scm.branch { Label(branch, systemImage: "checkmark") } else { Text(branch) }
                    }
                }
                Divider()
                Button("New Branch…") {
                    if let name = askText(title: "New Branch", message: "Create and switch to a new branch.", placeholder: "feature/my-change") {
                        scm.createBranch(name)
                    }
                }
            } label: {
                Label(scm.branch ?? "main", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            if scm.isBusy { ProgressView().controlSize(.small) }

            if scm.hasRemote {
                Button {
                    if scm.behind > 0 { scm.pull() } else { scm.push() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        if scm.behind > 0 { Text("\(scm.behind)↓") }
                        if scm.ahead > 0 { Text("\(scm.ahead)↑") }
                    }
                    .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(scm.upstream == nil ? "Push and set upstream" : "Sync with \(scm.upstream ?? "remote")")
                .disabled(scm.isBusy)
            }
        }
        .padding(.top, 4)
    }

    private var commitBox: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if scm.message.isEmpty {
                    Text("Message (⌘↩ to commit)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.haloTertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $scm.message)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .focused($messageFocused)
                    .frame(minHeight: 52, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(messageFocused ? Color.haloSky.opacity(0.5) : Color.haloHairline))

            Button {
                scm.commit { ok in if ok { workspace.showToast("Committed") } }
            } label: {
                HStack {
                    Image(systemName: "checkmark")
                    Text(scm.staged.isEmpty && !scm.changes.isEmpty ? "Commit All" : "Commit")
                }
                .font(.system(size: 12.5, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.haloAction)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(scm.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scm.changes.isEmpty || scm.isBusy)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(nsColor: Palette.warning))
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.system(size: 11.5)).foregroundStyle(Color.haloSecondary).lineLimit(6).textSelection(.enabled)
                if text.localizedCaseInsensitiveContains("auth") || text.localizedCaseInsensitiveContains("credential") || text.contains("could not read Username") {
                    Button("Sign in to GitHub") { workspace.githubSignIn() }.buttonStyle(.glass).controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(nsColor: Palette.warning).opacity(0.08)))
    }

    private func changeSection(_ title: String, _ items: [GitFileChange], staged: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionTitle(title, count: items.count)
                Spacer()
                if !items.isEmpty {
                    if staged {
                        IconButton(symbol: "minus", label: "Unstage All", size: 11) { scm.unstageAll() }
                    } else {
                        IconButton(symbol: "plus", label: "Stage All", size: 11) { scm.stageAll() }
                    }
                }
            }
            if items.isEmpty {
                Text(staged ? "" : "No changes")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.haloTertiary)
                    .padding(.leading, 4)
                    .padding(.vertical, 4)
            }
            ForEach(items) { change in
                ChangeRow(change: change, staged: staged, workspace: workspace, scm: scm)
            }
        }
    }

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("GitHub")
            if scm.ghPath == nil {
                Text("Connect GitHub with the GitHub CLI to publish, open pull requests and clone.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.haloSecondary)
                Button("Install GitHub CLI") { workspace.installGitHubCLI() }.buttonStyle(.glass).controlSize(.small)
            } else if let account = scm.ghAccount {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(Color.haloAdded)
                    Text(account).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.haloText)
                    Spacer()
                    if scm.repoSlug != nil {
                        IconButton(symbol: "arrow.up.forward.square", label: "Open on GitHub", size: 11) { workspace.openOnGitHub() }
                    }
                }
                if !scm.hasRemote {
                    Button("Publish to GitHub…") { workspace.publishToGitHub() }.buttonStyle(.glass).controlSize(.small)
                } else {
                    HStack(spacing: 6) {
                        Button("New Pull Request") { workspace.createPullRequest(onWeb: false) }.buttonStyle(.glass).controlSize(.small)
                        Button("On GitHub.com") { workspace.createPullRequest(onWeb: true) }.buttonStyle(.glass).controlSize(.small)
                    }
                }
                if !scm.pullRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(scm.pullRequests) { pr in
                            PullRequestRow(pr: pr) {
                                if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) }
                            }
                            .contextMenu {
                                Button("Open on GitHub") { if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) } }
                                Button("Check Out Locally") { workspace.checkoutPullRequest(pr) }
                            }
                        }
                    }
                }
            } else {
                Text("Sign in once and Halo can publish repositories, create pull requests and push without passwords.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.haloSecondary)
                Button("Sign in to GitHub") { workspace.githubSignIn() }.buttonStyle(.glass).controlSize(.small)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionTitle("History")
            ForEach(scm.commits.prefix(15)) { commit in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(commit.hash)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.haloTertiary)
                    Text(commit.subject)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.haloText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(commit.date.replacingOccurrences(of: " ago", with: ""))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.haloTertiary)
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .help("\(commit.subject)\n\(commit.author) · \(commit.date)")
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    var count: Int?
    init(_ title: String, count: Int? = nil) { self.title = title; self.count = count }
    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.haloSecondary)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.haloSecondary)
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChangeRow: View {
    let change: GitFileChange
    let staged: Bool
    @Bindable var workspace: Workspace
    @Bindable var scm: SourceControl
    @State private var hovering = false

    var body: some View {
        let letter = staged ? change.stagedLetter : change.unstagedLetter
        HStack(spacing: 6) {
            FileIconView(url: change.url, size: 14)
            Text(change.url.lastPathComponent)
                .font(.system(size: 12.5))
                .foregroundStyle(letter == "D" ? Color.haloTertiary : Color.haloText)
                .strikethrough(letter == "D")
                .lineLimit(1)
            Text((change.path as NSString).deletingLastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(Color.haloTertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            if hovering {
                if !staged {
                    IconButton(symbol: "arrow.uturn.backward", label: change.isUntracked ? "Move to Trash" : "Discard Changes", size: 10.5) { scm.discard(change) }
                }
                IconButton(symbol: staged ? "minus" : "plus", label: staged ? "Unstage" : "Stage", size: 10.5) {
                    if staged { scm.unstage(change) } else { scm.stage(change) }
                }
            }
            Text(letter)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(color(letter))
                .frame(width: 12)
        }
        .padding(.horizontal, 4)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if FileManager.default.fileExists(atPath: change.url.path) { workspace.open(change.url) } }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func color(_ letter: String) -> Color {
        switch letter {
        case "A", "U": .haloAdded
        case "D": Color(nsColor: Palette.error)
        default: .haloModified
        }
    }
}

private struct PullRequestRow: View {
    let pr: PullRequest
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: pr.isDraft ? "circle.dashed" : "arrow.triangle.pull")
                    .font(.system(size: 11))
                    .foregroundStyle(pr.isDraft ? Color.haloTertiary : Color.haloAdded)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.title).font(.system(size: 12)).foregroundStyle(Color.haloText).lineLimit(1)
                    Text("#\(pr.number) · \(pr.headRefName) · \(pr.author.login)")
                        .font(.system(size: 10.5)).foregroundStyle(Color.haloTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

@MainActor
func askText(title: String, message: String, placeholder: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(string: "")
    field.placeholderString = placeholder
    field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}
