import AppKit
import Observation

struct GitFileChange: Identifiable, Hashable {
    let path: String           // relative to the repository root
    let url: URL
    let index: Character       // staged state (X)
    let worktree: Character    // unstaged state (Y)
    var id: String { path }

    var isUntracked: Bool { index == "?" }
    var isStaged: Bool { index != " " && index != "?" }
    var isUnstaged: Bool { worktree != " " || isUntracked }
    var stagedLetter: String { String(index) }
    var unstagedLetter: String { isUntracked ? "U" : String(worktree) }
}

struct GitCommit: Identifiable, Hashable {
    let hash: String
    let subject: String
    let author: String
    let date: String
    var id: String { hash }
}

struct PullRequest: Identifiable, Hashable, Decodable {
    struct Author: Hashable, Decodable { let login: String }
    let number: Int
    let title: String
    let headRefName: String
    let url: String
    let isDraft: Bool
    let author: Author
    var id: Int { number }
}

/// Git and GitHub for the open folder. Read-only queries run headless;
/// anything interactive (sign-in, publishing) runs visibly in the terminal.
@Observable @MainActor
final class SourceControl {
    private(set) var repoRoot: URL?
    private(set) var branch: String?
    private(set) var upstream: String?
    private(set) var ahead = 0
    private(set) var behind = 0
    private(set) var changes: [GitFileChange] = []
    private(set) var branches: [String] = []
    private(set) var commits: [GitCommit] = []
    private(set) var hasRemote = false
    private(set) var repoSlug: String?
    private(set) var isBusy = false
    private(set) var lastError: String?
    var message = ""

    private(set) var ghPath: String? = Tools.find("gh")
    private(set) var ghAccount: String?
    private(set) var pullRequests: [PullRequest] = []

    var staged: [GitFileChange] { changes.filter(\.isStaged) }
    var unstaged: [GitFileChange] { changes.filter(\.isUnstaged) }
    var isRepository: Bool { repoRoot != nil }

    @ObservationIgnored private var folder: URL?

    // MARK: Queries

    func refresh(folder: URL?) {
        self.folder = folder
        guard let folder, let git = Git.executable else {
            repoRoot = nil; changes = []; branches = []; commits = []; branch = nil
            return
        }
        Task.detached(priority: .utility) {
            let repo = Git.repoRoot(for: folder)
            var snapshot = Snapshot()
            if let repo {
                snapshot = Self.load(git: git, repo: repo)
            }
            await MainActor.run { [weak self] in
                guard let self, self.folder == folder else { return }
                self.repoRoot = repo
                self.apply(snapshot)
            }
        }
        refreshGitHub()
    }

    private struct Snapshot: Sendable {
        var branch: String?
        var upstream: String?
        var ahead = 0, behind = 0
        var changes: [GitFileChange] = []
        var branches: [String] = []
        var commits: [GitCommit] = []
        var remoteURL: String?
    }

    nonisolated private static func load(git: String, repo: URL) -> Snapshot {
        var s = Snapshot()
        let (_, status) = Shell.run([git, "-C", repo.path, "status", "--porcelain=v1", "-z", "-b", "--untracked-files=all"])
        var entries = status.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        if let head = entries.first, head.hasPrefix("## ") {
            entries.removeFirst()
            let info = head.dropFirst(3)
            let parts = info.components(separatedBy: "...")
            s.branch = parts[0].replacingOccurrences(of: "No commits yet on ", with: "")
            if parts.count > 1 {
                let rest = parts[1]
                s.upstream = rest.split(separator: " ").first.map(String.init)
                if let m = rest.range(of: #"ahead (\d+)"#, options: .regularExpression) { s.ahead = Int(rest[m].dropFirst(6)) ?? 0 }
                if let m = rest.range(of: #"behind (\d+)"#, options: .regularExpression) { s.behind = Int(rest[m].dropFirst(7)) ?? 0 }
            }
        }
        var i = 0
        while i < entries.count {
            let e = entries[i]
            i += 1
            guard e.count > 3 else { continue }
            let x = e[e.startIndex], y = e[e.index(after: e.startIndex)]
            let path = String(e.dropFirst(3))
            if x == "R" || x == "C" { i += 1 }
            s.changes.append(GitFileChange(path: path, url: repo.appendingPathComponent(path), index: x, worktree: y))
        }
        let (_, branchList) = Shell.run([git, "-C", repo.path, "branch", "--format=%(refname:short)"])
        s.branches = branchList.split(separator: "\n").map(String.init)
        let (_, log) = Shell.run([git, "-C", repo.path, "log", "-n", "25", "--pretty=format:%h%x1f%s%x1f%an%x1f%ar"])
        s.commits = log.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            return f.count == 4 ? GitCommit(hash: f[0], subject: f[1], author: f[2], date: f[3]) : nil
        }
        let (code, remote) = Shell.run([git, "-C", repo.path, "remote", "get-url", "origin"])
        if code == 0 { s.remoteURL = remote.trimmingCharacters(in: .whitespacesAndNewlines) }
        return s
    }

    private func apply(_ s: Snapshot) {
        branch = s.branch
        upstream = s.upstream
        ahead = s.ahead
        behind = s.behind
        changes = s.changes
        branches = s.branches
        commits = s.commits
        hasRemote = s.remoteURL != nil
        repoSlug = s.remoteURL.flatMap(Self.slug(from:))
    }

    static func slug(from remote: String) -> String? {
        guard let r = remote.range(of: #"github\.com[:/]([^/]+)/([^/\s]+?)(\.git)?$"#, options: .regularExpression) else { return nil }
        let tail = remote[r].replacingOccurrences(of: "github.com:", with: "").replacingOccurrences(of: "github.com/", with: "")
        return tail.hasSuffix(".git") ? String(tail.dropLast(4)) : tail
    }

    /// Lines changed in a file relative to HEAD, for the gutter.
    nonisolated static func lineChanges(for url: URL, untracked: Bool) -> [LineChange] {
        guard let git = Git.executable, let repo = Git.repoRoot(for: url) else { return [] }
        if untracked {
            let count = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false).count
            return count > 0 ? [LineChange(kind: .added, lines: 1...count)] : []
        }
        let (code, diff) = Shell.run([git, "-C", repo.path, "diff", "--no-color", "--no-ext-diff", "-U0", "HEAD", "--", url.path])
        guard code == 0 else { return [] }
        var out: [LineChange] = []
        let re = try! NSRegularExpression(pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#, options: .anchorsMatchLines)
        let ns = diff as NSString
        for m in re.matches(in: diff, range: NSRange(location: 0, length: ns.length)) {
            func n(_ i: Int, _ fallback: Int) -> Int { m.range(at: i).location == NSNotFound ? fallback : Int(ns.substring(with: m.range(at: i))) ?? fallback }
            let oldCount = n(2, 1), newStart = n(3, 1), newCount = n(4, 1)
            if oldCount == 0 && newCount > 0 {
                out.append(LineChange(kind: .added, lines: newStart...(newStart + newCount - 1)))
            } else if newCount == 0 {
                out.append(LineChange(kind: .deleted, lines: max(newStart, 1)...max(newStart, 1)))
            } else {
                let modified = min(oldCount, newCount)
                out.append(LineChange(kind: .modified, lines: newStart...(newStart + modified - 1)))
                if newCount > oldCount {
                    out.append(LineChange(kind: .added, lines: (newStart + modified)...(newStart + newCount - 1)))
                }
            }
        }
        return out
    }

    // MARK: Actions

    private func git(_ args: [String], refreshAfter: Bool = true, done: ((Bool, String) -> Void)? = nil) {
        guard let repo = repoRoot ?? folder, let git = Git.executable else { return }
        isBusy = true
        lastError = nil
        Task.detached(priority: .userInitiated) {
            let (code, output) = Shell.run([git, "-C", repo.path] + args, environment: ["GIT_TERMINAL_PROMPT": "0"], timeout: 120)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isBusy = false
                if code != 0 { self.lastError = output.trimmingCharacters(in: .whitespacesAndNewlines) }
                done?(code == 0, output)
                if refreshAfter { self.refresh(folder: self.folder) }
            }
        }
    }

    func stage(_ change: GitFileChange) { git(["add", "--", change.path]) }
    func unstage(_ change: GitFileChange) { git(["restore", "--staged", "--", change.path]) }
    func stageAll() { git(["add", "-A"]) }
    func unstageAll() { git(["restore", "--staged", "."]) }

    func discard(_ change: GitFileChange) {
        let alert = NSAlert()
        alert.messageText = change.isUntracked ? "Move “\(change.url.lastPathComponent)” to the Trash?" : "Discard changes to “\(change.url.lastPathComponent)”?"
        alert.informativeText = change.isUntracked ? "This file isn’t tracked by Git. You can restore it from the Trash." : "Your unstaged changes to this file will be lost. This can’t be undone."
        alert.addButton(withTitle: change.isUntracked ? "Move to Trash" : "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if change.isUntracked {
            try? FileManager.default.trashItem(at: change.url, resultingItemURL: nil)
            refresh(folder: folder)
        } else {
            git(["restore", "--", change.path])
        }
    }

    func commit(onDone: @escaping (Bool) -> Void = { _ in }) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let commitNow = { [weak self] in
            self?.git(["commit", "-m", text]) { ok, _ in
                if ok { self?.message = "" }
                onDone(ok)
            }
        }
        if staged.isEmpty {
            git(["add", "-A"], refreshAfter: false) { ok, _ in if ok { commitNow() } else { onDone(false) } }
        } else {
            commitNow()
        }
    }

    func push(onDone: @escaping (Bool) -> Void = { _ in }) {
        git(upstream == nil ? ["push", "-u", "origin", "HEAD"] : ["push"]) { ok, _ in onDone(ok) }
    }

    func pull(onDone: @escaping (Bool) -> Void = { _ in }) { git(["pull", "--ff-only"]) { ok, _ in onDone(ok) } }
    func fetch() { git(["fetch", "--prune"]) }
    func checkout(_ branch: String) { git(["checkout", branch]) }
    func createBranch(_ name: String) { git(["checkout", "-b", name]) }
    func initialize() { git(["init", "-b", "main"]) }

    // MARK: GitHub (gh)

    func refreshGitHub() {
        ghPath = Tools.find("gh")
        guard let gh = ghPath else { ghAccount = nil; pullRequests = []; return }
        let folder = self.folder
        Task.detached(priority: .utility) {
            let (_, status) = Shell.run([gh, "auth", "status", "--hostname", "github.com"], timeout: 20)
            var account: String?
            if let r = status.range(of: #"account (\S+)"#, options: .regularExpression) {
                account = String(status[r].dropFirst(8))
            } else if let r = status.range(of: #"Logged in to github\.com as (\S+)"#, options: .regularExpression) {
                account = String(status[r].split(separator: " ").last ?? "")
            }
            var prs: [PullRequest] = []
            if account != nil, let folder {
                let (code, json) = Shell.run([gh, "pr", "list", "--json", "number,title,headRefName,url,isDraft,author", "--limit", "30"], cwd: folder, timeout: 20)
                if code == 0, let data = json.data(using: .utf8) {
                    prs = (try? JSONDecoder().decode([PullRequest].self, from: data)) ?? []
                }
            }
            await MainActor.run { [weak self] in
                self?.ghAccount = account
                self?.pullRequests = prs
            }
        }
    }
}
