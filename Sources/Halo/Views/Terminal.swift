import AppKit
import SwiftUI
import SwiftTerm

/// One persistent shell per window. The view outlives panel toggles so the
/// session (history, running servers) survives hiding the terminal.
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    private weak var workspace: Workspace?
    private(set) var view: HaloTerminalView
    private(set) var isStarted = false
    weak var container: NSView?

    init(workspace: Workspace) {
        self.workspace = workspace
        view = HaloTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
        super.init()
        configure(view)
    }

    private func configure(_ view: HaloTerminalView) {
        view.processDelegate = self
        view.onAppearanceChange = { [weak self, weak view] in
            guard let view else { return }
            self?.applyTheme(to: view)
        }
        view.optionAsMetaKey = false
        applyTheme(to: view)
    }

    static var loginShell: String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell { return String(cString: shell) }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// Returns true if a fresh shell was just launched.
    @discardableResult
    func startIfNeeded(in directory: URL?) -> Bool {
        guard !isStarted else { return false }
        isStarted = true
        let shell = Self.loginShell
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        env.append("TERM_PROGRAM=Halo")
        env.append("TERM_PROGRAM_VERSION=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
        if let path = ProcessInfo.processInfo.environment["PATH"] { env.append("PATH=\(path)") }
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] { env.append("TMPDIR=\(tmp)") }
        env.append("SHELL=\(shell)")
        let execName = "-" + (shell as NSString).lastPathComponent   // login shell: loads your profile
        view.startProcess(executable: shell, args: [], environment: env, execName: execName,
                          currentDirectory: directory?.path ?? NSHomeDirectory())
        return true
    }

    /// Ctrl-C to whatever is running.
    func interrupt() { view.send(txt: "\u{03}") }

    func changeDirectory(to url: URL) {
        let escaped = url.path.replacingOccurrences(of: "'", with: "'\\''")
        view.send(txt: "cd '\(escaped)'\r")
    }

    func run(_ command: String) {
        view.send(txt: command + "\r")
    }

    func focus() { view.window?.makeFirstResponder(view) }

    func applyTheme(to view: HaloTerminalView) {
        let dark = view.effectiveAppearance.isDark
        let palette: [UInt32] = dark
            ? [0x1A2029, 0xF07A8A, 0xA9D98B, 0xF2C47A, 0x8DB8F5, 0xD3A6F2, 0x7FD4D9, 0xDCE1E8,
               0x4A5466, 0xFF95A3, 0xBFE8A6, 0xF8D693, 0xA9CCFA, 0xE2BFFA, 0x9DE6EA, 0xFFFFFF]
            : [0x2B2F36, 0xC03A4B, 0x4A7F2C, 0xA65F14, 0x2F62B0, 0x8E4FA8, 0x24707F, 0xB9BEC6,
               0x6B717A, 0xD9485F, 0x5E9A3A, 0xC27A12, 0x3F7BD9, 0xA868C4, 0x2E8C9E, 0x8C919A]
        view.installColors(palette.map { hex in
            SwiftTerm.Color(red: UInt16((hex >> 16) & 0xFF) * 257, green: UInt16((hex >> 8) & 0xFF) * 257, blue: UInt16(hex & 0xFF) * 257)
        })
        view.nativeBackgroundColor = NSColor(hex: dark ? 0x0B0E14 : 0xF5F3EE)
        view.nativeForegroundColor = NSColor(hex: dark ? 0xDCE1E8 : 0x2B2F36)
        view.caretColor = NSColor(hex: dark ? 0xE8C77A : 0x2F6FCF)
        view.selectedTextBackgroundColor = NSColor(hex: dark ? 0x27384F : 0xCFE2F8)
        view.font = EditorFont.regular(max(11, Preferences.shared.fontSize - 1))
    }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Fresh shell next time the panel opens.
            self.isStarted = false
            let old = self.view
            let fresh = HaloTerminalView(frame: old.frame)
            self.configure(fresh)
            self.view = fresh
            if let container = self.container {
                old.removeFromSuperview()
                fresh.frame = container.bounds
                fresh.autoresizingMask = [.width, .height]
                container.addSubview(fresh)
            }
            withAnimation(Motion.snappy) { self.workspace?.showTerminal = false }
            self.workspace?.active?.editor?.focus()
        }
    }
}

final class HaloTerminalView: LocalProcessTerminalView {
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        session.container = container
        let view = session.view
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if session.view.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            session.view.frame = container.bounds
            session.view.autoresizingMask = [.width, .height]
            container.addSubview(session.view)
            session.container = container
        }
    }
}
