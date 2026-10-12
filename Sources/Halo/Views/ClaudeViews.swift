import SwiftUI

/// Settings → Claude: let Claude use Halo over MCP.
struct ClaudeSettings: View {
    @Bindable private var server = MCPServer.shared
    private let connections = ClaudeConnections.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $server.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow Claude to connect")
                        Text("Claude can see what you’re working on in Halo, edit files and run code. Everything stays on this Mac; Halo talks to Claude through MCP.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.haloSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ClaudeStatusLine()
            }

            Section("Claude may") {
                LabeledContent("Read the project and the editor") {
                    Text("Always").foregroundStyle(Color.haloSecondary)
                }
                Toggle(isOn: $server.allowEdits) {
                    SettingLabel("Edit files", detail: "Changes show up in the editor and ⌘Z undoes them.")
                }
                Toggle(isOn: $server.allowRun) {
                    SettingLabel("Run code and commands", detail: "Runs in your project folder with your permissions, so Claude can test its work.")
                }
            }
            .disabled(!server.enabled)

            Section("Connect") {
                ClaudeConnectRows()
                HStack(spacing: 12) {
                    SettingLabel("Other MCP apps", detail: "Paste this into the app’s MCP server settings.")
                    Spacer(minLength: 8)
                    Button("Copy Setup") { connections.copyConfig() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }

            Section {
                if server.activity.isEmpty {
                    Text("Nothing yet. Once you’re connected, try asking Claude “What am I working on in Halo?”")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.haloSecondary)
                } else {
                    ForEach(server.activity.prefix(12)) { ActivityRow(item: $0) }
                }
            } header: {
                HStack {
                    Text("Activity")
                    Spacer()
                    if !server.activity.isEmpty {
                        Button("Clear") { server.clearActivity() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.haloSecondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { connections.refresh() }
    }
}

private struct SettingLabel: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.haloSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A dot and a sentence: off, ready, connected, or what went wrong.
struct ClaudeStatusLine: View {
    private let server = MCPServer.shared

    private var color: Color {
        if !server.enabled { return Color.haloTertiary }
        if server.problem != nil { return Color(nsColor: Palette.warning) }
        return server.clients.isEmpty ? Color.haloSky : Color.haloAdded
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(server.statusText)
                .font(.system(size: 12))
                .foregroundStyle(server.problem == nil ? Color.haloSecondary : Color(nsColor: Palette.warning))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Claude Desktop and Claude Code, each with its connect button.
struct ClaudeConnectRows: View {
    var carded = false
    private let connections = ClaudeConnections.shared

    var body: some View {
        VStack(alignment: .leading, spacing: carded ? 10 : 12) {
            if let problem = connections.locationProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: Palette.warning))
                    .fixedSize(horizontal: false, vertical: true)
            }
            card { desktopRow }
            if !carded { Divider() }
            card { codeRow }
            if let message = connections.message {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(nsColor: Palette.warning))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(connections.busy || connections.locationProblem != nil)
        .onAppear { connections.refresh() }
    }

    @ViewBuilder private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if carded {
            content()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.haloHairline))
        } else {
            content()
        }
    }

    private var desktopRow: some View {
        AppRow(icon: connections.desktopIcon, title: "Claude Desktop", connected: connections.desktop == .connected,
               detail: desktopDetail) {
            switch connections.desktop {
            case .checking:
                ProgressView().controlSize(.small)
            case .notInstalled:
                Link("Get Claude", destination: URL(string: "https://claude.ai/download")!)
                    .font(.system(size: 12))
            case .notConnected, .otherCopy:
                Button(connections.desktop == .otherCopy ? "Reconnect" : "Connect") { connections.connectDesktop() }
                    .buttonStyle(.glassProminent)
                    .tint(Color.haloAction)
                    .controlSize(.small)
            case .connected:
                if connections.desktopNeedsRestart {
                    Button("Restart Claude") { connections.restartDesktop() }
                        .buttonStyle(.glassProminent)
                        .tint(Color.haloAction)
                        .controlSize(.small)
                }
                Button("Disconnect") { connections.disconnectDesktop() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
    }

    private var desktopDetail: String {
        switch connections.desktop {
        case .checking: "Checking…"
        case .notInstalled: "Not installed on this Mac."
        case .notConnected: "Adds Halo to Claude’s MCP servers."
        case .otherCopy: "Set up for another copy of Halo. Reconnect to use this one."
        case .connected: connections.desktopNeedsRestart ? "Restart Claude to finish connecting." : "Claude can use Halo in any chat."
        }
    }

    private var codeRow: some View {
        AppRow(icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app"), title: "Claude Code",
               connected: connections.code == .connected, detail: codeDetail) {
            switch connections.code {
            case .checking:
                ProgressView().controlSize(.small)
            case .notInstalled:
                Button("Copy Command") { connections.copyCodeCommand() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help(connections.codeCommand)
            case .notConnected, .otherCopy:
                Button(connections.code == .otherCopy ? "Reconnect" : "Connect") { connections.connectCode() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            case .connected:
                Button("Disconnect") { connections.disconnectCode() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
    }

    private var codeDetail: String {
        switch connections.code {
        case .checking: "Checking…"
        case .notInstalled: "The claude command isn’t installed. Copy the command to run it once Claude Code is set up."
        case .notConnected: "Adds Halo to every Claude Code session."
        case .otherCopy: "Set up for another copy of Halo. Reconnect to use this one."
        case .connected: "Available in every Claude Code session."
        }
    }
}

private struct AppRow<Actions: View>: View {
    let icon: NSImage?
    let title: String
    let connected: Bool
    let detail: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06))
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.haloText)
                    if connected {
                        Text("Connected").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.haloAdded)
                    }
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.haloSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { actions }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ActivityRow: View {
    let item: MCPServer.Activity

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(item.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color.haloTertiary)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(item.failed ? Color(nsColor: Palette.warning) : Color.haloText)
                    .lineLimit(2)
                Text("\(item.client) · \(item.tool)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.haloTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Opens Settings at a tab from anywhere (the window captures SwiftUI's action).
@MainActor
enum SettingsOpener {
    static var action: OpenSettingsAction?

    static func open(tab: String? = nil) {
        if let tab { UserDefaults.standard.set(tab, forKey: "settingsTab") }
        NSApp.activate()
        action?()
    }
}

/// Status bar: shows when Claude is connected, and when it's doing something.
struct ClaudeBadge: View {
    private let server = MCPServer.shared

    var body: some View {
        if server.enabled, !server.clients.isEmpty {
            Button { SettingsOpener.open(tab: "claude") } label: {
                Label(server.working > 0 ? "Claude working" : "Claude", systemImage: "cable.connector")
                    .foregroundStyle(server.working > 0 ? Color.haloAction : Color.haloTertiary)
                    .contentTransition(.opacity)
                    .animation(Motion.snappy, value: server.working > 0)
            }
            .buttonStyle(.plain)
            .help(server.statusText + " — click for Claude settings")
        }
    }
}
