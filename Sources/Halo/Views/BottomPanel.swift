import SwiftUI

/// Terminal, Problems, Output and Debug Console in one resizable panel.
struct BottomPanel: View {
    @Bindable var workspace: Workspace
    @State private var dragStart: CGFloat?
    @Namespace private var tabIndicator

    private var tabs: [PanelTab] {
        workspace.debug == nil ? [.terminal, .problems, .output] : [.terminal, .problems, .output, .debugConsole]
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.haloChrome)
    }

    private var resizeHandle: some View {
        Rectangle().fill(Color.haloHairline).frame(height: 1)
            .frame(height: 7)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStart == nil { dragStart = workspace.terminalHeight }
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) {
                            workspace.terminalHeight = min(720, max(120, (dragStart ?? 240) - value.translation.height))
                        }
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }

    private var header: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(Motion.snappy) { workspace.panelTab = tab }
                    if tab == .terminal {
                        workspace.terminal.startIfNeeded(in: workspace.root)
                        DispatchQueue.main.async { workspace.terminal.focus() }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.title)
                        if tab == .problems {
                            let counts = workspace.problemCounts
                            if counts.errors + counts.warnings > 0 {
                                Text("\(counts.errors + counts.warnings)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(counts.errors > 0 ? .white : Color.haloText)
                                    .padding(.horizontal, 5)
                                    .background(Capsule().fill(counts.errors > 0 ? Color(nsColor: Palette.error) : Color.primary.opacity(0.1)))
                            }
                        }
                    }
                    .font(.system(size: 11.5, weight: workspace.panelTab == tab ? .semibold : .regular))
                    .foregroundStyle(workspace.panelTab == tab ? Color.haloText : Color.haloSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .overlay(alignment: .bottom) {
                        if workspace.panelTab == tab {
                            Capsule().fill(Color.haloAction).frame(height: 2)
                                .padding(.horizontal, 6)
                                .matchedGeometryEffect(id: "tab", in: tabIndicator)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if workspace.isBuilding {
                ProgressView().controlSize(.mini).padding(.trailing, 6)
            }
            switch workspace.panelTab {
            case .terminal:
                IconButton(symbol: "stop.circle", label: "Interrupt (⌃C)", size: 11) { workspace.terminal.interrupt() }
            case .output:
                IconButton(symbol: "trash", label: "Clear Output", size: 11) { workspace.buildLog = [] }
            default:
                EmptyView()
            }
            IconButton(symbol: "chevron.down", label: "Hide Panel", size: 11) { workspace.toggleTerminal() }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }

    @ViewBuilder private var content: some View {
        switch workspace.panelTab {
        case .terminal:
            TerminalHost(session: workspace.terminal)
                .padding(.leading, 10)
                .padding(.bottom, 4)
        case .problems:
            ProblemsList(workspace: workspace)
        case .output:
            LogView(lines: workspace.buildLog.map { ($0, Color.haloText) }, empty: "Build output appears here when you run compiled code.")
        case .debugConsole:
            if let session = workspace.debug {
                DebugConsole(session: session)
            }
        }
    }
}

private struct ProblemsList: View {
    @Bindable var workspace: Workspace

    var body: some View {
        let files = workspace.diagnostics.keys.sorted()
        if files.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.system(size: 18)).foregroundStyle(Color.haloAdded)
                Text("No problems").font(.system(size: 12)).foregroundStyle(Color.haloSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(files, id: \.self) { path in
                        let url = URL(fileURLWithPath: path)
                        HStack(spacing: 6) {
                            FileIconView(url: url, size: 13)
                            Text(url.lastPathComponent).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.haloText)
                            Text(workspace.relativePath(url)).font(.system(size: 11)).foregroundStyle(Color.haloTertiary).lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                        ForEach(workspace.diagnostics[path] ?? []) { d in
                            ProblemRow(diagnostic: d) { workspace.open(url, line: d.line, column: d.column ?? 1) }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

private struct ProblemRow: View {
    let diagnostic: Diagnostic
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: diagnostic.severity == .error ? "xmark.circle.fill" : diagnostic.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(nsColor: diagnostic.color))
                Text(diagnostic.message).font(.system(size: 12)).foregroundStyle(Color.haloText).lineLimit(2)
                Text("\(diagnostic.source) · \(diagnostic.line)\(diagnostic.column.map { ":\($0)" } ?? "")")
                    .font(.system(size: 11)).foregroundStyle(Color.haloTertiary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 30)
            .padding(.trailing, 12)
            .padding(.vertical, 3)
            .background(hovering ? Color.primary.opacity(0.05) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct LogView: View {
    let lines: [(String, Color)]
    let empty: String

    var body: some View {
        if lines.isEmpty {
            Text(empty).font(.system(size: 12)).foregroundStyle(Color.haloTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line.0.isEmpty ? " " : line.0)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(line.1)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .onAppear { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                .onChange(of: lines.count) { _, n in proxy.scrollTo(n - 1, anchor: .bottom) }
            }
        }
    }
}

private struct DebugConsole: View {
    @Bindable var session: DebugSession
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            LogView(lines: session.console.map { line in
                switch line.kind {
                case .output: (line.text, Color.haloText)
                case .error: (line.text, Color(nsColor: Palette.error))
                case .info: (line.text, Color.haloTertiary)
                case .input: ("› " + line.text, Color.haloSky)
                case .result: (line.text, Color(nsColor: SyntaxPalette.string))
                }
            }, empty: "Program output and expression results appear here.")
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.haloSky)
                TextField(session.state == .stopped ? "Evaluate an expression" : "Pause the program to evaluate expressions", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($focused)
                    .disabled(session.state != .stopped)
                    .onSubmit {
                        session.evaluate(input)
                        input = ""
                        focused = true
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .overlay(alignment: .top) { Rectangle().fill(Color.haloHairline).frame(height: 1) }
        }
    }
}
