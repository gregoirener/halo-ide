import AppKit
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case terminal, problems, output, debugConsole
    var id: String { rawValue }
    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .problems: "Problems"
        case .output: "Output"
        case .debugConsole: "Debug Console"
        }
    }
}

extension Workspace {
    // MARK: Bottom panel

    func showPanel(_ tab: PanelTab) {
        withAnimation(Motion.snappy) {
            panelTab = tab
            showTerminal = true
        }
        if tab == .terminal { terminal.startIfNeeded(in: root) }
    }

    func runInTerminal(_ command: String) {
        showPanel(.terminal)
        let fresh = terminal.startIfNeeded(in: root)
        // A brand-new login shell needs a moment to print its prompt.
        DispatchQueue.main.asyncAfter(deadline: .now() + (fresh ? 0.8 : 0.05)) { [weak self] in
            self?.terminal.run(command)
            self?.terminal.focus()
        }
    }

    // MARK: Run

    var canRun: Bool { active?.url != nil && active?.kind == .text }

    func runActive() {
        guard let doc = active else { return }
        guard let url = doc.url else { showToast("Save the file to run it"); return }
        if doc.isDirty { guard save(doc) else { return } }
        if debug?.isActive == true { debug?.stop() }
        switch Runner.plan(for: url, language: doc.language, root: root) {
        case .failure(let error):
            presentRunError(error)
        case .success(let plan):
            guard let compile = plan.compile else { runInTerminal(plan.command); return }
            isBuilding = true
            buildLog = ["$ " + compile.map { $0.contains(" ") ? Runner.q($0) : $0 }.joined(separator: " ")]
            let path = url.standardizedFileURL.path
            Task {
                let result = await Runner.build(compile, cwd: plan.cwd)
                self.isBuilding = false
                self.buildLog += result.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                self.applyBuildDiagnostics(result.diagnostics, for: [path])
                if result.ok {
                    self.buildLog.append("Build succeeded.")
                    self.runInTerminal(plan.command)
                } else {
                    let errors = result.diagnostics.filter { $0.severity == .error }.count
                    self.buildLog.append("Build failed.")
                    self.showPanel(errors > 0 ? .problems : .output)
                    self.showToast(errors == 1 ? "Build failed — 1 error" : "Build failed — \(max(errors, 1)) errors")
                }
            }
        }
    }

    func stopRunning() {
        if debug?.isActive == true { debug?.stop() } else { terminal.interrupt() }
    }

    private func presentRunError(_ error: RunError) {
        let alert = NSAlert()
        alert.messageText = error.localizedDescription
        if let hint = error.installHint {
            alert.informativeText = "Halo can run the installer in the terminal:\n\(hint)"
            alert.addButton(withTitle: "Install in Terminal")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { runInTerminal(hint) }
        } else {
            alert.runModal()
        }
    }

    // MARK: Debug

    func startDebugging() {
        if let debug, debug.isActive {
            if debug.state == .stopped { debug.resume() }
            return
        }
        guard let doc = active else { return }
        guard let url = doc.url else { showToast("Save the file to debug it"); return }
        guard DebugSession.supports(doc.language) else {
            showToast("Debugging \(doc.language.name) isn’t supported yet — try ⌘R")
            return
        }
        if doc.isDirty { guard save(doc) else { return } }
        let session = DebugSession(fileURL: url.standardizedFileURL, language: doc.language, workspace: self)
        debug = session
        withAnimation(Motion.gentle) {
            sidebarMode = .debug
            if columnVisibility == .detailOnly { columnVisibility = .all }
        }
        showPanel(.debugConsole)
        session.start()
    }

    func offerDebugpyInstall(python: String) {
        let alert = NSAlert()
        alert.messageText = "Install the Python debugger?"
        alert.informativeText = "Halo debugs Python with debugpy — the same debugger VS Code uses. It will be installed with pip for:\n\(python)"
        alert.addButton(withTitle: "Install in Terminal")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            runInTerminal("\(Runner.q(python)) -m pip install debugpy")
        }
    }

    func toggleBreakpoint(path: String, line: Int) {
        var lines = breakpoints[path] ?? []
        if lines.contains(line) { lines.remove(line) } else { lines.insert(line) }
        breakpoints[path] = lines
        debug?.sendBreakpoints(path: path, lines: lines)
    }

    func toggleBreakpointAtCaret() {
        guard let doc = active, let url = doc.url else { return }
        toggleBreakpoint(path: url.standardizedFileURL.path, line: doc.cursorLine)
    }

    func removeAllBreakpoints() {
        for path in breakpoints.keys { debug?.sendBreakpoints(path: path, lines: []) }
        breakpoints = [:]
    }

    // MARK: Problems

    func applyBuildDiagnostics(_ list: [Diagnostic], for paths: [String]) {
        for path in paths { buildDiagnostics[path] = [] }
        for d in list { buildDiagnostics[d.path, default: []].append(d) }
        recomputeDiagnostics()
    }

    func recomputeDiagnostics() {
        var merged: [String: [Diagnostic]] = [:]
        for path in Set(lintDiagnostics.keys).union(buildDiagnostics.keys) {
            var seen = Set<String>()
            var list: [Diagnostic] = []
            for d in (buildDiagnostics[path] ?? []) + (lintDiagnostics[path] ?? []) {
                let key = "\(d.line):\(d.message)"
                if seen.insert(key).inserted { list.append(d) }
            }
            if !list.isEmpty { merged[path] = list.sorted { ($0.line, $0.severity) < ($1.line, $1.severity) } }
        }
        diagnostics = merged
    }

    var problemCounts: (errors: Int, warnings: Int) {
        var e = 0, w = 0
        for list in diagnostics.values {
            for d in list { if d.severity == .error { e += 1 } else if d.severity == .warning { w += 1 } }
        }
        return (e, w)
    }

    func scheduleLint(_ doc: Document) {
        guard let url = doc.url, Linter.supports(doc.language) else { return }
        let path = url.standardizedFileURL.path
        lintWork[path]?.cancel()
        let work = DispatchWorkItem { [weak self, weak doc] in
            guard let self, let doc, let editor = doc.editor else { return }
            let text = editor.text
            let language = doc.language
            let root = self.root
            Task {
                let found = await Linter.lint(text: text, url: url, language: language, root: root)
                guard editor.text == text else { return }       // edited since; a newer pass is coming
                // The line you're still typing is allowed to be incomplete.
                let typingLine = self.unattendedEdits.remove(path) == nil ? doc.cursorLine : -1
                self.lintDiagnostics[path] = found.filter { $0.line != typingLine || $0.severity != .error }
                self.pendingLint[path] = found.contains { $0.line == typingLine && $0.severity == .error } ? typingLine : nil
                self.buildDiagnostics[path] = nil               // edits make old build errors stale
                self.recomputeDiagnostics()
            }
        }
        lintWork[path] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Checks a document right away, holding nothing back (after Claude edits it).
    @discardableResult
    func lintNow(_ doc: Document) async -> [Diagnostic] {
        guard let url = doc.url, Linter.supports(doc.language), let editor = doc.editor else { return [] }
        let path = url.standardizedFileURL.path
        lintWork[path]?.cancel()
        let text = editor.text
        let found = await Linter.lint(text: text, url: url, language: doc.language, root: root)
        guard editor.text == text else { return found }
        unattendedEdits.remove(path)
        lintDiagnostics[path] = found
        pendingLint[path] = nil
        buildDiagnostics[path] = nil
        recomputeDiagnostics()
        return found
    }

    // MARK: Source control

    func refreshLineChanges(for doc: Document?) {
        guard let doc, let url = doc.url, scm.isRepository || Git.repoRoot(for: url) != nil else { return }
        let path = url.standardizedFileURL.path
        let untracked = scm.changes.contains { $0.url.standardizedFileURL.path == path && $0.isUntracked }
        Task.detached(priority: .utility) {
            let changes = SourceControl.lineChanges(for: url, untracked: untracked)
            await MainActor.run { [weak self] in self?.lineChanges[path] = changes }
        }
    }

    func cloneRepository() {
        let alert = NSAlert()
        alert.messageText = "Clone Repository"
        alert.informativeText = "A GitHub owner/name (with the GitHub CLI) or any Git URL."
        alert.addButton(withTitle: "Choose Folder…")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "")
        field.placeholderString = "owner/repository or https://…"
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let source = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Clone Here"
        panel.message = "Choose where to put the repository"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        var name = (source as NSString).lastPathComponent
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        let destination = parent.appendingPathComponent(name)

        let isURL = source.contains("://") || source.hasPrefix("git@")
        let argv: [String]
        if !isURL, let gh = Tools.find("gh") {
            argv = [gh, "repo", "clone", source, destination.path]
        } else if let git = Git.executable {
            argv = [git, "clone", isURL ? source : "https://github.com/\(source).git", destination.path]
        } else {
            showToast("Git isn’t installed")
            return
        }
        showToast("Cloning \(name)…")
        Task.detached(priority: .userInitiated) {
            let (code, output) = Shell.run(argv, environment: ["GIT_TERMINAL_PROMPT": "0"], timeout: 600)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if code == 0 {
                    self.openFolder(destination)
                    self.showToast("Cloned \(name)")
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Couldn’t clone \(name)"
                    alert.informativeText = output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(600).description
                    alert.runModal()
                }
            }
        }
    }

    func githubSignIn() {
        guard scm.ghPath != nil else { installGitHubCLI(); return }
        runInTerminal("gh auth login --hostname github.com --web --git-protocol https && gh auth setup-git")
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.scm.refreshGitHub() }
    }

    func installGitHubCLI() {
        if Tools.find("brew") != nil {
            runInTerminal("brew install gh")
        } else {
            NSWorkspace.shared.open(URL(string: "https://cli.github.com")!)
        }
    }

    func publishToGitHub() {
        guard let root else { return }
        guard scm.ghPath != nil else { installGitHubCLI(); return }
        let alert = NSAlert()
        alert.messageText = "Publish to GitHub"
        alert.informativeText = "Creates a repository on your GitHub account and pushes this folder to it."
        alert.addButton(withTitle: "Publish")
        alert.addButton(withTitle: "Cancel")
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        let name = NSTextField(string: root.lastPathComponent)
        name.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let privacy = NSButton(checkboxWithTitle: "Private repository", target: nil, action: nil)
        privacy.state = .on
        stack.addArrangedSubview(name)
        stack.addArrangedSubview(privacy)
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 56)
        alert.accessoryView = stack
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let repoName = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoName.isEmpty else { return }
        var steps = ["cd \(Runner.q(root.path))"]
        if !scm.isRepository { steps.append("git init -b main") }
        if scm.commits.isEmpty { steps.append("git add -A && git commit -m 'Initial commit'") }
        steps.append("gh repo create \(Runner.q(repoName)) --\(privacy.state == .on ? "private" : "public") --source . --remote origin --push")
        runInTerminal(steps.joined(separator: " && "))
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.scm.refresh(folder: root) }
    }

    func createPullRequest(onWeb: Bool) {
        guard let root else { return }
        guard scm.ghPath != nil else { installGitHubCLI(); return }
        runInTerminal("cd \(Runner.q(root.path)) && gh pr create --fill" + (onWeb ? " --web" : ""))
    }

    func checkoutPullRequest(_ pr: PullRequest) {
        guard let root else { return }
        runInTerminal("cd \(Runner.q(root.path)) && gh pr checkout \(pr.number)")
    }

    func openOnGitHub() {
        guard let slug = scm.repoSlug, let url = URL(string: "https://github.com/\(slug)") else { return }
        NSWorkspace.shared.open(url)
    }
}
