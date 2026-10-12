import AppKit
import Observation

@Observable @MainActor
final class Document: Identifiable {
    enum Kind { case text, image, binary, tooLarge }

    let id = UUID()
    private(set) var url: URL?
    private(set) var kind: Kind
    private(set) var language: Language
    var isDirty = false
    var cursorLine = 1
    var cursorColumn = 1
    var selectionLength = 0
    private(set) var usesCRLF = false
    private(set) var encoding: String.Encoding = .utf8
    private(set) var modificationDate: Date?
    var image: NSImage?

    @ObservationIgnored private var _editor: EditorController?
    /// Called when the caret moves to another line.
    @ObservationIgnored var onLineChange: ((Int) -> Void)?
    @ObservationIgnored private var initialText = ""

    var name: String { url?.lastPathComponent ?? "Untitled" }
    var indentUnit: Int { _editor?.textView.indentUnit ?? language.indentUnit }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "ico", "icns", "pdf"]
    static let maxTextBytes = 24 * 1024 * 1024

    init(untitled: Void = ()) {
        kind = .text
        language = .plain
    }

    init(url: URL) {
        self.url = url
        language = Language.detect(url: url)
        kind = .text
        load()
    }

    var editor: EditorController? {
        guard kind == .text else { return nil }
        if let _editor { return _editor }
        let controller = EditorController(text: initialText, language: language, settings: Preferences.shared)
        controller.onTextChange = { [weak self] in
            guard let self, !self.isDirty else { return }
            DispatchQueue.main.async { self.isDirty = true }
        }
        controller.onSelectionChange = { [weak self] line, column, selected in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.cursorLine != line {
                    self.cursorLine = line
                    self.onLineChange?(line)
                }
                if self.cursorColumn != column { self.cursorColumn = column }
                if self.selectionLength != selected { self.selectionLength = selected }
            }
        }
        initialText = ""
        _editor = controller
        return controller
    }

    private func load() {
        guard let url else { return }
        modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            kind = .image
            image = NSImage(contentsOf: url)
            return
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size > Self.maxTextBytes { kind = .tooLarge; return }
        guard let data = try? Data(contentsOf: url) else { kind = .binary; return }
        if data.prefix(8000).contains(0) { kind = .binary; return }
        var text: String
        if let s = String(data: data, encoding: .utf8) {
            text = s; encoding = .utf8
        } else if let s = String(data: data, encoding: .windowsCP1252) {
            text = s; encoding = .windowsCP1252
        } else {
            kind = .binary; return
        }
        if text.contains("\r\n") {
            usesCRLF = true
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
        }
        initialText = text
    }

    /// Reload from disk if the file changed underneath us and we have no edits.
    func reloadIfChangedOnDisk() {
        guard let url, !isDirty, kind == .text else { return }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let date, date != modificationDate else { return }
        guard let data = try? Data(contentsOf: url), var text = String(data: data, encoding: encoding) else { return }
        modificationDate = date
        if usesCRLF { text = text.replacingOccurrences(of: "\r\n", with: "\n") }
        if let _editor {
            guard _editor.text != text else { return }
            _editor.setText(text)
        } else {
            initialText = text
        }
        isDirty = false
    }

    func save(to newURL: URL? = nil) throws {
        guard kind == .text, let target = newURL ?? url else { return }
        let lfText = _editor?.text ?? initialText
        let text = usesCRLF ? lfText.replacingOccurrences(of: "\n", with: "\r\n") : lfText
        guard let data = text.data(using: encoding) ?? text.data(using: .utf8) else { return }
        try data.write(to: target, options: .atomic)
        if newURL != nil, newURL != url {
            url = target
            let detected = Language.detect(url: target)
            if detected != language { language = detected; _editor = nil; initialText = lfText }
        }
        modificationDate = (try? target.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        isDirty = false
    }
}
