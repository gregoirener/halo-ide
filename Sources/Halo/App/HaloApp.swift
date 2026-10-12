import SwiftUI
import AppKit

@main
enum HaloMain {
    static func main() {
        // Claude launches `Halo --mcp`: be the stdio bridge, not the app.
        if CommandLine.arguments.dropFirst().contains(MCP.bridgeFlag) { MCPBridge.run() }
        HaloApp.main()
    }
}

struct HaloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Halo restores your last project itself; macOS window restoration
        // could otherwise bring back "no windows" after a forced quit.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true, "NSQuitAlwaysKeepsWindows": false,
                                                  "NSTreatUnknownArgumentsAsOpen": "NO"])
    }

    var body: some Scene {
        WindowGroup(id: "workspace") {
            ContentView()
        }
        .defaultSize(width: 1320, height: 860)
        .restorationBehavior(.disabled)
        .windowToolbarStyle(.unified)
        .commands { HaloCommands() }

        Settings {
            PreferencesView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        // `Halo <path>…` from a shell opens those paths.
        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        let urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        MainActor.assumeIsolated { WorkspaceRegistry.pendingOpen.append(contentsOf: urls) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Preferences.shared.applyAppearance()
            SmartFill.shared.refresh()
            MCPServer.shared.start()
            SnapshotDriver.startIfRequested()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            SmartFill.shared.stop()
            MCPServer.shared.stop()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            for workspace in WorkspaceRegistry.all where !workspace.confirmCloseAll() {
                return .terminateCancel
            }
            return .terminateNow
        }
    }
}

private func fn(_ key: Int) -> KeyEquivalent { KeyEquivalent(Character(UnicodeScalar(UInt16(key))!)) }

struct HaloCommands: Commands {
    @FocusedValue(\.workspace) private var workspace
    @Environment(\.openWindow) private var openWindow

    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") { workspace?.newFile() }
                .keyboardShortcut("n")
            Button("New Window") { openWindow(id: "workspace") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Open…") { workspace?.chooseFiles() }
                .keyboardShortcut("o")
            Button("Open Folder…") { workspace?.chooseFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Menu("Open Recent") {
                ForEach(Preferences.shared.recentFolders, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        if let workspace, workspace.root == nil { workspace.openFolder(url) }
                        else {
                            WorkspaceRegistry.pendingOpen.append(url)
                            openWindow(id: "workspace")
                        }
                    }
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { workspace?.save() }
                .keyboardShortcut("s")
            Button("Save As…") { workspace?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Save All") { workspace?.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button("Close Tab") {
                if workspace?.closeActive() != true { NSApp.keyWindow?.performClose(nil) }
            }
            .keyboardShortcut("w")
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Close Folder") { workspace?.closeFolder() }
                .disabled(workspace?.root == nil)
        }

        CommandGroup(replacing: .printItem) {}

        TextEditingCommands()

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Toggle Comment") { send(#selector(HaloTextView.toggleComment(_:))) }
                .keyboardShortcut("/")
            Button("Duplicate Line") { send(#selector(HaloTextView.duplicateLine(_:))) }
                .keyboardShortcut("d")
            Button("Move Line Up") { send(#selector(HaloTextView.moveLineUp(_:))) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button("Move Line Down") { send(#selector(HaloTextView.moveLineDown(_:))) }
                .keyboardShortcut("]", modifiers: [.command, .option])
        }

        Group {
            CommandMenu("Run") {
                Button("Run") { workspace?.runActive() }
                    .keyboardShortcut("r")
                    .disabled(workspace?.canRun != true)
                Button(workspace?.debug?.state == .stopped ? "Continue" : "Start Debugging") { workspace?.startDebugging() }
                    .keyboardShortcut(fn(NSF5FunctionKey), modifiers: [])
                Button("Stop") { workspace?.stopRunning() }
                    .keyboardShortcut(".")
                Divider()
                Button("Step Over") { workspace?.debug?.stepOver() }
                    .keyboardShortcut(fn(NSF10FunctionKey), modifiers: [])
                    .disabled(workspace?.debug?.state != .stopped)
                Button("Step Into") { workspace?.debug?.stepInto() }
                    .keyboardShortcut(fn(NSF11FunctionKey), modifiers: [])
                    .disabled(workspace?.debug?.state != .stopped)
                Button("Step Out") { workspace?.debug?.stepOut() }
                    .keyboardShortcut(fn(NSF11FunctionKey), modifiers: .shift)
                    .disabled(workspace?.debug?.state != .stopped)
                Button("Pause") { workspace?.debug?.pause() }
                    .keyboardShortcut(fn(NSF6FunctionKey), modifiers: [])
                    .disabled(workspace?.debug?.state != .running)
                Divider()
                Button("Toggle Breakpoint") { workspace?.toggleBreakpointAtCaret() }
                    .keyboardShortcut("\\")
                Button("Remove All Breakpoints") { workspace?.removeAllBreakpoints() }
                Divider()
                Button("Show Problems") { workspace?.showPanel(.problems) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }

            CommandMenu("Source Control") {
                Button("Show Source Control") {
                    guard let workspace else { return }
                    withAnimation(Motion.snappy) {
                        workspace.sidebarMode = .git
                        if workspace.columnVisibility == .detailOnly { workspace.columnVisibility = .all }
                    }
                }
                .keyboardShortcut("g", modifiers: [.control, .shift])
                Button("Commit…") {
                    guard let workspace else { return }
                    withAnimation(Motion.snappy) { workspace.sidebarMode = .git; workspace.columnVisibility = .all }
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                Button("Push") { workspace?.scm.push() }.disabled(workspace?.scm.hasRemote != true)
                Button("Pull") { workspace?.scm.pull() }.disabled(workspace?.scm.hasRemote != true)
                Divider()
                Button("Clone Repository…") { workspace?.cloneRepository() }
                Button("Publish to GitHub…") { workspace?.publishToGitHub() }
                Button("Create Pull Request") { workspace?.createPullRequest(onWeb: false) }
                Button("Sign in to GitHub") { workspace?.githubSignIn() }
            }

        }

        CommandMenu("Go") {
            Button("Quick Open…") { workspace?.showPalette(.files) }
                .keyboardShortcut("p")
            Button("Command Palette…") { workspace?.showPalette(.commands) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Go to Line…") { workspace?.showPalette(.line) }
                .keyboardShortcut("g", modifiers: .control)
            Button("Search in Project") { workspace?.focusSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("Next Tab") { workspace?.activateTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { workspace?.activateTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }

        CommandGroup(before: .sidebar) {
            Button("Toggle Panel") { workspace?.toggleTerminal() }
                .keyboardShortcut("`", modifiers: .control)
            Button("Focus Mode") { workspace?.toggleAscend() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button(Preferences.shared.fillEnabled ? "Turn Off Halo Fill" : "Turn On Halo Fill") { Preferences.shared.fillEnabled.toggle() }
            Button(Preferences.shared.wordWrap ? "Disable Word Wrap" : "Enable Word Wrap") { Preferences.shared.wordWrap.toggle() }
                .keyboardShortcut("w", modifiers: [.command, .option])
            Divider()
            Button("Increase Font Size") { Preferences.shared.adjustFontSize(1) }
                .keyboardShortcut("=")
            Button("Decrease Font Size") { Preferences.shared.adjustFontSize(-1) }
                .keyboardShortcut("-")
            Button("Reset Font Size") { Preferences.shared.fontSize = 13.5 }
                .keyboardShortcut("0")
            Divider()
        }

        SidebarCommands()

        CommandGroup(replacing: .help) {
            Button("Setup Guide") { workspace?.showSetup = true }
        }
    }
}

struct PreferencesView: View {
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            CompletionSettings()
                .tabItem { Label("Completion", systemImage: "text.append") }
                .tag("completion")
            ClaudeSettings()
                .frame(height: 640)
                .tabItem { Label("Claude", systemImage: "cable.connector") }
                .tag("claude")
        }
        .frame(width: 560)
    }
}

private struct GeneralSettings: View {
    @State private var prefs = Preferences.shared

    var body: some View {
        Form {
            Picker("Appearance", selection: $prefs.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Font size") {
                HStack {
                    Slider(value: Binding(get: { Double(prefs.fontSize) }, set: { prefs.fontSize = CGFloat($0.rounded(toPlaces: 1)) }), in: 10...24, step: 0.5)
                    Text(String(format: "%.1f pt", prefs.fontSize)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
            LabeledContent("Line spacing") {
                HStack {
                    Slider(value: Binding(get: { Double(prefs.lineSpacing) }, set: { prefs.lineSpacing = CGFloat($0.rounded(toPlaces: 2)) }), in: 1.2...2.0, step: 0.05)
                    Text(String(format: "%.2f×", prefs.lineSpacing)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
            Toggle("Wrap long lines", isOn: $prefs.wordWrap)
            Section {
                Button("Show Setup Guide…") {
                    WorkspaceRegistry.focused?.showSetup = true
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 236)
    }
}

private struct CompletionSettings: View {
    @State private var prefs = Preferences.shared

    var body: some View {
        Form {
            Toggle("Suggest code as you type (Tab to accept)", isOn: $prefs.fillEnabled)
            Section("Smart Fill") {
                Toggle("Use a local AI model", isOn: Binding(get: { SmartFill.shared.enabled }, set: { SmartFill.shared.enabled = $0 }))
                SmartFillControls()
                    .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(height: 336)
    }
}
