import AppKit

/// The tools Claude calls, run against the focused Halo window.
@MainActor
enum MCPTools {
    struct Outcome {
        var text: String
        var isError = false
        var summary: String

        static func failure(_ message: String) -> Outcome { Outcome(text: message, isError: true, summary: message) }
    }

    struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    static func run(_ name: String, arguments args: [String: Any], client: String) async -> Outcome {
        do {
            guard let ws = WorkspaceRegistry.focused ?? WorkspaceRegistry.all.first else {
                throw Failure("Halo has no window open. Ask the user to open a project in Halo.")
            }
            switch name {
            case "get_editor_state": return editorState(ws)
            case "list_files": return try await listFiles(ws, args)
            case "read_file": return try readFile(ws, args)
            case "search": return try await search(ws, args)
            case "get_diagnostics": return try diagnostics(ws, args)
            case "git_status": return try await gitStatus(ws, args)
            case "get_terminal_output": return terminalOutput(ws, args)
            case "open_file": return try openFile(ws, args)
            case "edit_file": return try await editFile(ws, args, client: client)
            case "write_file": return try await writeFile(ws, args, client: client)
            case "run_command": return try await runCommand(ws, args, client: client)
            case "run_file": return try await runFile(ws, args, client: client)
            default: throw Failure("Unknown tool: \(name)")
            }
        } catch let failure as Failure {
            return .failure(failure.message)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: Arguments

    private static func string(_ args: [String: Any], _ key: String) -> String? {
        guard let value = args[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func int(_ args: [String: Any], _ key: String) -> Int? {
        if let n = args[key] as? Int { return n }
        if let n = args[key] as? Double { return Int(n) }
        if let s = args[key] as? String { return Int(s) }
        return nil
    }

    private static func bool(_ args: [String: Any], _ key: String) -> Bool {
        if let b = args[key] as? Bool { return b }
        if let s = args[key] as? String { return s == "true" || s == "1" }
        return false
    }

    // MARK: Paths

    /// A path Claude may touch: inside the open project, or a file open in Halo.
    private static func resolve(_ raw: String?, in ws: Workspace, mustExist: Bool = true) throws -> URL {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { throw Failure("Missing “path”.") }
        let url: URL
        if raw.hasPrefix("/") {
            url = URL(fileURLWithPath: raw).standardizedFileURL
        } else if raw.hasPrefix("~") {
            url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL
        } else if let root = ws.root {
            url = root.appendingPathComponent(raw).standardizedFileURL
        } else if let doc = ws.documents.first(where: { $0.url?.lastPathComponent == raw }), let docURL = doc.url {
            url = docURL.standardizedFileURL
        } else {
            throw Failure("No folder is open in Halo, so “\(raw)” can’t be resolved. Use an absolute path to a file open in Halo, or ask the user to open the project folder.")
        }
        let inProject = ws.root.map { url.path == $0.path || url.path.hasPrefix($0.path + "/") } ?? false
        let isOpen = ws.documents.contains { $0.url?.standardizedFileURL.path == url.path }
        guard inProject || isOpen else {
            let scope = ws.root.map { "the project folder (\($0.path))" } ?? "files open in Halo"
            throw Failure("“\(raw)” is outside \(scope). Halo only shares the open project and the files open in its editor.")
        }
        if mustExist, !FileManager.default.fileExists(atPath: url.path) {
            throw Failure("There’s no file at \(ws.relativePath(url)).")
        }
        return url
    }

    private static func directory(_ raw: String?, in ws: Workspace) throws -> URL {
        guard let raw else {
            guard let root = ws.root else { throw Failure("No folder is open in Halo. Ask the user to open the project folder.") }
            return root
        }
        let url = try resolve(raw, in: ws)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw Failure("\(ws.relativePath(url)) isn’t a folder.")
        }
        return url
    }

    private static func document(for url: URL, in ws: Workspace) -> Document? {
        ws.documents.first { $0.url?.standardizedFileURL.path == url.path }
    }

    /// Opens the file in Halo (so the user sees Claude's change) and returns its editor.
    private static func openEditor(_ url: URL, in ws: Workspace) throws -> (Document, EditorController) {
        if document(for: url, in: ws) == nil || ws.active?.url?.standardizedFileURL.path != url.path { ws.open(url, flash: false) }
        guard let doc = document(for: url, in: ws) else { throw Failure("Halo couldn’t open \(ws.relativePath(url)).") }
        guard let editor = doc.editor else { throw Failure("\(ws.relativePath(url)) isn’t a text file.") }
        editor.textView.removeGhost()
        return (doc, editor)
    }

    private static func lineNumber(at location: Int, in text: NSString) -> Int {
        var line = 1
        var i = 0
        let end = min(location, text.length)
        while i < end {
            let r = text.range(of: "\n", options: .literal, range: NSRange(location: i, length: end - i))
            guard r.location != NSNotFound else { break }
            line += 1
            i = r.location + 1
        }
        return line
    }

    private static func numbered(_ lines: ArraySlice<String>, from first: Int) -> String {
        let width = String(first + lines.count).count
        return lines.enumerated().map { offset, line in
            let n = String(first + offset)
            let clipped = line.count > 2000 ? String(line.prefix(2000)) + " …" : line
            return String(repeating: " ", count: max(0, width - n.count)) + n + "\t" + clipped
        }.joined(separator: "\n")
    }

    private static func clip(_ text: String, max: Int = 30_000) -> String {
        guard text.count > max else { return text }
        let head = text.prefix(max / 3)
        let tail = text.suffix(max * 2 / 3)
        return head + "\n… (\(text.count - max) characters cut) …\n" + tail
    }

    // MARK: Reading

    private static func editorState(_ ws: Workspace) -> Outcome {
        var out: [String] = []
        if let root = ws.root {
            var line = "Project: \(root.path)"
            if let branch = ws.git.branch {
                line += " (git branch \(branch)" + (ws.git.changedCount > 0 ? ", \(ws.git.changedCount) changed files)" : ", clean)")
            }
            out.append(line)
        } else {
            out.append("Project: no folder open")
        }
        if ws.documents.isEmpty {
            out.append("Open tabs: none")
        } else {
            out.append("Open tabs:")
            for doc in ws.documents {
                let name = doc.url.map { ws.relativePath($0) } ?? "Untitled"
                var flags: [String] = []
                if doc.id == ws.activeID { flags.append("active") }
                if doc.isDirty { flags.append("unsaved changes") }
                out.append("  \(doc.id == ws.activeID ? "*" : " ") \(name)" + (flags.isEmpty ? "" : " (\(flags.joined(separator: ", ")))"))
            }
        }
        if let doc = ws.active {
            let name = doc.url.map { ws.relativePath($0) } ?? "Untitled"
            out.append("Active file: \(name) — \(doc.language.name), line \(doc.cursorLine), column \(doc.cursorColumn)")
            if let editor = doc.editor {
                let range = editor.textView.selectedRange()
                let storage = editor.textView.string as NSString
                if range.length > 0, NSMaxRange(range) <= storage.length {
                    let selected = storage.substring(with: range)
                    let first = lineNumber(at: range.location, in: storage)
                    let last = first + selected.filter { $0 == "\n" }.count
                    out.append("Selection (lines \(first)–\(last)):")
                    out.append(clip(selected, max: 12_000))
                } else {
                    out.append("Selection: none")
                }
            }
        }
        let problems = ws.diagnostics.values.flatMap { $0 }
        let errors = problems.filter { $0.severity == .error }.count
        if !problems.isEmpty { out.append("Problems: \(errors) errors, \(problems.count - errors) warnings (see get_diagnostics)") }
        return Outcome(text: out.joined(separator: "\n"), summary: "Looked at the editor")
    }

    private static func listFiles(_ ws: Workspace, _ args: [String: Any]) async throws -> Outcome {
        guard let root = ws.root else { throw Failure("No folder is open in Halo. Ask the user to open the project folder.") }
        var files = ws.index
        if files.isEmpty { files = await Task.detached { ProjectIndexer.index(root: root) }.value }
        var prefix = ""
        if let path = string(args, "path") {
            prefix = ws.relativePath(try directory(path, in: ws))
            if !prefix.isEmpty, !prefix.hasSuffix("/") { prefix += "/" }
            if prefix == "/" { prefix = "" }
        }
        let pattern = string(args, "pattern")?.replacingOccurrences(of: "**/", with: "*")
        let limit = max(1, int(args, "limit") ?? 500)
        let matches = files.map(\.relative).filter { rel in
            guard prefix.isEmpty || rel.hasPrefix(prefix) else { return false }
            guard let pattern else { return true }
            if fnmatch(pattern, rel, 0) == 0 { return true }
            return !pattern.contains("/") && fnmatch(pattern, (rel as NSString).lastPathComponent, 0) == 0
        }.sorted()
        guard !matches.isEmpty else { return Outcome(text: "No files match.", summary: "Listed files (none)") }
        var text = matches.prefix(limit).joined(separator: "\n")
        if matches.count > limit { text += "\n… and \(matches.count - limit) more (raise limit or narrow with path/pattern)" }
        return Outcome(text: text, summary: "Listed \(matches.count) files")
    }

    private static func readFile(_ ws: Workspace, _ args: [String: Any]) throws -> Outcome {
        let url = try resolve(string(args, "path"), in: ws)
        let rel = ws.relativePath(url)
        var text: String
        var unsaved = false
        if let doc = document(for: url, in: ws), let editor = doc.editor {
            text = editor.text
            unsaved = doc.isDirty
        } else {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                throw Failure("\(rel) is a folder — use list_files.")
            }
            guard let data = try? Data(contentsOf: url) else { throw Failure("Couldn’t read \(rel).") }
            guard data.count <= Document.maxTextBytes else { throw Failure("\(rel) is too large to read (\(data.count / 1_048_576) MB).") }
            guard !data.prefix(8000).contains(0), let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
                throw Failure("\(rel) is a binary file.")
            }
            text = s.replacingOccurrences(of: "\r\n", with: "\n")
        }
        if text.isEmpty { return Outcome(text: "\(rel) is empty.", summary: "Read \(rel)") }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let first = min(max(1, int(args, "start_line") ?? 1), max(1, lines.count))
        let last = min(lines.count, int(args, "end_line") ?? (first + 1999))
        guard first <= last else { throw Failure("\(rel) has \(lines.count) lines.") }
        var header = "\(rel) — lines \(first)–\(last) of \(lines.count)"
        if unsaved { header += " (includes unsaved changes in Halo)" }
        let body = numbered(lines[(first - 1)..<last], from: first)
        let more = last < lines.count ? "\n… \(lines.count - last) more lines (use start_line \(last + 1))" : ""
        return Outcome(text: header + "\n" + body + more, summary: "Read \(rel)")
    }

    private static func search(_ ws: Workspace, _ args: [String: Any]) async throws -> Outcome {
        guard let query = string(args, "query") else { throw Failure("Missing “query”.") }
        guard let root = ws.root else { throw Failure("No folder is open in Halo. Ask the user to open the project folder.") }
        let regex = bool(args, "regex")
        if regex, (try? NSRegularExpression(pattern: query)) == nil { throw Failure("“\(query)” isn’t a valid regular expression.") }
        let caseSensitive = bool(args, "case_sensitive")
        let limit = max(1, int(args, "limit") ?? 100)
        var files = ws.index
        if files.isEmpty { files = await Task.detached { ProjectIndexer.index(root: root) }.value }
        let found = await Task.detached { ProjectSearch.run(query: query, caseSensitive: caseSensitive, regex: regex, files: files) { false } }.value
        guard found.total > 0 else { return Outcome(text: "No matches for “\(query)”.", summary: "Searched “\(query)” (no matches)") }
        var lines: [String] = []
        outer: for file in found.results {
            for match in file.matches {
                lines.append("\(file.relative):\(match.line): \(match.preview.trimmingCharacters(in: .whitespaces))")
                if lines.count >= limit { break outer }
            }
        }
        var text = lines.joined(separator: "\n")
        if found.total > lines.count { text += "\n… \(found.total - lines.count)\(found.truncated ? "+" : "") more matches" }
        return Outcome(text: text, summary: "Searched “\(query)” — \(found.total) matches")
    }

    private static func diagnostics(_ ws: Workspace, _ args: [String: Any]) throws -> Outcome {
        var entries = ws.diagnostics
        if let path = string(args, "path") {
            let url = try resolve(path, in: ws)
            entries = entries.filter { $0.key == url.path }
        }
        let list = entries.values.flatMap { $0 }.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
        // Mistakes Halo underlines in open files (time.wait → time.sleep…).
        var suggestions: [String] = []
        let only = try string(args, "path").map { try resolve($0, in: ws).path }
        for doc in ws.documents {
            guard let url = doc.url, only == nil || url.standardizedFileURL.path == only, let editor = doc.editor else { continue }
            let ns = editor.text as NSString
            for fix in editor.codeFixes {
                let line = ns.substring(to: min(fix.anchor.location, ns.length)).filter { $0 == "\n" }.count + 1
                suggestions.append("\(ws.relativePath(url)):\(line): suggestion: \(fix.original) → \(fix.label) (\(fix.why))")
            }
        }
        if list.isEmpty, !suggestions.isEmpty {
            return Outcome(text: suggestions.joined(separator: "\n"), summary: "Checked problems — \(suggestions.count) suggestions")
        }
        guard !list.isEmpty else {
            return Outcome(text: "No problems. (Halo checks open files as they change, and compiled files when they’re run.)", summary: "Checked problems (none)")
        }
        let text = list.prefix(300).map { d in
            let severity = d.severity == .error ? "error" : d.severity == .warning ? "warning" : "note"
            return "\(ws.relativePath(URL(fileURLWithPath: d.path))):\(d.line)\(d.column.map { ":\($0)" } ?? ""): \(severity): \(d.message) [\(d.source)]"
        }.joined(separator: "\n") + (suggestions.isEmpty ? "" : "\n" + suggestions.joined(separator: "\n"))
        return Outcome(text: text, summary: "Checked problems — \(list.count)")
    }

    private static func gitStatus(_ ws: Workspace, _ args: [String: Any]) async throws -> Outcome {
        guard let root = ws.root else { throw Failure("No folder is open in Halo.") }
        guard let git = Git.executable else { throw Failure("git isn’t installed.") }
        let pathFilter = try string(args, "path").map { ws.relativePath(try resolve($0, in: ws, mustExist: false)) }
        let wantDiff = bool(args, "diff")
        let (status, output) = await Task.detached { () -> (Int32, String) in
            let (code, status) = Shell.run([git, "status", "--short", "--branch"], cwd: root)
            guard code == 0, wantDiff else { return (code, status) }
            let tail = pathFilter.map { ["--", $0] } ?? []
            let unstaged = Shell.run([git, "diff"] + tail, cwd: root).1
            let staged = Shell.run([git, "diff", "--cached"] + tail, cwd: root).1
            var text = status
            if !staged.isEmpty { text += "\n--- staged ---\n" + staged }
            if !unstaged.isEmpty { text += "\n--- not staged ---\n" + unstaged }
            return (code, text)
        }.value
        guard status == 0 else {
            if output.contains("not a git repository") { return Outcome(text: "This project isn’t a git repository.", summary: "Checked git (no repository)") }
            throw Failure(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Outcome(text: clip(output.trimmingCharacters(in: .newlines), max: 40_000), summary: wantDiff ? "Read the git diff" : "Checked git status")
    }

    private static func terminalOutput(_ ws: Workspace, _ args: [String: Any]) -> Outcome {
        guard ws.terminal.isStarted else { return Outcome(text: "The terminal hasn’t been opened in this window.", summary: "Read the terminal (not open)") }
        let data = ws.terminal.view.getTerminal().getBufferAsData()
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let count = min(max(1, int(args, "lines") ?? 80), 1000)
        let text = lines.suffix(count).joined(separator: "\n")
        return Outcome(text: text.isEmpty ? "The terminal is empty." : text, summary: "Read the terminal")
    }

    private static func openFile(_ ws: Workspace, _ args: [String: Any]) throws -> Outcome {
        let url = try resolve(string(args, "path"), in: ws)
        let rel = ws.relativePath(url)
        let line = int(args, "line")
        ws.open(url, line: line)
        if let line, let endLine = int(args, "end_line"), endLine > line, let editor = document(for: url, in: ws)?.editor {
            DispatchQueue.main.async {
                let text = editor.textView.string as NSString
                var starts = [0]
                var i = 0
                while starts.count <= endLine, i < text.length {
                    let r = text.range(of: "\n", options: .literal, range: NSRange(location: i, length: text.length - i))
                    guard r.location != NSNotFound else { break }
                    starts.append(r.location + 1)
                    i = r.location + 1
                }
                guard line - 1 < starts.count else { return }
                let start = starts[line - 1]
                let end = endLine < starts.count ? starts[endLine] : text.length
                editor.textView.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
                editor.textView.scrollRangeToVisible(NSRange(location: start, length: 0))
            }
        }
        return Outcome(text: "Opened \(rel)\(line.map { " at line \($0)" } ?? "") in Halo.", summary: "Opened \(rel)")
    }

    // MARK: Editing

    private static func persist(_ doc: Document, in ws: Workspace, _ rel: String) throws {
        do { try ws.persist(doc) } catch { throw Failure("Changed \(rel) in the editor but couldn’t save it: \(error.localizedDescription)") }
    }

    /// Lints the file Claude just changed and describes any errors for the reply.
    private static func problems(after doc: Document, in ws: Workspace) async -> String {
        let found = await ws.lintNow(doc).filter { $0.severity == .error }
        guard !found.isEmpty else { return "" }
        let list = found.prefix(10).map { "  line \($0.line): \($0.message)" }.joined(separator: "\n")
        return "\nHalo now sees \(found.count == 1 ? "an error" : "\(found.count) errors") in this file:\n" + list
    }

    /// The editor marks a document edited on the next main-queue turn; save after that.
    private static func nextTurn() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { done.resume() } }
    }

    private static func editFile(_ ws: Workspace, _ args: [String: Any], client: String) async throws -> Outcome {
        guard let old = args["old_string"] as? String, !old.isEmpty else { throw Failure("Missing “old_string”.") }
        guard let new = args["new_string"] as? String else { throw Failure("Missing “new_string”.") }
        guard old != new else { throw Failure("old_string and new_string are the same.") }
        let url = try resolve(string(args, "path"), in: ws)
        let rel = ws.relativePath(url)
        let (doc, editor) = try openEditor(url, in: ws)
        ws.unattendedEdits.insert(url.path)
        let text = editor.text as NSString
        var ranges: [NSRange] = []
        var from = 0
        while from <= text.length {
            let r = text.range(of: old, options: .literal, range: NSRange(location: from, length: text.length - from))
            guard r.location != NSNotFound else { break }
            ranges.append(r)
            from = NSMaxRange(r)
        }
        guard let firstRange = ranges.first, let lastRange = ranges.last else {
            throw Failure("old_string wasn’t found in \(rel). Read the file again — it may have changed, and the match must be exact (including indentation).")
        }
        let replaceAll = bool(args, "replace_all")
        guard ranges.count == 1 || replaceAll else {
            throw Failure("old_string appears \(ranges.count) times in \(rel). Include more surrounding lines so it matches once, or set replace_all.")
        }
        // One undoable change covering every match.
        let span = replaceAll ? NSRange(location: firstRange.location, length: NSMaxRange(lastRange) - firstRange.location) : firstRange
        let replacement = replaceAll ? text.substring(with: span).replacingOccurrences(of: old, with: new) : new
        editor.textView.replace(span, with: replacement)
        let firstLine = lineNumber(at: span.location, in: editor.text as NSString)
        editor.textView.goTo(line: firstLine, flash: true)
        await nextTurn()
        try persist(doc, in: ws, rel)
        ws.showToast("\(client) edited \(url.lastPathComponent)")

        // Show the result around the change so Claude can check it.
        let lines = editor.text.components(separatedBy: "\n")
        let changed = replacement.filter { $0 == "\n" }.count + 1
        let from0 = max(1, firstLine - 3)
        let to0 = min(lines.count, firstLine + changed + 2)
        let count = ranges.count == 1 ? "1 occurrence" : "\(ranges.count) occurrences"
        let snippet = from0 <= to0 ? "\n" + numbered(lines[(from0 - 1)..<to0], from: from0) : ""
        let issues = await problems(after: doc, in: ws)
        return Outcome(text: "Edited \(rel) (\(count), line \(firstLine)) and saved. The user can undo it with ⌘Z.\(snippet)\(issues)",
                       summary: "Edited \(rel)")
    }

    private static func writeFile(_ ws: Workspace, _ args: [String: Any], client: String) async throws -> Outcome {
        guard let content = args["content"] as? String else { throw Failure("Missing “content”.") }
        let url = try resolve(string(args, "path"), in: ws, mustExist: false)
        let rel = ws.relativePath(url)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { throw Failure("\(rel) is a folder.") }
        let lineCount = content.isEmpty ? 0 : content.components(separatedBy: "\n").count - (content.hasSuffix("\n") ? 1 : 0)
        if exists {
            // Through the editor, so ⌘Z brings the old contents back.
            let (doc, editor) = try openEditor(url, in: ws)
            ws.unattendedEdits.insert(url.path)
            editor.textView.replace(NSRange(location: 0, length: (editor.textView.string as NSString).length), with: content)
            editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
            await nextTurn()
            try persist(doc, in: ws, rel)
            ws.showToast("\(client) rewrote \(url.lastPathComponent)")
            let issues = await problems(after: doc, in: ws)
            return Outcome(text: "Replaced the contents of \(rel) (\(lineCount) lines) and saved. The user can undo it with ⌘Z.\(issues)", summary: "Rewrote \(rel)")
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url, options: .atomic)
        } catch {
            throw Failure("Couldn’t create \(rel): \(error.localizedDescription)")
        }
        ws.refreshTree()
        ws.open(url, flash: false)
        ws.showToast("\(client) created \(url.lastPathComponent)")
        var issues = ""
        if let doc = document(for: url, in: ws) { issues = await problems(after: doc, in: ws) }
        return Outcome(text: "Created \(rel) (\(lineCount) lines) and opened it in Halo.\(issues)", summary: "Created \(rel)")
    }

    // MARK: Running

    private struct Captured: Sendable {
        var status: Int32
        var output: String
        var timedOut: Bool
        var seconds: Double
    }

    /// Runs a command line in the user's login shell, capturing output, with a time limit.
    nonisolated private static func capture(_ command: String, shell: String, cwd: URL, stdin: String?, timeout: TimeInterval) -> Captured {
        let start = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let input = Pipe()
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input
        do { try process.run() } catch {
            return Captured(status: -1, output: error.localizedDescription, timedOut: false, seconds: 0)
        }
        if let stdin {
            let handle = input.fileHandleForWriting
            DispatchQueue.global().async {
                try? handle.write(contentsOf: Data(stdin.utf8))
                try? handle.close()
            }
        }
        let collected = LockedData()
        let reading = DispatchGroup()
        reading.enter()
        DispatchQueue.global().async {
            let handle = output.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
            }
            reading.leave()
        }
        var timedOut = false
        if reading.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            // Children that ignore SIGTERM (or a shell's grandchildren holding the pipe).
            if reading.wait(timeout: .now() + 2) == .timedOut { kill(-process.processIdentifier, SIGKILL); kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        return Captured(status: process.terminationStatus, output: String(decoding: collected.value, as: UTF8.self),
                        timedOut: timedOut, seconds: Date().timeIntervalSince(start))
    }

    private static func report(_ result: Captured, label: String) -> String {
        var head = "\(label) — "
        if result.timedOut { head += "stopped after \(Int(result.seconds)) s (time limit)" }
        else { head += "exit code \(result.status) · \(String(format: "%.1f", result.seconds)) s" }
        let body = result.output.trimmingCharacters(in: .newlines)
        return head + "\n" + (body.isEmpty ? "(no output)" : clip(body))
    }

    private static func logToOutput(_ ws: Workspace, _ lines: [String]) {
        ws.buildLog += lines
        if ws.buildLog.count > 4000 { ws.buildLog.removeFirst(ws.buildLog.count - 4000) }
    }

    private static func runCommand(_ ws: Workspace, _ args: [String: Any], client: String) async throws -> Outcome {
        guard let command = string(args, "command") else { throw Failure("Missing “command”.") }
        let cwd = try string(args, "cwd").map { try directory($0, in: ws) } ?? ws.root ?? URL(fileURLWithPath: NSHomeDirectory())
        let timeout = TimeInterval(min(600, max(1, int(args, "timeout_seconds") ?? 60)))
        let shell = TerminalSession.loginShell
        ws.showToast("\(client) is running \(command.count > 40 ? String(command.prefix(40)) + "…" : command)")
        let result = await Task.detached { capture(command, shell: shell, cwd: cwd, stdin: nil, timeout: timeout) }.value
        logToOutput(ws, ["$ \(command)    (run by \(client))"] + result.output.components(separatedBy: "\n").suffix(400))
        let failed = result.timedOut || result.status != 0
        return Outcome(text: report(result, label: "$ \(command)"), isError: false,
                       summary: "Ran \(command.count > 60 ? String(command.prefix(60)) + "…" : command)" + (failed ? " — failed" : ""))
    }

    private static func runFile(_ ws: Workspace, _ args: [String: Any], client: String) async throws -> Outcome {
        let url: URL
        if let path = string(args, "path") { url = try resolve(path, in: ws) }
        else if let active = ws.active?.url { url = active.standardizedFileURL }
        else { throw Failure("No file is open in Halo — pass “path”.") }
        let rel = ws.relativePath(url)
        if let doc = document(for: url, in: ws), doc.isDirty { try persist(doc, in: ws, rel) }
        let language = Language.detect(url: url)
        let plan: RunPlan
        switch Runner.plan(for: url, language: language, root: ws.root) {
        case .failure(let error):
            throw Failure(error.localizedDescription + (error.installHint.map { " Install it with: \($0)" } ?? ""))
        case .success(let p): plan = p
        }
        if let compile = plan.compile {
            ws.isBuilding = true
            let built = await Runner.build(compile, cwd: plan.cwd)
            ws.isBuilding = false
            ws.applyBuildDiagnostics(built.diagnostics, for: [url.path])
            guard built.ok else {
                return Outcome(text: "Build failed:\n" + clip(built.output.trimmingCharacters(in: .newlines)), isError: false, summary: "Ran \(rel) — build failed")
            }
        }
        let timeout = TimeInterval(min(600, max(1, int(args, "timeout_seconds") ?? 60)))
        let shell = TerminalSession.loginShell
        let stdin = args["stdin"] as? String
        ws.showToast("\(client) is running \(url.lastPathComponent)")
        let result = await Task.detached { capture(plan.command, shell: shell, cwd: plan.cwd, stdin: stdin, timeout: timeout) }.value
        logToOutput(ws, ["$ \(plan.command)    (run by \(client))"] + result.output.components(separatedBy: "\n").suffix(400))
        let failed = result.timedOut || result.status != 0
        return Outcome(text: report(result, label: "$ \(plan.command)"), summary: "Ran \(rel)" + (failed ? " — failed" : ""))
    }
}

/// Bytes appended from one thread and read once the writer is done.
private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    var value: Data { lock.withLock { data } }
}
