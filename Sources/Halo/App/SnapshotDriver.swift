import AppKit
import SwiftUI

/// Development aid: when HALO_SNAPSHOT_DIR is set, runs the steps in
/// HALO_SNAPSHOT_STEPS (comma-separated) against the front window and writes
/// PNGs of the window into that directory. Inert in normal use.
///
/// Steps: wait:<sec> · shot:<name> · type:<text> · tab · enter · end
/// · eol:<text> · altenter · fixall · undo · dump:<name> · ready · settings:<tab> · setup:<step> · panel-height:<pt> · run · debug
/// · continue · step · panel:<terminal|problems|output|debugConsole>
/// · mode:<files|search|git|debug> · bp:<line> · palette · close-palette
/// · light · dark · quit
@MainActor
enum SnapshotDriver {
    static func startIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["HALO_SNAPSHOT_DIR"] else { return }
        let steps = (env["HALO_SNAPSHOT_STEPS"] ?? "wait:3,shot:window").split(separator: ",").map(String.init)
        run(steps[...], dir: URL(fileURLWithPath: dir))
    }

    private static var workspace: Workspace? { WorkspaceRegistry.focused ?? WorkspaceRegistry.all.first }
    private static var textView: HaloTextView? { workspace?.active?.editor?.textView }

    private static func run(_ steps: ArraySlice<String>, dir: URL) {
        guard let step = steps.first else { return }
        let rest = steps.dropFirst()
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        var delay = 0.35
        switch parts[0] {
        case "wait": delay = Double(arg) ?? 1
        case "shot": shoot(name: arg, dir: dir)
        case "type":
            if let tv = textView {
                tv.window?.makeFirstResponder(tv)
                for ch in arg.replacingOccurrences(of: "\\n", with: "\n") {
                    if ch == "\n" { tv.insertNewline(nil) } else { tv.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0)) }
                }
            }
            delay = 0.8
        case "tab": textView?.insertTab(nil)
        case "altenter": textView?.insertNewlineIgnoringFieldEditor(nil)
        case "fixall": textView?.applyAllSuggestedFixes(nil)
        case "undo": textView?.undoManager?.undo()   // what ⌘Z does via the window
        case "probe":
            let um = textView?.undoManager
            let info = "chars=\((textView?.string as NSString?)?.length ?? -1) canUndo=\(um?.canUndo ?? false) action=\(um?.undoActionName ?? "-") redo=\(um?.redoActionName ?? "-") level=\(um?.groupingLevel ?? -1) text=\((textView?.string ?? "").replacingOccurrences(of: "\n", with: "⏎")) levels=\(um?.levelsOfUndo ?? -1) groupsByEvent=\(um?.groupsByEvent ?? false) responds=\(textView?.responds(to: Selector(("undo:"))) ?? false) ghost=\(textView?.ghostRange.map { NSStringFromRange($0) } ?? "none")\n"
            let url = dir.appendingPathComponent("probe.txt")
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data((arg + ": " + info).utf8)); try? handle.close() }
            else { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); try? (arg + ": " + info).write(to: url, atomically: true, encoding: .utf8) }
        case "enter": textView?.insertNewline(nil)
        case "end": textView?.moveToEndOfDocument(nil)
        case "eol":
            // Caret to the end of the first line containing the text.
            if let tv = textView, let match = tv.string.range(of: arg) {
                let ns = tv.string as NSString
                let line = ns.lineRange(for: NSRange(location: NSRange(match, in: tv.string).location, length: 0))
                var end = NSMaxRange(line)
                if end > line.location, ns.character(at: end - 1) == 10 { end -= 1 }
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: end, length: 0))
            }
        case "ready":
            // Hold the remaining steps until the Smart Fill model has loaded.
            if !SmartFill.shared.isReady {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { run(steps, dir: dir) }
                return
            }
        case "claude-desktop":
            if arg == "disconnect" { ClaudeConnections.shared.disconnectDesktop() } else { ClaudeConnections.shared.connectDesktop() }
        case "windows":
            let list = NSApp.windows.map { "\($0.title.isEmpty ? "-" : $0.title) visible=\($0.isVisible) key=\($0.isKeyWindow) \(type(of: $0)) \(Int($0.frame.width))x\(Int($0.frame.height)) id=\($0.identifier?.rawValue ?? "")" }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? (list.joined(separator: "\n") + "\nopener=\(SettingsOpener.action != nil)").write(to: dir.appendingPathComponent("windows.txt"), atomically: true, encoding: .utf8)
        case "dump":
            textView?.removeGhost()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? textView?.string.write(to: dir.appendingPathComponent(arg + ".txt"), atomically: true, encoding: .utf8)
        case "run": workspace?.runActive(); delay = 3
        case "panel-height": if let h = Double(arg) { workspace?.terminalHeight = h }
        case "debug": workspace?.startDebugging(); delay = 4
        case "continue": workspace?.debug?.resume(); delay = 1.5
        case "step": workspace?.debug?.stepOver(); delay = 1.2
        case "panel": if let tab = PanelTab(rawValue: arg) { workspace?.showPanel(tab) }
        case "mode": if let mode = SidebarMode(rawValue: arg) { workspace?.sidebarMode = mode }
        case "bp":
            if let ws = workspace, let url = ws.active?.url, let line = Int(arg) {
                ws.toggleBreakpoint(path: url.standardizedFileURL.path, line: line)
            }
        case "settings":
            // settings:<general|completion|claude>
            SettingsOpener.open(tab: arg.isEmpty ? nil : arg)
            delay = 1
        case "setup":
            SetupGuide.startStep = Int(arg) ?? 0
            workspace?.showSetup = true
            delay = 1
        case "palette": workspace?.showPalette(.files)
        case "commands": workspace?.showPalette(.commands)
        case "close-palette": workspace?.dismissPalette()
        case "light": Preferences.shared.appearance = .daybreak; delay = 0.8
        case "dark": Preferences.shared.appearance = .nightfall; delay = 0.8
        case "quit": NSApp.terminate(nil)
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { run(rest, dir: dir) }
    }

    private static func shoot(name: String, dir: URL) {
        // Shots named settings-… are of the Settings window.
        let settings = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.contains("Settings") == true }
        guard let window = (name.hasPrefix("settings") ? settings : nil)
                ?? NSApp.orderedWindows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) && $0 !== settings }),
              let view = (window.attachedSheet ?? window).contentView?.superview ?? (window.attachedSheet ?? window).contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name + ".png"))
    }
}
