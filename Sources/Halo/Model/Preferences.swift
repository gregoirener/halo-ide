import AppKit
import Observation

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, daybreak, nightfall
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Follow System"
        case .daybreak: "Daybreak"
        case .nightfall: "Nightfall"
        }
    }
}

@Observable @MainActor
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    var fontSize: CGFloat { didSet { defaults.set(Double(fontSize), forKey: "fontSize"); notify() } }
    var lineSpacing: CGFloat { didSet { defaults.set(Double(lineSpacing), forKey: "lineSpacing"); notify() } }
    var wordWrap: Bool { didSet { defaults.set(wordWrap, forKey: "wordWrap"); notify() } }
    var fillEnabled: Bool { didSet { defaults.set(fillEnabled, forKey: "fillEnabled") } }
    var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: "hasCompletedSetup") } }
    private(set) var recentFolders: [URL]

    private init() {
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        let size = defaults.double(forKey: "fontSize")
        fontSize = size > 0 ? CGFloat(size) : 13.5
        let spacing = defaults.double(forKey: "lineSpacing")
        lineSpacing = spacing > 0 ? CGFloat(spacing) : 1.55
        wordWrap = defaults.object(forKey: "wordWrap") as? Bool ?? true
        hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        fillEnabled = defaults.object(forKey: "fillEnabled") as? Bool ?? true
        recentFolders = (defaults.stringArray(forKey: "recentFolders") ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .daybreak: NSApp.appearance = NSAppearance(named: .aqua)
        case .nightfall: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func noteRecent(_ url: URL) {
        recentFolders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentFolders.insert(url, at: 0)
        recentFolders = Array(recentFolders.prefix(8))
        defaults.set(recentFolders.map(\.path), forKey: "recentFolders")
    }

    func forgetRecent(_ url: URL) {
        recentFolders.removeAll { $0 == url }
        defaults.set(recentFolders.map(\.path), forKey: "recentFolders")
    }

    func adjustFontSize(_ delta: CGFloat) {
        fontSize = min(28, max(9, fontSize + delta))
    }

    private func notify() {
        NotificationCenter.default.post(name: .haloEditorSettingsChanged, object: nil)
    }
}
