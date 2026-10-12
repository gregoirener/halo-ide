import SwiftUI
import AppKit

struct EditorArea: View {
    @Bindable var workspace: Workspace

    var body: some View {
        let active = workspace.active
        let textDocument = active?.kind == .text ? active : nil
        // The AppKit host stays mounted for the window's lifetime; only the
        // document inside it changes. Overlays cover it for other states.
        ZStack {
            let path = textDocument?.url?.standardizedFileURL.path ?? ""
            EditorHost(document: textDocument, language: textDocument?.language, ascended: workspace.ascended,
                       workspace: workspace,
                       breakpoints: workspace.breakpoints[path] ?? [],
                       executionLine: workspace.debug?.location?.path == path ? workspace.debug?.location?.line : nil,
                       diagnostics: workspace.diagnostics[path] ?? [],
                       lineChanges: workspace.lineChanges[path] ?? [])
            if let doc = active {
                switch doc.kind {
                case .text:
                    EmptyView()
                case .image:
                    ImagePreview(document: doc).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.haloEditor)
                case .binary:
                    FileNotice(symbol: "doc.zipper", title: "Binary file", message: "Halo doesn’t display binary files.", url: doc.url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.haloEditor)
                case .tooLarge:
                    FileNotice(symbol: "scalemass", title: "File is too large", message: "Files over 24 MB are better opened elsewhere.", url: doc.url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.haloEditor)
                }
            } else {
                EmptyEditor(workspace: workspace).background(Color.haloEditor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.haloEditor)
        // Switching tabs should be instant, never a crossfade.
        .transaction(value: workspace.activeID) { $0.animation = nil }
    }
}

/// Hosts the active document's persistent AppKit editor. Switching tabs
/// swaps the scroll view inside, so each document keeps its own undo stack,
/// selection and scroll position.
struct EditorHost: NSViewRepresentable {
    let document: Document?
    let language: Language?    // read so a Save As that changes language rebuilds
    let ascended: Bool
    let workspace: Workspace
    let breakpoints: Set<Int>
    let executionLine: Int?
    let diagnostics: [Diagnostic]
    let lineChanges: [LineChange]

    final class Container: NSView {
        weak var current: NSScrollView?
        override var isFlipped: Bool { true }
    }

    func makeNSView(context: Context) -> Container { Container() }

    func updateNSView(_ container: Container, context: Context) {
        let editor = document?.editor
        editor?.centeredWidth = ascended ? 780 : nil
        if let editor, let document {
            let path = document.url?.standardizedFileURL.path ?? ""
            editor.fileURL = document.url
            editor.breakpoints = breakpoints
            editor.executionLine = executionLine
            if editor.diagnostics != diagnostics { editor.setDiagnostics(diagnostics) }
            editor.lineChanges = lineChanges
            let workspace = self.workspace
            editor.onToggleBreakpoint = { [weak workspace] line in workspace?.toggleBreakpoint(path: path, line: line) }
            editor.onEdit = { [weak workspace, weak document] in
                if let document { workspace?.scheduleLint(document) }
            }
            // An error held back on the line you were typing appears once you leave it.
            document.onLineChange = { [weak workspace, weak document] line in
                guard let workspace, let document, let held = workspace.pendingLint[path], held != line else { return }
                workspace.scheduleLint(document)
            }
            if let line = executionLine, container.current === editor.scrollView {
                DispatchQueue.main.async { editor.revealLine(line) }
            }
        }
        guard container.current !== editor?.scrollView else { return }
        container.current?.removeFromSuperview()
        container.current = nil
        guard let editor else { return }
        let sv = editor.scrollView
        sv.frame = container.bounds
        sv.autoresizingMask = [.width, .height]
        container.addSubview(sv)
        container.current = sv
        DispatchQueue.main.async { editor.focus() }
    }
}

struct ImagePreview: View {
    let document: Document

    var body: some View {
        VStack(spacing: 14) {
            if let image = document.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(image.size.width < 64 ? .none : .high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: min(image.size.width * 2, 900), maxHeight: min(image.size.height * 2, 640))
                    .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: 10)))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(Color.haloTertiary)
            } else {
                FileNotice(symbol: "photo", title: "Can’t preview this image", message: "", url: document.url)
            }
        }
        .padding(40)
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 10
            for row in 0..<Int(size.height / s) + 1 {
                for col in 0..<Int(size.width / s) + 1 where (row + col) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * s, y: CGFloat(row) * s, width: s, height: s)), with: .color(.primary.opacity(0.05)))
                }
            }
        }
    }
}

struct FileNotice: View {
    let symbol: String
    let title: String
    let message: String
    let url: URL?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.haloTertiary)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.haloText)
            if !message.isEmpty {
                Text(message).font(.system(size: 13)).foregroundStyle(Color.haloSecondary)
            }
            if let url {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.glass)
                    .padding(.top, 6)
            }
        }
    }
}

struct EmptyEditor: View {
    @Bindable var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No file open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.haloText)
            VStack(alignment: .leading, spacing: 8) {
                hint("Quick Open", "⌘P")
                hint("Command Palette", "⇧⌘P")
                hint("Run Current File", "⌘R")
                hint("Start Debugging", "F5")
                hint("Search in Project", "⇧⌘F")
                hint("Toggle Panel", "⌃`")
            }
        }
        .frame(width: 280, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(Color.haloSecondary)
            Spacer()
            Kbd(keys)
        }
    }
}

// MARK: - Tabs

struct TabBar: View {
    @Bindable var workspace: Workspace
    @Namespace private var activeTab

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.documents) { doc in
                        TabItem(document: doc, workspace: workspace, duplicateName: isDuplicate(doc), namespace: activeTab)
                            .id(doc.id)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
                    }
                }
                .padding(.horizontal, 10)
                .animation(Motion.snappy, value: workspace.documents.map(\.id))
                .animation(Motion.snappy, value: workspace.activeID)
            }
            .onChange(of: workspace.activeID) { _, id in
                guard let id else { return }
                withAnimation(Motion.snappy) { proxy.scrollTo(id) }
            }
        }
        .frame(height: 40)
        .background(Color.haloEditor)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.haloHairline).frame(height: 1) }
    }

    private func isDuplicate(_ doc: Document) -> Bool {
        workspace.documents.filter { $0.name == doc.name }.count > 1
    }
}

struct TabItem: View {
    let document: Document
    @Bindable var workspace: Workspace
    let duplicateName: Bool
    let namespace: Namespace.ID
    @State private var hovering = false
    @State private var hoveringClose = false

    private var isActive: Bool { workspace.activeID == document.id }

    var body: some View {
        label
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .frame(height: 28)
            .background(background)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { workspace.activate(document) }
            .contextMenu { menu }
            .help(document.url?.path ?? "Untitled")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(traits)
    }

    private var traits: AccessibilityTraits { isActive ? [.isSelected, .isButton] : [.isButton] }
    private var accessibilityText: String { document.isDirty ? "\(document.name), edited" : document.name }

    private var label: some View {
        return HStack(spacing: 6) {
            FileIconView(url: document.url, size: 14)
            Text(document.name)
                .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Color.haloText : Color.haloSecondary)
                .lineLimit(1)
            if duplicateName, let parent = document.url?.deletingLastPathComponent().lastPathComponent {
                Text(parent).font(.system(size: 11)).foregroundStyle(Color.haloTertiary).lineLimit(1)
            }
            closeButton
        }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if isActive {
            // One highlight that slides from tab to tab.
            shape
                .fill(Color.haloRaised)
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .overlay(shape.strokeBorder(Color.haloHairline))
                .matchedGeometryEffect(id: "active", in: namespace)
        } else {
            shape.fill(hovering ? Color.primary.opacity(0.045) : Color.clear)
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Close") { workspace.close(document) }
        Button("Close Others") { workspace.closeOthers(document) }
        if let url = document.url {
            Divider()
            Button("Reveal in Sidebar") { workspace.reveal(url) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
        }
    }

    private var closeButton: some View {
        Button { workspace.close(document) } label: {
            ZStack {
                if document.isDirty && !hoveringClose {
                    Circle().fill(Color.haloSecondary).frame(width: 7, height: 7)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(hoveringClose ? Color.haloText : Color.haloTertiary)
                        .opacity(hovering || isActive ? 1 : 0)
                }
            }
            .frame(width: 18, height: 18)
            .background(Circle().fill(hoveringClose ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringClose = $0 }
        .accessibilityLabel("Close \(document.name)")
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @Bindable var workspace: Workspace

    var body: some View {
        HStack(spacing: 14) {
            let counts = workspace.problemCounts
            Button { workspace.showPanel(.problems) } label: {
                HStack(spacing: 8) {
                    Label("\(counts.errors)", systemImage: "xmark.circle")
                        .foregroundStyle(counts.errors > 0 ? Color(nsColor: Palette.error) : Color.haloTertiary)
                    Label("\(counts.warnings)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(counts.warnings > 0 ? Color(nsColor: Palette.warning) : Color.haloTertiary)
                }
            }
            .buttonStyle(.plain)
            .help("Problems (⇧⌘M)")
            if let branch = workspace.git.branch {
                Label {
                    Text(branch)
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                }
                .help(workspace.git.changedCount > 0 ? "\(workspace.git.changedCount) changed files" : "Working tree clean")
                if workspace.git.changedCount > 0 {
                    Label("\(workspace.git.changedCount)", systemImage: "circle.fill")
                        .labelStyle(DotLabelStyle())
                }
            }
            if let doc = workspace.active, let url = doc.url {
                Text(workspace.relativePath(url))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(Color.haloTertiary)
            }
            Spacer(minLength: 8)
            ClaudeBadge()
            SmartFillBadge()
            if Preferences.shared.fillEnabled, let percent = FillStats.shared.percent {
                Text("Fill \(percent)%")
                    .foregroundStyle(Color.haloSecondary)
                    .help("Share of your code written by Tab this session")
            }
            if let doc = workspace.active, doc.kind == .text {
                Text(doc.selectionLength > 0 ? "Ln \(doc.cursorLine), Col \(doc.cursorColumn) (\(doc.selectionLength) selected)" : "Ln \(doc.cursorLine), Col \(doc.cursorColumn)")
                    .monospacedDigit()
                Text("Spaces: \(doc.indentUnit)")
                Text(doc.usesCRLF ? "CRLF" : "LF")
                Text(doc.encoding == .utf8 ? "UTF-8" : "Windows-1252")
                Text(doc.language.name)
                    .foregroundStyle(Color.haloSecondary)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Color.haloTertiary)
        .labelStyle(CompactLabelStyle())
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(Color.haloEditor)
        .overlay(alignment: .top) { Rectangle().fill(Color.haloHairline).frame(height: 1) }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10, weight: .semibold))
            configuration.title
        }
    }
}

struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Color.haloModified).frame(width: 6, height: 6)
            configuration.title
        }
    }
}
