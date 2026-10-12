import SwiftUI
import AppKit

extension FocusedValues {
    @Entry var workspace: Workspace?
}

struct ContentView: View {
    @State private var workspace = Workspace()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static var isFirstWindow = true

    var body: some View {
        NavigationSplitView(columnVisibility: $workspace.columnVisibility) {
            Sidebar(workspace: workspace)
                .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 420)
        } detail: {
            detail
                .toolbar { toolbar }
        }
        .navigationTitle(workspace.title)
        .navigationSubtitle(subtitle)
        .toolbar(removing: workspace.root == nil ? .sidebarToggle : nil)
        .toolbar(workspace.ascended ? .hidden : .visible, for: .windowToolbar)
        .focusedSceneValue(\.workspace, workspace)
        .background(WindowAccessor(workspace: workspace))
        .sheet(isPresented: $workspace.showSetup) { SetupGuide() }
        .onAppear {
            SettingsOpener.action = openSettings
            launch()
        }
        // Files and folders opened from Finder or the Dock land in an existing
        // window instead of SwiftUI spawning a new one per event.
        .onOpenURL(perform: handleExternalOpen)
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    private var subtitle: String {
        guard let doc = workspace.active, workspace.root != nil else { return "" }
        return doc.isDirty ? "\(doc.name) — Edited" : doc.name
    }

    @ViewBuilder private var detail: some View {
        ZStack(alignment: .top) {
            if workspace.root == nil && workspace.documents.isEmpty {
                WelcomeView(workspace: workspace)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    if !workspace.ascended && !workspace.documents.isEmpty {
                        TabBar(workspace: workspace)
                    }
                    EditorArea(workspace: workspace)
                        .overlay(alignment: .top) {
                            if let session = workspace.debug, session.isActive, !workspace.ascended {
                                DebugToolbar(session: session, workspace: workspace)
                                    .padding(.top, 10)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .animation(Motion.snappy, value: workspace.debug?.isActive == true)
                    if workspace.showTerminal {
                        BottomPanel(workspace: workspace)
                            .frame(height: workspace.terminalHeight)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if !workspace.ascended {
                        StatusBar(workspace: workspace)
                    }
                }
                .background(Color.haloEditor)
                .transition(.opacity)
            }

            if let mode = workspace.palette {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { workspace.dismissPalette() }
                CommandPalette(workspace: workspace, initialMode: mode)
                    .padding(.top, workspace.ascended ? 80 : 56)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.97, anchor: .top)),
                        removal: .opacity))
                    .zIndex(10)
            }

            if let toast = workspace.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.haloText)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.bottom, 44)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(11)
            }
        }
        .animation(Motion.gentle, value: workspace.root == nil && workspace.documents.isEmpty)
        .ignoresSafeArea(.container, edges: workspace.ascended ? .top : [])
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { workspace.open(url) }
                }
            }
            return true
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if workspace.debug?.isActive == true || workspace.isBuilding {
                Button { workspace.stopRunning() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop (⌘.)")
            } else {
                Button { workspace.runActive() } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .help("Run (⌘R)")
                .disabled(!workspace.canRun)
            }
            Button { workspace.startDebugging() } label: {
                Label("Debug", systemImage: "ladybug")
            }
            .help("Run and Debug (F5)")
            .disabled(!workspace.canRun)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button { workspace.showPalette(.files) } label: {
                Label(workspace.root.map { "Search \($0.lastPathComponent)" } ?? "Search", systemImage: "magnifyingglass")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 170, alignment: .leading)
            }
            .help("Quick Open (⌘P)")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button { workspace.toggleTerminal() } label: {
                Label("Panel", systemImage: "rectangle.bottomthird.inset.filled")
            }
            .help("Toggle Panel (⌃`)")
            Button { workspace.toggleAscend() } label: {
                Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Focus Mode (⇧⌘↩)")
        }
    }

    private func handleExternalOpen(_ url: URL) {
        guard url.isFileURL else { return }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue, let root = workspace.root, root != url.standardizedFileURL {
            WorkspaceRegistry.pendingOpen.append(url)   // another project → its own window
            openWindow(id: "workspace")
        } else {
            workspace.open(url)
        }
    }

    private func launch() {
        Preferences.shared.applyAppearance()
        WorkspaceRegistry.focus(workspace)
        let pending = WorkspaceRegistry.pendingOpen
        WorkspaceRegistry.pendingOpen = []
        let restore = Self.isFirstWindow && Preferences.shared.hasCompletedSetup ? Preferences.shared.recentFolders.first : nil
        DispatchQueue.main.async {
            if !pending.isEmpty {
                pending.forEach { workspace.open($0) }
            } else if let restore {
                workspace.openFolder(restore)   // pick up where you left off
            }
        }
        if Self.isFirstWindow && !Preferences.shared.hasCompletedSetup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { workspace.showSetup = true }
        }
        Self.isFirstWindow = false
    }
}

/// Reaches the hosting NSWindow to tune it and to guard closing with
/// unsaved changes.
struct WindowAccessor: NSViewRepresentable {
    let workspace: Workspace

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.workspace = workspace
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        weak var workspace: Workspace?
        private var proxy: WindowDelegateProxy?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let workspace else { return }
            window.minSize = NSSize(width: 720, height: 460)
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = Palette.editorBackground
            window.tabbingMode = .disallowed
            if proxy == nil {
                let proxy = WindowDelegateProxy(original: window.delegate, workspace: workspace)
                self.proxy = proxy
                window.delegate = proxy
            }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak workspace] _ in
                MainActor.assumeIsolated {
                    if let workspace { WorkspaceRegistry.focus(workspace) }
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

/// Forwards everything to SwiftUI's own window delegate, but gets a say in
/// whether the window may close.
final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?
    weak var workspace: Workspace?

    init(original: NSWindowDelegate?, workspace: Workspace) {
        self.original = original
        self.workspace = workspace
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let allowed = MainActor.assumeIsolated { workspace?.confirmCloseAll() ?? true }
        guard allowed else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if original?.responds(to: aSelector) == true { return original }
        return super.forwardingTarget(for: aSelector)
    }
}
