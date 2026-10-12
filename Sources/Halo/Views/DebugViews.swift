import SwiftUI

// MARK: - Sidebar: Run and Debug

struct DebugSidebar: View {
    @Bindable var workspace: Workspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let session = workspace.debug, session.isActive {
                    SessionHeader(session: session)
                    VariablesSection(session: session)
                    CallStackSection(session: session)
                } else {
                    startCard
                }
                BreakpointsSection(workspace: workspace)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            let doc = workspace.active
            Button { workspace.startDebugging() } label: {
                Label("Run and Debug", systemImage: "play.fill")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.haloAction)
            .disabled(doc?.url == nil)
            Text(hint(for: doc))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.haloSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private func hint(for doc: Document?) -> String {
        guard let doc else { return "Open a Python, C, C++, Swift or Rust file, click in the gutter to add breakpoints, then press F5." }
        if DebugSession.supports(doc.language) {
            return "Debugs \(doc.name) with \(doc.language.id == "python" ? "debugpy" : "LLDB"). Click a line number to set a breakpoint."
        }
        return "\(doc.language.name) can’t be debugged yet. Run it with ⌘R."
    }
}

private struct SessionHeader: View {
    let session: DebugSession

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.state == .stopped ? Color(nsColor: Palette.executionMarker) : Color.haloAdded)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.haloText)
                Text(status).font(.system(size: 11)).foregroundStyle(Color.haloSecondary)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    private var status: String {
        switch session.state {
        case .building: "Building…"
        case .starting: "Starting…"
        case .running: "Running"
        case .stopped: "Paused" + (session.stopReason.map { " on \($0)" } ?? "")
        case .ended: "Ended"
        }
    }
}

private struct VariablesSection: View {
    @Bindable var session: DebugSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionTitle("Variables")
            if session.state != .stopped {
                Text("Variables appear when the program pauses.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.haloTertiary).padding(.leading, 4)
            }
            ForEach(session.scopes) { scope in
                DisclosureRow(title: scope.name, value: nil, type: nil, depth: 0, expandable: true,
                              expanded: session.expanded.contains(scope.reference)) {
                    withAnimation(Motion.snappy) { session.toggle(scope.reference) }
                }
                if session.expanded.contains(scope.reference) {
                    VariableTree(session: session, reference: scope.reference, depth: 1)
                }
            }
        }
    }
}

private struct VariableTree: View {
    @Bindable var session: DebugSession
    let reference: Int
    let depth: Int

    var body: some View {
        ForEach(session.variables[reference] ?? []) { variable in
            DisclosureRow(title: variable.name, value: variable.value, type: variable.type, depth: depth,
                          expandable: variable.reference > 0, expanded: session.expanded.contains(variable.reference)) {
                withAnimation(Motion.snappy) { session.toggle(variable.reference) }
            }
            if variable.reference > 0, session.expanded.contains(variable.reference), depth < 8 {
                VariableTree(session: session, reference: variable.reference, depth: depth + 1)
            }
        }
    }
}

private struct DisclosureRow: View {
    let title: String
    let value: String?
    let type: String?
    let depth: Int
    let expandable: Bool
    let expanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.haloTertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 10)
                .opacity(expandable ? 1 : 0)
            Text(title)
                .font(.system(size: 12, weight: value == nil ? .semibold : .regular, design: value == nil ? .default : .monospaced))
                .foregroundStyle(value == nil ? Color.haloSecondary : Color(nsColor: SyntaxPalette.property))
                .lineLimit(1)
            if let value {
                Text("=").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.haloTertiary)
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(nsColor: color(for: value)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 12 + 2)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if expandable { toggle() } }
        .help(type.map { "\(title): \($0)" } ?? title)
    }

    private func color(for value: String) -> NSColor {
        if value.hasPrefix("\"") || value.hasPrefix("'") { return SyntaxPalette.string }
        if Double(value) != nil || value.hasPrefix("0x") { return SyntaxPalette.number }
        if ["true", "false", "True", "False", "None", "nil", "null", "NULL"].contains(value) { return SyntaxPalette.number }
        return Palette.text
    }
}

private struct CallStackSection: View {
    @Bindable var session: DebugSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionTitle("Call Stack")
            ForEach(session.frames) { frame in
                Button { session.select(frame) } label: {
                    HStack(spacing: 6) {
                        Text(frame.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(frame.path == nil ? Color.haloTertiary : Color.haloText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let path = frame.path {
                            Text("\(URL(fileURLWithPath: path).lastPathComponent):\(frame.line)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.haloTertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(session.selectedFrameID == frame.id ? Color.haloSky.opacity(0.15) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct BreakpointsSection: View {
    @Bindable var workspace: Workspace

    var body: some View {
        let items = workspace.breakpoints.flatMap { path, lines in lines.map { (path, $0) } }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionTitle("Breakpoints", count: items.count)
                Spacer()
                if !items.isEmpty {
                    IconButton(symbol: "xmark.circle", label: "Remove All Breakpoints", size: 11) { workspace.removeAllBreakpoints() }
                }
            }
            if items.isEmpty {
                Text("Click a line number to add one.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.haloTertiary).padding(.leading, 4)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: Palette.breakpoint)).frame(width: 8, height: 8)
                    Text(URL(fileURLWithPath: item.0).lastPathComponent).font(.system(size: 12)).foregroundStyle(Color.haloText)
                    Text("line \(item.1)").font(.system(size: 11)).foregroundStyle(Color.haloTertiary)
                    Spacer()
                    IconButton(symbol: "xmark", label: "Remove", size: 9) { workspace.toggleBreakpoint(path: item.0, line: item.1) }
                }
                .frame(height: 24)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture { workspace.open(URL(fileURLWithPath: item.0), line: item.1) }
            }
        }
    }
}

// MARK: - Floating debug toolbar

struct DebugToolbar: View {
    @Bindable var session: DebugSession
    @Bindable var workspace: Workspace

    var body: some View {
        HStack(spacing: 2) {
            if session.state == .stopped {
                control("play.fill", "Continue (F5)") { session.resume() }
            } else {
                control("pause.fill", "Pause (F6)", enabled: session.state == .running) { session.pause() }
            }
            control("arrow.turn.down.right", "Step Over (F10)", enabled: session.state == .stopped) { session.stepOver() }
            control("arrow.down.to.line", "Step Into (F11)", enabled: session.state == .stopped) { session.stepInto() }
            control("arrow.up.to.line", "Step Out (⇧F11)", enabled: session.state == .stopped) { session.stepOut() }
            Divider().frame(height: 16).padding(.horizontal, 3)
            control("arrow.clockwise", "Restart (⇧⌘F5)") {
                session.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { workspace.startDebugging() }
            }
            control("stop.fill", "Stop (⇧F5)", tint: Color(nsColor: Palette.error)) { session.stop() }
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func control(_ symbol: String, _ label: String, enabled: Bool = true, tint: Color = .haloText, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? tint : Color.haloTertiary)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
