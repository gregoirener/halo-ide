import AppKit
import SwiftUI

/// File and folder icons from Catppuccin Icons (MIT — see Icons/LICENSE).
/// Latte is used in Daybreak, Mocha in Nightfall. SVGs are rendered by
/// macOS itself, so they stay crisp at any size.
@MainActor
enum IconTheme {
    private struct Map: Decodable {
        let fileExtensions: [String: String]
        let fileNames: [String: String]
        let folderNames: [String: String]
    }

    private static let directory: URL? = {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Icons"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        // `swift run` during development: fall back to the source tree.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Icons")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }()

    private static let map: Map? = {
        guard let url = directory?.appendingPathComponent("map.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Map.self, from: data)
    }()

    /// A few names the upstream map leaves generic.
    private static let extraFileNames: [String: String] = ["package.swift": "swift", "package.resolved": "lock"]
    private static let extraExtensions: [String: String] = ["lock": "lock", "resolved": "lock", "icns": "image"]
    private static let extraFolders: [String: String] = ["resources": "assets", ".build": "dist", ".swiftpm": "config"]

    private static var cache: [String: NSImage] = [:]

    static func iconName(for url: URL, isDirectory: Bool, expanded: Bool = false) -> String {
        let name = url.lastPathComponent.lowercased()
        if isDirectory {
            if let icon = extraFolders[name] ?? map?.folderNames[name] {
                return "folder_\(icon)" + (expanded ? "_open" : "")
            }
            return expanded ? "_folder_open" : "_folder"
        }
        if let icon = extraFileNames[name] ?? map?.fileNames[name] { return icon }
        // Longest compound extension first: "d.ts", "test.tsx", then "tsx".
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 1 {
            for i in 1..<parts.count {
                let ext = parts[i...].joined(separator: ".")
                if let icon = map?.fileExtensions[ext] ?? extraExtensions[ext] { return icon }
            }
        }
        return "_file"
    }

    static func image(named name: String, dark: Bool) -> NSImage? {
        let flavor = dark ? "mocha" : "latte"
        let key = flavor + "/" + name
        if let cached = cache[key] { return cached }
        guard let dir = directory else { return nil }
        var url = dir.appendingPathComponent(flavor).appendingPathComponent(name + ".svg")
        if !FileManager.default.fileExists(atPath: url.path) {
            // An "_open" variant might not exist for every folder.
            let fallback = name.hasSuffix("_open") ? String(name.dropLast(5)) : (name.hasPrefix("folder_") ? "_folder" : "_file")
            url = dir.appendingPathComponent(flavor).appendingPathComponent(fallback + ".svg")
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        cache[key] = image
        return image
    }
}

/// The icon for a file or folder, in the current light.
struct FileIconView: View {
    let url: URL?
    var isDirectory = false
    var expanded = false
    var size: CGFloat = 16
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let name = url.map { IconTheme.iconName(for: $0, isDirectory: isDirectory, expanded: expanded) } ?? "_file"
        Group {
            if let image = IconTheme.image(named: name, dark: scheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: isDirectory ? "folder" : "doc")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color.haloTertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
