import AppKit

extension NSAttributedString.Key {
    /// The token kind a run was highlighted as — lets editing behaviors ask
    /// "am I inside a string or comment?" without re-tokenizing.
    static let haloToken = NSAttributedString.Key("HaloToken")
}

/// Regex-driven highlighter. Whole-document passes run off the main thread
/// and are applied only if the text hasn't changed since; single-line passes
/// run synchronously while typing so keywords light up instantly.
final class SyntaxHighlighter {
    struct Token { let range: NSRange; let kind: TokenKind }

    let language: Language
    private let regex: NSRegularExpression?
    private let kinds: [TokenKind]
    private let queue = DispatchQueue(label: "halo.highlight", qos: .userInitiated)
    private var generation = 0

    var fontSize: CGFloat = 13 { didSet { buildFonts() } }
    private var regular = EditorFont.regular(13)
    private var italic = EditorFont.italic(13)
    private var semibold = EditorFont.semibold(13)

    static let maxLength = 3_000_000

    init(language: Language) {
        self.language = language
        kinds = language.grammar.rules.map(\.0)
        let pattern = language.grammar.rules.map { "(" + $0.1 + ")" }.joined(separator: "|")
        regex = pattern.isEmpty ? nil : try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        if regex == nil && !pattern.isEmpty { NSLog("Halo: grammar for \(language.id) failed to compile") }
    }

    private func buildFonts() {
        regular = EditorFont.regular(fontSize)
        italic = EditorFont.italic(fontSize)
        semibold = EditorFont.semibold(fontSize)
    }

    func tokenize(_ string: String, in range: NSRange) -> [Token] {
        guard let regex else { return [] }
        var out: [Token] = []
        out.reserveCapacity(range.length / 6)
        let groupCount = kinds.count
        regex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            for i in 1...groupCount {
                let r = match.range(at: i)
                if r.location != NSNotFound {
                    if r.length > 0 { out.append(Token(range: r, kind: kinds[i - 1])) }
                    return
                }
            }
        }
        return out
    }

    func attributes(for kind: TokenKind?) -> [NSAttributedString.Key: Any] {
        guard let kind else { return [.foregroundColor: Palette.text, .font: regular] }
        let color: NSColor
        var font = regular
        switch kind {
        case .comment: color = SyntaxPalette.comment; font = italic
        case .string: color = SyntaxPalette.string
        case .attribute: color = SyntaxPalette.attribute
        case .number, .constant: color = SyntaxPalette.number
        case .keyword: color = SyntaxPalette.keyword; font = language.id == "markdown" ? semibold : regular
        case .type: color = SyntaxPalette.type
        case .function: color = SyntaxPalette.function
        case .property: color = SyntaxPalette.property
        case .heading: color = SyntaxPalette.heading; font = semibold
        case .punctuation: color = SyntaxPalette.punctuation
        }
        return [.foregroundColor: color, .font: font, .haloToken: kind.rawValue]
    }

    private func apply(_ tokens: [Token], to storage: NSTextStorage, range: NSRange) {
        guard NSMaxRange(range) <= storage.length else { return }
        storage.beginEditing()
        storage.removeAttribute(.haloToken, range: range)
        storage.addAttributes(attributes(for: nil), range: range)
        for t in tokens where NSMaxRange(t.range) <= storage.length {
            storage.addAttributes(attributes(for: t.kind), range: t.range)
        }
        storage.endEditing()
    }

    /// Re-highlights only the lines touched by an edit. Skipped while the
    /// caret sits inside a string/comment, since those can span lines —
    /// the async full pass settles them a moment later.
    func highlightLines(around editedRange: NSRange, in storage: NSTextStorage) {
        guard regex != nil, storage.length < Self.maxLength else { return }
        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: min(editedRange.location, ns.length), length: min(editedRange.length, ns.length - min(editedRange.location, ns.length))))
        if lineRange.location > 0,
           let kind = storage.attribute(.haloToken, at: lineRange.location - 1, effectiveRange: nil) as? String,
           kind == TokenKind.comment.rawValue || kind == TokenKind.string.rawValue {
            return
        }
        let tokens = tokenize(storage.string, in: lineRange)
        apply(tokens, to: storage, range: lineRange)
    }

    /// Full-document pass on a background queue.
    func highlightAll(_ storage: NSTextStorage, completion: (() -> Void)? = nil) {
        generation += 1
        let gen = generation
        guard regex != nil else {
            apply([], to: storage, range: NSRange(location: 0, length: storage.length))
            completion?()
            return
        }
        guard storage.length < Self.maxLength else { completion?(); return }
        let snapshot = storage.string
        let length = storage.length
        queue.async { [weak self] in
            guard let self else { return }
            let tokens = self.tokenize(snapshot, in: NSRange(location: 0, length: length))
            DispatchQueue.main.async { [weak self, weak storage] in
                guard let self, let storage, gen == self.generation, storage.length == length else { return }
                self.apply(tokens, to: storage, range: NSRange(location: 0, length: length))
                completion?()
            }
        }
    }

    func cancelPending() { generation += 1 }
}
