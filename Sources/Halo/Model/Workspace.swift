import AppKit
import SwiftUI
import Observation

enum SidebarMode: String { case files, search, git, debug }

enum PaletteMode: Equatable {
    case files, commands, line
    var prefix: String {
        switch self {
        case .files: ""
        case .commands: ">"
        case .line: ":"
        }
    }
}

/// Weak registry of open windows' workspaces (for quit checks and
/// routing files opened from Finder or the Dock).
@MainActor
enum WorkspaceRegistry {
    private static var items: [WeakBox] = []
    private(set) static weak var focused: Workspace?
    static var pendingOpen: [URL] = []

    private final class WeakBox { weak var value: Workspace?; init(_ v: Workspace) { value = v } }

    static func register(_ w: Workspace) { items.append(WeakBox(w)); items.removeAll { $0.value == nil } }
    static func focus(_ w: Workspace) { focused = w }
    static var all: [Workspace] { items.compactMap(\.value) }
}

@Observable @MainActor
final class Workspace {
    // Project
    private(set) var root: URL?
    private(set) var rows: [FileNode] = []
    /// Expanded folders, keyed by standardized path (URLs differ on trailing slashes).
    private(set) var expanded: Set<String> = []
    @ObservationIgnored private var childCache: [URL: [FileEntry]] = [:]
    var sidebarSelection: URL?
    private(set) var git = GitInfo()
    private(set) var index: [IndexedFile] = []
    private(set) var isIndexing = false

    // Editing
    private(set) var documents: [Document] = []
    var activeID: UUID?
    var active: Document? { documents.first { $0.id == activeID } }

    // Chrome
    var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    var sidebarMode: SidebarMode = .files
    var showTerminal = false
    var terminalHeight: CGFloat = 240
    var palette: PaletteMode?
    var ascended = false
    var showSetup = false
    var toast: String?

    // Run, debug, problems, source control
    var panelTab: PanelTab = .terminal
    var diagnostics: [String: [Diagnostic]] = [:]          // path → build ∪ live errors
    var buildLog: [String] = []
    var isBuilding = false
    var breakpoints: [String: Set<Int>] = [:]
    var debug: DebugSession?
    let scm = SourceControl()
    var lineChanges: [String: [LineChange]] = [:]
    @ObservationIgnored var lintWork: [String: DispatchWorkItem] = [:]
    @ObservationIgnored var lintDiagnostics: [String: [Diagnostic]] = [:]
    @ObservationIgnored var buildDiagnostics: [String: [Diagnostic]] = [:]
    /// Line whose syntax error was held back while you were typing it.
    @ObservationIgnored var pendingLint: [String: Int] = [:]
    /// Files Claude just changed: nobody is typing there, so hold nothing back.
    @ObservationIgnored var unattendedEdits: Set<String> = []

    // Search
    var searchQuery = "" { didSet { scheduleSearch() } }
    var searchCaseSensitive = false { didSet { scheduleSearch() } }
    var searchRegex = false { didSet { scheduleSearch() } }
    private(set) var searchResults: [SearchFileResult] = []
    private(set) var searchTotal = 0
    private(set) var searchTruncated = false
    private(set) var isSearching = false
    var searchFocusToken = 0

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var searchWork: DispatchWorkItem?
    @ObservationIgnored private var refreshWork: DispatchWorkItem?
    @ObservationIgnored private var gitWork: DispatchWorkItem?
    @ObservationIgnored private var toastWork: DispatchWorkItem?
    @ObservationIgnored lazy var terminal = TerminalSession(workspace: self)
    @ObservationIgnored private var recentlyOpened: [URL] = []

    var title: String { root?.lastPathComponent ?? active?.name ?? "Halo" }

    init() {
        WorkspaceRegistry.register(self)
    }

    // MARK: Folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder to work in"
        if panel.runModal() == .OK, let url = panel.url { openFolder(url) }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach { open($0) } }
    }

    func openFolder(_ url: URL) {
        let url = url.standardizedFileURL
        saveSession()
        root = url
        childCache = [:]
        expanded = []
        sidebarSelection = nil
        rebuildRows()
        withAnimation(Motion.gentle) { columnVisibility = .all }
        Preferences.shared.noteRecent(url)
        watcher = FileWatcher(path: url.path) { [weak self] paths in self?.filesChanged(paths) }
        FillEngine.shared.reset()
        reindex()
        refreshGit()
        scm.refresh(folder: url)
        restoreSession()
        if terminal.isStarted { terminal.changeDirectory(to: url) }
    }

    func closeFolder() {
        saveSession()
        root = nil
        rows = []
        index = []
        git = GitInfo()
        watcher = nil
        debug?.stop()
        scm.refresh(folder: nil)
        FillEngine.shared.reset()
        withAnimation(Motion.gentle) { columnVisibility = .detailOnly }
    }

    // MARK: Tree

    func children(of url: URL) -> [FileEntry] {
        if let cached = childCache[url] { return cached }
        let list = FileSystem.children(of: url)
        childCache[url] = list
        return list
    }

    func toggle(_ url: URL) {
        let key = Self.key(url)
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
        rebuildRows()
    }

    static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    func isExpanded(_ url: URL) -> Bool { expanded.contains(Self.key(url)) }

    func rebuildRows() {
        guard let root else { rows = []; return }
        var out: [FileNode] = []
        func walk(_ dir: URL, depth: Int) {
            for entry in children(of: dir) {
                out.append(FileNode(entry: entry, depth: depth))
                if entry.isDirectory, expanded.contains(Self.key(entry.url)) { walk(entry.url, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        rows = out
    }

    func reveal(_ url: URL) {
        guard let root, url.path.hasPrefix(root.path) else { return }
        var dir = url.deletingLastPathComponent().standardizedFileURL
        while dir.path.count > root.path.count {
            expanded.insert(Self.key(dir))
            dir.deleteLastPathComponent()
        }
        rebuildRows()
        sidebarSelection = url.standardizedFileURL
    }

    func relativePath(_ url: URL) -> String {
        guard let root else { return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root.path) else { return path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        return String(path.dropFirst(root.path.count + 1))
    }

    func gitState(for url: URL) -> GitState? {
        guard root != nil else { return nil }
        return git.states[relativePath(url)]
    }

    private func filesChanged(_ paths: [String]) {
        guard let root else { return }
        var treeChanged = false
        var gitChanged = false
        for path in paths {
            if path.contains("/.git/") || path.hasSuffix("/.git") { gitChanged = true; continue }
            gitChanged = true
            let dir = URL(fileURLWithPath: path).standardizedFileURL
            let key = dir.path.hasSuffix("/") ? URL(fileURLWithPath: String(dir.path.dropLast())) : dir
            if childCache.removeValue(forKey: key) != nil { treeChanged = true }
            if key.path == root.path { childCache.removeValue(forKey: root); treeChanged = true }
        }
        if treeChanged {
            refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.rebuildRows()
                self?.reindex()
            }
            refreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        if gitChanged {
            refreshGit()
            scm.refresh(folder: root)
            refreshLineChanges(for: active)
        }
        documents.forEach { $0.reloadIfChangedOnDisk() }
    }

    func refreshTree() {
        childCache = [:]
        rebuildRows()
        reindex()
        refreshGit()
    }

    private func reindex() {
        guard let root else { return }
        isIndexing = true
        Task.detached(priority: .utility) { [weak self] in
            let files = ProjectIndexer.index(root: root)
            await MainActor.run {
                guard let self, self.root == root else { return }
                self.index = files
                FillEngine.shared.indexProject(root: root, files: files)
                self.isIndexing = false
                if !self.searchQuery.isEmpty { self.scheduleSearch(immediate: true) }
            }
        }
    }

    func refreshGit() {
        gitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let root = self.root else { return }
            Task.detached(priority: .utility) { [weak self] in
                let info = Git.status(root: root)
                await MainActor.run {
                    guard let self, self.root == root, self.git != info else { return }
                    self.git = info
                }
            }
        }
        gitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Documents

    func open(_ url: URL, line: Int? = nil, column: Int = 1, flash: Bool = true) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            if root == nil { openFolder(url) } else { NSWorkspace.shared.open(url) }
            return
        }
        let std = url.standardizedFileURL
        let doc: Document
        if let existing = documents.first(where: { $0.url?.standardizedFileURL == std }) {
            doc = existing
        } else {
            doc = Document(url: std)
            if let active, active.url == nil, !active.isDirty, (active.editor?.text.isEmpty ?? true),
               let i = documents.firstIndex(where: { $0.id == active.id }) {
                documents[i] = doc   // replace the pristine untitled tab
            } else if let activeIndex = documents.firstIndex(where: { $0.id == activeID }) {
                documents.insert(doc, at: activeIndex + 1)
            } else {
                documents.append(doc)
            }
        }
        activeID = doc.id
        refreshLineChanges(for: doc)
        recentlyOpened.removeAll { $0 == std }
        recentlyOpened.insert(std, at: 0)
        reveal(std)
        if let line {
            DispatchQueue.main.async { doc.editor?.textView.goTo(line: line, column: column, flash: flash) }
        }
    }

    var recentFiles: [URL] { recentlyOpened }

    func newFile() {
        let doc = Document()
        documents.append(doc)
        activeID = doc.id
    }

    func activate(_ doc: Document) {
        activeID = doc.id
        refreshLineChanges(for: doc)
    }

    func activateTab(offset: Int) {
        guard !documents.isEmpty, let i = documents.firstIndex(where: { $0.id == activeID }) else { return }
        activeID = documents[(i + offset + documents.count) % documents.count].id
    }

    @discardableResult
    func close(_ doc: Document) -> Bool {
        if doc.isDirty {
            activeID = doc.id
            let alert = NSAlert()
            alert.messageText = "Save changes to “\(doc.name)”?"
            alert.informativeText = "Your changes will be lost if you don’t save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Don’t Save")
            switch alert.runModal() {
            case .alertFirstButtonReturn: guard save(doc) else { return false }
            case .alertThirdButtonReturn: break
            default: return false
            }
        }
        guard let i = documents.firstIndex(where: { $0.id == doc.id }) else { return true }
        documents.remove(at: i)
        if activeID == doc.id {
            activeID = documents.isEmpty ? nil : documents[min(i, documents.count - 1)].id
        }
        return true
    }

    func closeOthers(_ doc: Document) {
        for other in documents where other.id != doc.id { if !close(other) { return } }
    }

    func closeActive() -> Bool {
        guard let active else { return false }
        close(active)
        return true
    }

    /// Returns false if the user cancelled.
    func confirmCloseAll() -> Bool {
        for doc in documents where doc.isDirty {
            if !close(doc) { return false }
        }
        saveSession()
        debug?.stop()
        return true
    }

    @discardableResult
    func save(_ doc: Document? = nil) -> Bool {
        guard let doc = doc ?? active else { return false }
        if doc.url == nil { return saveAs(doc) }
        do {
            try persist(doc)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// Saves a document that has a file, without any UI (Claude's edits use this).
    func persist(_ doc: Document) throws {
        try doc.save()
        refreshGit()
        if let url = doc.url, let text = doc.editor?.text { FillEngine.shared.update(url: url, text: text) }
        scm.refresh(folder: root)
        refreshLineChanges(for: doc)
    }

    @discardableResult
    func saveAs(_ doc: Document? = nil) -> Bool {
        guard let doc = doc ?? active else { return false }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = doc.name
        if let root { panel.directoryURL = doc.url?.deletingLastPathComponent() ?? root }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try doc.save(to: url)
            reveal(url)
            refreshGit()
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    func saveAll() {
        for doc in documents where doc.isDirty { if !save(doc) { return } }
    }

    // MARK: File operations

    func createItem(in directory: URL?, folder: Bool) {
        guard let dir = directory ?? root else { return }
        guard let name = prompt(title: folder ? "New Folder" : "New File", message: "Name", defaultValue: folder ? "untitled folder" : "untitled.txt") else { return }
        let url = dir.appendingPathComponent(name)
        do {
            if folder {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: url.path, contents: Data()) else { throw CocoaError(.fileWriteUnknown) }
            }
            childCache = [:]
            expanded.insert(Self.key(dir))
            rebuildRows()
            if !folder { open(url) }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func rename(_ url: URL) {
        guard let name = prompt(title: "Rename", message: "New name for “\(url.lastPathComponent)”", defaultValue: url.lastPathComponent),
              name != url.lastPathComponent else { return }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: url, to: target)
            childCache = [:]
            rebuildRows()
            if let doc = documents.first(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
                close(doc)
                open(target)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func moveToTrash(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Move “\(url.lastPathComponent)” to the Trash?"
        alert.informativeText = "You can restore it from the Trash in Finder."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            for doc in documents where doc.url?.path.hasPrefix(url.path) == true {
                doc.isDirty = false
                close(doc)
            }
            childCache = [:]
            rebuildRows()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func prompt(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if let dot = defaultValue.lastIndex(of: "."), dot != defaultValue.startIndex {
            DispatchQueue.main.async { field.currentEditor()?.selectedRange = NSRange(location: 0, length: defaultValue.distance(from: defaultValue.startIndex, to: dot)) }
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: Search

    func focusSearch() {
        withAnimation(Motion.snappy) {
            if columnVisibility == .detailOnly { columnVisibility = .all }
            sidebarMode = .search
        }
        if let editor = active?.editor {
            let sel = editor.textView.selectedRange()
            if sel.length > 0, sel.length < 200 {
                let s = (editor.text as NSString).substring(with: sel)
                if !s.contains("\n") { searchQuery = s }
            }
        }
        searchFocusToken += 1
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchWork?.cancel()
        searchGeneration += 1
        let gen = searchGeneration
        let query = searchQuery
        guard !query.isEmpty, root != nil else {
            searchResults = []; searchTotal = 0; isSearching = false; searchTruncated = false
            return
        }
        let files = index
        let caseSensitive = searchCaseSensitive
        let regex = searchRegex
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.activeSearchBox?.cancelled = true
            let box = CancelBox()
            self.activeSearchBox = box
            self.isSearching = true
            Task.detached(priority: .userInitiated) { [weak self] in
                let result = ProjectSearch.run(query: query, caseSensitive: caseSensitive, regex: regex, files: files) { box.cancelled }
                await MainActor.run {
                    guard let self, gen == self.searchGeneration else { return }
                    self.searchResults = result.results
                    self.searchTotal = result.total
                    self.searchTruncated = result.truncated
                    self.isSearching = false
                }
            }
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.22), execute: work)
    }

    @ObservationIgnored private var activeSearchBox: CancelBox?

    // MARK: Chrome

    func toggleSidebar() {
        withAnimation(Motion.gentle) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    func toggleTerminal() {
        withAnimation(Motion.snappy) { showTerminal.toggle() }
        if showTerminal {
            terminal.startIfNeeded(in: root)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.terminal.focus() }
        } else {
            active?.editor?.focus()
        }
    }

    func toggleAscend() {
        withAnimation(Motion.gentle) {
            ascended.toggle()
            columnVisibility = ascended ? .detailOnly : (root == nil ? .detailOnly : .all)
            if ascended { showTerminal = false }
        }
        showToast(ascended ? "Ascended — ⇧⌘↩ to return" : nil)
    }

    func showPalette(_ mode: PaletteMode) {
        withAnimation(Motion.snappy) { palette = mode }
    }

    func dismissPalette() {
        withAnimation(Motion.exit) { palette = nil }
        active?.editor?.focus()
    }

    func showToast(_ message: String?) {
        toastWork?.cancel()
        withAnimation(Motion.snappy) { toast = message }
        guard message != nil else { return }
        let work = DispatchWorkItem { [weak self] in withAnimation(Motion.exit) { self?.toast = nil } }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    // MARK: Session (open tabs per folder)

    private func sessionKey(_ root: URL) -> String { "session:" + root.path }

    func saveSession() {
        guard let root else { return }
        let paths = documents.compactMap { $0.url }.filter { $0.path.hasPrefix(root.path) }.map { relativePath($0) }
        let activeRel = active?.url.map { relativePath($0) }
        var marks: [String: [Int]] = [:]
        for (path, lines) in breakpoints where !lines.isEmpty && path.hasPrefix(root.path) {
            marks[relativePath(URL(fileURLWithPath: path))] = lines.sorted()
        }
        UserDefaults.standard.set(["tabs": paths, "active": activeRel ?? "", "breakpoints": marks,
                                   "expanded": expanded.map { relativePath(URL(fileURLWithPath: $0)) }], forKey: sessionKey(root))
    }

    private func restoreSession() {
        guard let root, let session = UserDefaults.standard.dictionary(forKey: sessionKey(root)) else { return }
        for rel in (session["expanded"] as? [String]) ?? [] {
            let url = root.appendingPathComponent(rel).standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path) { expanded.insert(Self.key(url)) }
        }
        rebuildRows()
        breakpoints = [:]
        for (rel, lines) in (session["breakpoints"] as? [String: [Int]]) ?? [:] {
            breakpoints[root.appendingPathComponent(rel).standardizedFileURL.path] = Set(lines)
        }
        for rel in (session["tabs"] as? [String]) ?? [] {
            let url = root.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path), !documents.contains(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
                documents.append(Document(url: url.standardizedFileURL))
            }
        }
        if let rel = session["active"] as? String, !rel.isEmpty,
           let doc = documents.first(where: { $0.url?.standardizedFileURL == root.appendingPathComponent(rel).standardizedFileURL }) {
            activeID = doc.id
        } else if activeID == nil {
            activeID = documents.first?.id
        }
    }
}

final class CancelBox: @unchecked Sendable {
    var cancelled = false
}
