import SwiftUI

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var shortcut: String? = nil
    let run: (Workspace) -> Void
}

@MainActor
enum CommandCatalog {
    static func all(_ w: Workspace) -> [PaletteCommand] {
        var list: [PaletteCommand] = [
            .init(id: "open-folder", title: "Open Folder…", symbol: "folder", shortcut: "⇧⌘O") { $0.chooseFolder() },
            .init(id: "open", title: "Open File…", symbol: "doc", shortcut: "⌘O") { $0.chooseFiles() },
            .init(id: "new-file", title: "New File", symbol: "doc.badge.plus", shortcut: "⌘N") { $0.newFile() },
            .init(id: "save", title: "Save", symbol: "square.and.arrow.down", shortcut: "⌘S") { $0.save() },
            .init(id: "save-all", title: "Save All", symbol: "square.and.arrow.down.on.square", shortcut: "⌥⌘S") { $0.saveAll() },
            .init(id: "close-tab", title: "Close Tab", symbol: "xmark", shortcut: "⌘W") { _ = $0.closeActive() },
            .init(id: "sidebar", title: "Toggle Sidebar", symbol: "sidebar.left", shortcut: "⌃⌘S") { $0.toggleSidebar() },
            .init(id: "terminal", title: "Toggle Terminal", symbol: "terminal", shortcut: "⌃`") { $0.toggleTerminal() },
            .init(id: "search", title: "Search in Project", symbol: "magnifyingglass", shortcut: "⇧⌘F") { $0.focusSearch() },
            .init(id: "goto-line", title: "Go to Line…", symbol: "number", shortcut: "⌃G") { $0.showPalette(.line) },
            .init(id: "ascend", title: "Ascend (Focus Mode)", symbol: "sparkles", shortcut: "⇧⌘↩") { $0.toggleAscend() },
            .init(id: "wrap", title: Preferences.shared.wordWrap ? "Disable Word Wrap" : "Enable Word Wrap", symbol: "text.word.spacing", shortcut: "⌥⌘W") { _ in Preferences.shared.wordWrap.toggle() },
            .init(id: "zoom-in", title: "Increase Font Size", symbol: "textformat.size.larger", shortcut: "⌘=") { _ in Preferences.shared.adjustFontSize(1) },
            .init(id: "zoom-out", title: "Decrease Font Size", symbol: "textformat.size.smaller", shortcut: "⌘−") { _ in Preferences.shared.adjustFontSize(-1) },
            .init(id: "zoom-reset", title: "Reset Font Size", symbol: "textformat.size", shortcut: "⌘0") { _ in Preferences.shared.fontSize = 13.5 },
            .init(id: "theme-day", title: "Theme: Daybreak", symbol: "sun.max") { _ in Preferences.shared.appearance = .daybreak },
            .init(id: "theme-night", title: "Theme: Nightfall", symbol: "moon.stars") { _ in Preferences.shared.appearance = .nightfall },
            .init(id: "theme-system", title: "Theme: Follow System", symbol: "circle.lefthalf.filled") { _ in Preferences.shared.appearance = .system },
            .init(id: "refresh", title: "Refresh File Tree", symbol: "arrow.clockwise") { $0.refreshTree() },
            .init(id: "setup", title: "Show Setup Guide", symbol: "hand.wave") { $0.showSetup = true },
        ]
        if let url = w.active?.url {
            list += [
                .init(id: "reveal", title: "Reveal Active File in Finder", symbol: "arrow.up.forward.app") { _ in NSWorkspace.shared.activateFileViewerSelecting([url]) },
                .init(id: "reveal-sidebar", title: "Reveal Active File in Sidebar", symbol: "sidebar.left") { $0.reveal(url) },
                .init(id: "copy-path", title: "Copy Path of Active File", symbol: "doc.on.doc") { _ in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                },
            ]
        }
        if w.root != nil {
            list.append(.init(id: "close-folder", title: "Close Folder", symbol: "folder.badge.minus") { $0.closeFolder() })
        }
        return list
    }
}

struct CommandPalette: View {
    @Bindable var workspace: Workspace
    let initialMode: PaletteMode

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private enum Row: Identifiable {
        case file(IndexedFile, [Int])
        case command(PaletteCommand, [Int])
        case line(Int)
        case message(String)

        var id: String {
            switch self {
            case .file(let f, _): "f:" + f.relative
            case .command(let c, _): "c:" + c.id
            case .line(let n): "l:\(n)"
            case .message(let m): "m:" + m
            }
        }
    }

    private var mode: PaletteMode {
        if query.hasPrefix(">") { return .commands }
        if query.hasPrefix(":") { return .line }
        return .files
    }

    private var term: String {
        let t = mode == .files ? query : String(query.dropFirst())
        return t.trimmingCharacters(in: .whitespaces)
    }

    private var rows: [Row] {
        switch mode {
        case .files:
            let q = Array(term.lowercased().filter { !$0.isWhitespace }.utf16)
            if q.isEmpty {
                var seen = Set<String>()
                var out: [Row] = []
                for url in workspace.recentFiles {
                    let file = IndexedFile(url: url, relative: workspace.relativePath(url))
                    if seen.insert(file.relative).inserted { out.append(.file(file, [])) }
                }
                for file in workspace.index.prefix(80) where seen.insert(file.relative).inserted { out.append(.file(file, [])) }
                if out.isEmpty { return [.message(workspace.root == nil ? "Open a folder to search its files" : (workspace.isIndexing ? "Indexing…" : "No files"))] }
                return Array(out.prefix(80))
            }
            var scored: [(IndexedFile, Fuzzy.Match)] = []
            for file in workspace.index {
                if let m = Fuzzy.match(q, in: file) { scored.append((file, m)) }
            }
            scored.sort { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0.relative.count < $1.0.relative.count }
            let out = scored.prefix(60).map { Row.file($0.0, $0.1.positions) }
            return out.isEmpty ? [.message("No matching files")] : out
        case .commands:
            let commands = CommandCatalog.all(workspace)
            let q = Array(term.lowercased().utf16)
            if q.isEmpty { return commands.map { .command($0, []) } }
            let scored = commands.compactMap { c -> (PaletteCommand, Fuzzy.Match)? in
                let probe = IndexedFile(url: URL(fileURLWithPath: "/"), relative: c.title)
                return Fuzzy.match(q, in: probe).map { (c, $0) }
            }.sorted { $0.1.score > $1.1.score }
            return scored.isEmpty ? [.message("No matching commands")] : scored.map { .command($0.0, $0.1.positions) }
        case .line:
            if let n = Int(term.split(separator: ":").first ?? ""), n > 0 { return [.line(n)] }
            let total = workspace.active?.editor?.lineStarts.count ?? 0
            return [.message(workspace.active?.editor == nil ? "Open a file first" : "Type a line number between 1 and \(total)")]
        }
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: modeSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.haloSecondary)
                    .frame(width: 20)
                    .contentTransition(.symbolEffect(.replace))
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { run(rows) }
                    .onKeyPress(.downArrow) { step(1, rows.count); return .handled }
                    .onKeyPress(.upArrow) { step(-1, rows.count); return .handled }
                    .onKeyPress(.escape) { workspace.dismissPalette(); return .handled }
                    .onKeyPress(keys: ["n", "j"], phases: .down) { press in
                        guard press.modifiers.contains(.control) else { return .ignored }
                        step(1, rows.count); return .handled
                    }
                    .onKeyPress(keys: ["p", "k"], phases: .down) { press in
                        guard press.modifiers.contains(.control) else { return .ignored }
                        step(-1, rows.count); return .handled
                    }
            }
            .padding(.horizontal, 18)
            .frame(height: 54)

            Rectangle().fill(Color.haloHairline).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            rowView(row, selected: i == selection)
                                .id(i)
                                .onTapGesture { selection = i; run(rows) }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selection) { _, s in proxy.scrollTo(s) }
            }

            Rectangle().fill(Color.haloHairline).frame(height: 1)
            HStack(spacing: 14) {
                footerHint("↑↓", "navigate")
                footerHint("↩", "open")
                footerHint("esc", "close")
                Spacer()
                Text(mode == .files ? "Type > for commands, : for a line" : (mode == .commands ? "Commands" : "Go to line"))
                    .foregroundStyle(Color.haloTertiary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 14)
            .frame(height: 30)
        }
        .frame(width: 640)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 30, y: 14)
        .onAppear {
            query = initialMode.prefix
            focused = true
        }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private var modeSymbol: String {
        switch mode {
        case .files: "magnifyingglass"
        case .commands: "command"
        case .line: "number"
        }
    }

    private var placeholder: String {
        switch mode {
        case .files: "Search files by name"
        case .commands: "Run a command"
        case .line: "Go to line"
        }
    }

    private func step(_ delta: Int, _ count: Int) {
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func run(_ rows: [Row]) {
        guard rows.indices.contains(selection) else { return }
        let row = rows[selection]
        switch row {
        case .file(let file, _):
            workspace.dismissPalette()
            workspace.open(file.url)
        case .command(let command, _):
            workspace.dismissPalette()
            DispatchQueue.main.async { command.run(workspace) }
        case .line(let n):
            let parts = term.split(separator: ":")
            let column = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            workspace.dismissPalette()
            DispatchQueue.main.async { workspace.active?.editor?.textView.goTo(line: n, column: column) }
        case .message:
            break
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, selected: Bool) -> some View {
        HStack(spacing: 10) {
            switch row {
            case .file(let file, let positions):
                FileIconView(url: file.url, size: 16)
                    .frame(width: 18)
                Text(highlighted(file.url.lastPathComponent, positions: positions, offset: file.nameStart, base: .haloText, highlight: .haloSky))
                    .font(.system(size: 13))
                    .lineLimit(1)
                let dir = (file.relative as NSString).deletingLastPathComponent
                if !dir.isEmpty {
                    Text(dir)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.haloTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
            case .command(let command, let positions):
                Image(systemName: command.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.haloSecondary)
                    .frame(width: 18)
                Text(highlighted(command.title, positions: positions, base: .haloText, highlight: .haloSky))
                    .font(.system(size: 13))
                Spacer(minLength: 0)
                if let s = command.shortcut { Kbd(s) }
            case .line(let n):
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.haloSecondary)
                    .frame(width: 18)
                Text("Go to line \(n)").font(.system(size: 13)).foregroundStyle(Color.haloText)
                Spacer(minLength: 0)
            case .message(let m):
                Text(m).font(.system(size: 13)).foregroundStyle(Color.haloTertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.haloSky.opacity(0.16) : .clear)
        )
        .contentShape(Rectangle())
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(Color.haloSecondary)
            Text(label).foregroundStyle(Color.haloTertiary)
        }
    }
}
