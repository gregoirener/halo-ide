import Foundation
import CoreServices

// MARK: - File system entries

struct FileEntry: Hashable {
    let url: URL
    let isDirectory: Bool
    var name: String { url.lastPathComponent }
}

struct FileNode: Identifiable, Hashable {
    let entry: FileEntry
    let depth: Int
    var id: URL { entry.url }
    var url: URL { entry.url }
    var name: String { entry.name }
    var isDirectory: Bool { entry.isDirectory }
}

enum FileSystem {
    static let hiddenNames: Set<String> = [".git", ".DS_Store", ".svn", ".hg"]
    static let skippedForIndex: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData", "Pods", "dist", ".next", ".nuxt",
        "target", "venv", ".venv", "__pycache__", ".idea", ".swiftpm", ".gradle", "vendor", ".cache",
        "coverage", ".turbo", ".parcel-cache", "out", ".svelte-kit", ".expo",
    ]

    static func children(of url: URL) -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: []) else { return [] }
        return urls
            .filter { !hiddenNames.contains($0.lastPathComponent) }
            .map { u in
                let values = try? u.resourceValues(forKeys: Set(keys))
                let isDir = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
                return FileEntry(url: u, isDirectory: isDir)
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
}

// MARK: - Project index (quick open + search)

struct IndexedFile: Hashable {
    let url: URL
    let relative: String
    let lower: [UInt16]
    let nameStart: Int

    init(url: URL, relative: String) {
        self.url = url
        self.relative = relative
        lower = Array(relative.lowercased().utf16)
        nameStart = (lower.lastIndex(of: 47).map { $0 + 1 }) ?? 0
    }
}

enum ProjectIndexer {
    static let limit = 60_000

    static func index(root: URL) -> [IndexedFile] {
        var out: [IndexedFile] = []
        let rootPath = root.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return [] }
        for case let url as URL in e {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true && values?.isPackage != true {
                if FileSystem.skippedForIndex.contains(name) { e.skipDescendants() }
                continue
            }
            if name == ".DS_Store" { continue }
            var rel = url.standardizedFileURL.path
            if rel.hasPrefix(rootPath) { rel = String(rel.dropFirst(rootPath.count)) }
            if rel.hasPrefix("/") { rel.removeFirst() }
            out.append(IndexedFile(url: url, relative: rel))
            if out.count >= limit { break }
        }
        return out
    }
}

// MARK: - Fuzzy matching

enum Fuzzy {
    struct Match { let score: Int; let positions: [Int] }

    private static func isBoundary(_ c: UInt16) -> Bool { c == 47 || c == 95 || c == 45 || c == 46 || c == 32 }

    /// Greedy subsequence match. Prefers matches inside the file name,
    /// at word boundaries, and in consecutive runs.
    static func match(_ query: [UInt16], in file: IndexedFile) -> Match? {
        guard !query.isEmpty else { return Match(score: 0, positions: []) }
        if let m = greedy(query, file.lower, from: file.nameStart) {
            var score = m.score + 60
            if file.lower[file.nameStart...].starts(with: query) { score += 40 }
            return Match(score: score - file.lower.count / 8, positions: m.positions)
        }
        guard let m = greedy(query, file.lower, from: 0) else { return nil }
        return Match(score: m.score - file.lower.count / 8, positions: m.positions)
    }

    private static func greedy(_ q: [UInt16], _ s: [UInt16], from start: Int) -> Match? {
        var positions: [Int] = []
        positions.reserveCapacity(q.count)
        var qi = 0
        var score = 0
        var last = -2
        var i = start
        while i < s.count, qi < q.count {
            if s[i] == q[qi] {
                var bonus = 1
                if i == 0 || isBoundary(s[i - 1]) { bonus += 8 }
                if last == i - 1 { bonus += 6 } else if last >= 0 { score -= min(i - last - 1, 4) }
                score += bonus
                positions.append(i)
                last = i
                qi += 1
            }
            i += 1
        }
        return qi == q.count ? Match(score: score, positions: positions) : nil
    }
}

// MARK: - Git

enum GitState: Character {
    case modified = "M", added = "A", deleted = "D", renamed = "R", untracked = "?", conflicted = "U"
}

struct GitInfo: Equatable {
    var branch: String?
    var states: [String: GitState] = [:]   // relative path → state (folders inherit)
    var changedCount = 0
}

enum Git {
    static let executable: String? = {
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // /usr/bin/git is a shim that would pop the Command Line Tools installer
        // if they're missing, so only use it when a developer dir is set up.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["-p"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        return p.terminationStatus == 0 ? "/usr/bin/git" : nil
    }()

    static func repoRoot(for url: URL) -> URL? {
        var dir = url.standardizedFileURL
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    static func headBranch(repo: URL) -> String? {
        var gitDir = repo.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir)
        if !isDir.boolValue, let text = try? String(contentsOf: gitDir, encoding: .utf8), text.hasPrefix("gitdir:") {
            gitDir = URL(fileURLWithPath: text.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: repo)
        }
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") { return String(trimmed.dropFirst(16)) }
        return String(trimmed.prefix(7))
    }

    /// Runs `git status` and maps paths relative to `root` (the opened folder).
    static func status(root: URL) -> GitInfo {
        guard let repo = repoRoot(for: root) else { return GitInfo() }
        var info = GitInfo(branch: headBranch(repo: repo))
        guard let git = executable else { return info }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: git)
        p.arguments = ["-C", repo.path, "status", "--porcelain=v1", "-z", "--untracked-files=normal"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return info }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return info }

        let rootPath = root.standardizedFileURL.path
        let repoPath = repo.standardizedFileURL.path
        let prefix = rootPath == repoPath ? "" : String(rootPath.dropFirst(repoPath.count + 1)) + "/"
        let entries = data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
        var i = 0
        while i < entries.count {
            let entry = entries[i]
            i += 1
            guard entry.count > 3 else { continue }
            let x = entry[entry.startIndex]
            let y = entry[entry.index(after: entry.startIndex)]
            var path = String(entry.dropFirst(3))
            if x == "R" || x == "C" { i += 1 }
            let state: GitState
            if x == "?" { state = .untracked }
            else if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D") { state = .conflicted }
            else if x == "A" { state = .added }
            else if x == "D" || y == "D" { state = .deleted }
            else if x == "R" { state = .renamed }
            else { state = .modified }
            guard prefix.isEmpty || path.hasPrefix(prefix) else { continue }
            path = String(path.dropFirst(prefix.count))
            if path.hasSuffix("/") { path.removeLast() }
            info.states[path] = state
            info.changedCount += 1
            // Propagate a quieter "contains changes" mark to parent folders.
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if info.states[parent] == nil { info.states[parent] = .modified }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return info
    }
}

// MARK: - File watching (FSEvents)

final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void

    init?(path: String, handler: @escaping ([String]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watcher.handler(Array(array.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

// MARK: - Project search

struct SearchMatch: Identifiable, Hashable {
    let id = UUID()
    let line: Int
    let column: Int
    let preview: String
    let highlight: Range<Int>   // character offsets within preview
}

struct SearchFileResult: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let relative: String
    let matches: [SearchMatch]
}

enum ProjectSearch {
    static let maxMatches = 3000
    static let maxFileBytes = 2 * 1024 * 1024

    static func run(query: String, caseSensitive: Bool, regex: Bool, files: [IndexedFile], isCancelled: () -> Bool) -> (results: [SearchFileResult], total: Int, truncated: Bool) {
        let pattern = regex ? query : NSRegularExpression.escapedPattern(for: query)
        guard !query.isEmpty, let re = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive]) else {
            return ([], 0, false)
        }
        var results: [SearchFileResult] = []
        var total = 0
        for file in files {
            if isCancelled() { break }
            if Document.imageExtensions.contains(file.url.pathExtension.lowercased()) { continue }
            guard let size = try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxFileBytes,
                  let data = try? Data(contentsOf: file.url), !data.prefix(4000).contains(0),
                  let text = String(data: data, encoding: .utf8) else { continue }
            var matches: [SearchMatch] = []
            var lineNumber = 0
            text.enumerateLines { line, stop in
                lineNumber += 1
                let ns = line as NSString
                guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), m.range.length > 0 else { return }
                let lead = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
                let start = min(m.range.location, max(lead, m.range.location - 40))
                let previewRange = NSRange(location: start, length: min(ns.length - start, 160))
                let preview = ns.substring(with: previewRange)
                let hlStart = (ns.substring(with: NSRange(location: start, length: m.range.location - start))).count
                let hlLen = ns.substring(with: m.range).count
                matches.append(SearchMatch(line: lineNumber, column: m.range.location + 1, preview: preview, highlight: hlStart..<(hlStart + hlLen)))
                total += 1
                if matches.count >= 200 || total >= maxMatches { stop = true }
            }
            if !matches.isEmpty { results.append(SearchFileResult(url: file.url, relative: file.relative, matches: matches)) }
            if total >= maxMatches { return (results, total, true) }
        }
        return (results, total, false)
    }
}
