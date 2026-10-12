import SwiftUI

struct WelcomeView: View {
    @Bindable var workspace: Workspace

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Start
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("Halo")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.haloText)
                    .padding(.top, 14)
                Text("Version \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.haloTertiary)
                    .padding(.top, 2)

                VStack(spacing: 4) {
                    WelcomeAction(symbol: "folder", title: "Open Folder…", detail: "Work on an existing project", keys: "⇧⌘O") {
                        workspace.chooseFolder()
                    }
                    WelcomeAction(symbol: "doc.badge.plus", title: "New File", detail: "Start writing right away", keys: "⌘N") {
                        workspace.newFile()
                    }
                    WelcomeAction(symbol: "arrow.down.circle", title: "Clone Repository…", detail: "From GitHub or any Git URL", keys: nil) {
                        workspace.cloneRepository()
                    }
                }
                .padding(.top, 32)

                Spacer(minLength: 24)

                Button("Setup Guide") { workspace.showSetup = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.haloSecondary)
            }
            .padding(36)
            .frame(width: 400, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.haloChrome)

            Rectangle().fill(Color.haloHairline).frame(width: 1)

            // Recent
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Projects")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.haloSecondary)
                    .padding(.horizontal, 12)
                if Preferences.shared.recentFolders.isEmpty {
                    Text("Projects you open will show up here. You can also drop a folder anywhere in this window.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.haloTertiary)
                        .padding(.horizontal, 12)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Preferences.shared.recentFolders, id: \.self) { url in
                                RecentRow(url: url) { workspace.openFolder(url) }
                                    .contextMenu {
                                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                        Button("Remove from Recent") { Preferences.shared.forgetRecent(url) }
                                    }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 36)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.haloEditor)
        }
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
}

private struct WelcomeAction: View {
    let symbol: String
    let title: String
    let detail: String
    let keys: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.haloSky)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.haloSky.opacity(0.1)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Color.haloText)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Color.haloSecondary)
                }
                Spacer(minLength: 8)
                if let keys { Kbd(keys) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct RecentRow: View {
    let url: URL
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FileIconView(url: url, isDirectory: true, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.haloText)
                    Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.haloTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
