import SwiftUI

struct Sidebar: View {
    @Bindable var workspace: Workspace
    @Namespace private var modeIndicator

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch workspace.sidebarMode {
                case .files: FileTreeView(workspace: workspace)
                case .search: SearchPanel(workspace: workspace)
                case .git: SourceControlView(workspace: workspace, scm: workspace.scm)
                case .debug: DebugSidebar(workspace: workspace)
                }
            }
            .transition(.opacity)
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            mode(.files, symbol: "folder", label: "Files")
            mode(.search, symbol: "magnifyingglass", label: "Search in Project (⇧⌘F)")
            mode(.git, symbol: "arrow.triangle.branch", label: "Source Control (⌃⇧G)", badge: workspace.scm.changes.count)
            mode(.debug, symbol: "ladybug", label: "Run and Debug (⇧⌘D)", badge: workspace.debug?.isActive == true ? -1 : 0)
            Spacer()
            if workspace.sidebarMode == .files {
                IconButton(symbol: "doc.badge.plus", label: "New File") { workspace.createItem(in: nil, folder: false) }
                IconButton(symbol: "folder.badge.plus", label: "New Folder") { workspace.createItem(in: nil, folder: true) }
                IconButton(symbol: "arrow.clockwise", label: "Refresh") { workspace.refreshTree() }
            } else if workspace.sidebarMode == .git {
                IconButton(symbol: "arrow.clockwise", label: "Refresh") { workspace.scm.refresh(folder: workspace.root) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func mode(_ mode: SidebarMode, symbol: String, label: String, badge: Int = 0) -> some View {
        let selected = workspace.sidebarMode == mode
        return Button {
            if mode == .search { workspace.focusSearch() } else { withAnimation(Motion.snappy) { workspace.sidebarMode = mode } }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(selected ? Color.haloText : Color.haloSecondary)
                .frame(width: 28, height: 26)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .matchedGeometryEffect(id: "mode", in: modeIndicator)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Capsule().fill(Color.haloAction))
                            .offset(x: 3, y: -2)
                    } else if badge < 0 {
                        Circle().fill(Color.haloAdded).frame(width: 6, height: 6).offset(x: -3, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - File tree

struct FileTreeView: View {
    @Bindable var workspace: Workspace
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let root = workspace.root {
                HStack(spacing: 6) {
                    Text(root.lastPathComponent.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Color.haloSecondary)
                        .lineLimit(1)
                    if let branch = workspace.git.branch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 9, weight: .semibold))
                            Text(branch).lineLimit(1)
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.haloTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(workspace.rows) { node in
                            FileRow(node: node, workspace: workspace)
                                .id(node.url)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.automatic)
                .onChange(of: workspace.sidebarSelection) { _, url in
                    guard let url else { return }
                    withAnimation(Motion.snappy) { proxy.scrollTo(url, anchor: nil) }
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.rightArrow) { setExpanded(true); return .handled }
            .onKeyPress(.leftArrow) { setExpanded(false); return .handled }
            .onKeyPress(.return) { activateSelection(); return .handled }
        }
        .contextMenu {
            Button("New File…") { workspace.createItem(in: nil, folder: false) }
            Button("New Folder…") { workspace.createItem(in: nil, folder: true) }
            Divider()
            if let root = workspace.root {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
            }
        }
    }

    private func move(_ delta: Int) {
        let rows = workspace.rows
        guard !rows.isEmpty else { return }
        let i = rows.firstIndex { $0.url == workspace.sidebarSelection } ?? (delta > 0 ? -1 : rows.count)
        let next = rows[max(0, min(rows.count - 1, i + delta))]
        workspace.sidebarSelection = next.url
    }

    private func setExpanded(_ expand: Bool) {
        guard let url = workspace.sidebarSelection, let node = workspace.rows.first(where: { $0.url == url }) else { return }
        if node.isDirectory, workspace.isExpanded(url) != expand { withAnimation(Motion.snappy) { workspace.toggle(url) } }
        else if !expand, let root = workspace.root {
            let parent = url.deletingLastPathComponent().standardizedFileURL
            if parent.path != root.path { workspace.sidebarSelection = parent }
        }
    }

    private func activateSelection() {
        guard let url = workspace.sidebarSelection, let node = workspace.rows.first(where: { $0.url == url }) else { return }
        if node.isDirectory { withAnimation(Motion.snappy) { workspace.toggle(url) } } else { workspace.open(url) }
    }
}

struct FileRow: View {
    let node: FileNode
    @Bindable var workspace: Workspace
    @State private var hovering = false

    private var isExpanded: Bool { workspace.isExpanded(node.url) }
    private var isActive: Bool { !node.isDirectory && workspace.active?.url?.standardizedFileURL == node.url.standardizedFileURL }
    private var isSelected: Bool { workspace.sidebarSelection == node.url }
    private static let indent: CGFloat = 12

    var body: some View {
        let git = workspace.gitState(for: node.url)
        HStack(spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Color.haloTertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
                .opacity(node.isDirectory ? 1 : 0)
            FileIconView(url: node.url, isDirectory: node.isDirectory, expanded: isExpanded, size: 16)
            Text(node.name)
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .foregroundStyle(nameColor(git))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let git {
                gitBadge(git, folder: node.isDirectory)
            }
        }
        .padding(.leading, CGFloat(node.depth) * Self.indent + 4)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background(alignment: .leading) { guides }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            workspace.sidebarSelection = node.url
            if node.isDirectory { withAnimation(Motion.snappy) { workspace.toggle(node.url) } }
            else { workspace.open(node.url) }
        }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(node.isDirectory ? "Folder \(node.name)" : node.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var rowFill: Color {
        if isActive { return Color.haloSky.opacity(0.15) }
        if isSelected { return Color.primary.opacity(0.07) }
        if hovering { return Color.primary.opacity(0.045) }
        return .clear
    }

    private func nameColor(_ git: GitState?) -> Color {
        if node.name.hasPrefix(".") { return Color.haloTertiary }
        switch git {
        case .untracked?, .added?: return node.isDirectory ? Color.haloText : Color.haloAdded
        case .modified? where !node.isDirectory, .renamed?: return Color.haloModified
        case .conflicted?: return Color(hex: 0xD9485F)
        case .deleted?: return Color.haloTertiary
        default: return Color.haloText
        }
    }

    @ViewBuilder private func gitBadge(_ state: GitState, folder: Bool) -> some View {
        if folder {
            Circle().fill(Color.haloModified.opacity(0.7)).frame(width: 5, height: 5)
                .accessibilityLabel("Contains changes")
        } else {
            let (letter, color): (String, Color) = switch state {
            case .untracked: ("U", .haloAdded)
            case .added: ("A", .haloAdded)
            case .modified: ("M", .haloModified)
            case .renamed: ("R", .haloModified)
            case .deleted: ("D", Color(hex: 0xD9485F))
            case .conflicted: ("!", Color(hex: 0xD9485F))
            }
            Text(letter)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .accessibilityLabel("Git: \(String(describing: state))")
        }
    }

    private var guides: some View {
        HStack(spacing: 0) {
            ForEach(0..<node.depth, id: \.self) { _ in
                Rectangle()
                    .fill(Color.haloHairline)
                    .frame(width: 1)
                    .padding(.leading, 8.5)
                    .padding(.trailing, Self.indent - 9.5)
            }
        }
    }

    @ViewBuilder private var menu: some View {
        let dir = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        if !node.isDirectory { Button("Open") { workspace.open(node.url) } }
        Button("New File…") { workspace.createItem(in: dir, folder: false) }
        Button("New Folder…") { workspace.createItem(in: dir, folder: true) }
        Divider()
        Button("Rename…") { workspace.rename(node.url) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        Button("Open in Terminal") {
            if !workspace.showTerminal { workspace.toggleTerminal() }
            workspace.terminal.changeDirectory(to: dir)
        }
        Divider()
        Button("Copy Path") { copy(node.url.path) }
        Button("Copy Relative Path") { copy(workspace.relativePath(node.url)) }
        Divider()
        Button("Move to Trash", role: .destructive) { workspace.moveToTrash(node.url) }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

// MARK: - Project search

struct SearchPanel: View {
    @Bindable var workspace: Workspace
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.haloTertiary)
                TextField("Search in project", text: $workspace.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($fieldFocused)
                    .onSubmit { openFirst() }
                toggle("textformat", "Match Case", $workspace.searchCaseSensitive)
                toggle("asterisk", "Use Regular Expression", $workspace.searchRegex)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(fieldFocused ? Color.haloSky.opacity(0.5) : Color.haloHairline))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            summary
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(workspace.searchResults) { file in
                        SearchFileSection(file: file, workspace: workspace)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .onAppear { fieldFocused = true }
        .onChange(of: workspace.searchFocusToken) { _, _ in fieldFocused = true }
    }

    @ViewBuilder private var summary: some View {
        HStack {
            if workspace.isSearching {
                ProgressView().controlSize(.mini)
                Text("Searching…")
            } else if workspace.searchQuery.isEmpty {
                Text(workspace.isIndexing ? "Indexing files…" : "\(workspace.index.count) files indexed")
            } else if workspace.searchResults.isEmpty {
                Text("No results")
            } else {
                Text("\(workspace.searchTotal)\(workspace.searchTruncated ? "+" : "") results in \(workspace.searchResults.count) files")
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.haloTertiary)
    }

    private func toggle(_ symbol: String, _ label: String, _ binding: Binding<Bool>) -> some View {
        IconButton(symbol: symbol, label: label, size: 11, active: binding.wrappedValue) { binding.wrappedValue.toggle() }
    }

    private func openFirst() {
        guard let file = workspace.searchResults.first, let match = file.matches.first else { return }
        workspace.open(file.url, line: match.line, column: match.column)
    }
}

struct SearchFileSection: View {
    let file: SearchFileResult
    @Bindable var workspace: Workspace
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.snappy) { collapsed.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.haloTertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .frame(width: 10)
                    FileIconView(url: file.url, size: 14)
                    Text(file.url.lastPathComponent).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.haloText)
                    Text((file.relative as NSString).deletingLastPathComponent)
                        .font(.system(size: 11)).foregroundStyle(Color.haloTertiary).lineLimit(1).truncationMode(.head)
                    Spacer(minLength: 4)
                    Text("\(file.matches.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.haloSecondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .frame(height: 24)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                ForEach(file.matches) { match in
                    SearchMatchRow(match: match) { workspace.open(file.url, line: match.line, column: match.column) }
                }
            }
        }
        .padding(.top, 4)
    }
}

struct SearchMatchRow: View {
    let match: SearchMatch
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(match.line)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.haloTertiary)
                    .frame(minWidth: 26, alignment: .trailing)
                Text(attributed)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var attributed: AttributedString {
        let text = match.preview
        var out = AttributedString(text)
        out.foregroundColor = Color.haloSecondary
        let chars = Array(text)
        guard match.highlight.lowerBound >= 0, match.highlight.upperBound <= chars.count else { return out }
        let start = text.index(text.startIndex, offsetBy: match.highlight.lowerBound)
        let end = text.index(text.startIndex, offsetBy: match.highlight.upperBound)
        if let lo = AttributedString.Index(start, within: out), let hi = AttributedString.Index(end, within: out) {
            out[lo..<hi].foregroundColor = Color.haloText
            out[lo..<hi].backgroundColor = Color.haloSky.opacity(0.2)
        }
        return out
    }
}
