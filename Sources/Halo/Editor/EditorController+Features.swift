import AppKit
import Observation

extension NSAttributedString.Key {
    static let haloGhost = NSAttributedString.Key("HaloGhost")
}

struct Diagnostic: Identifiable, Hashable {
    enum Severity: Int, Comparable {
        case error = 0, warning = 1, note = 2
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }
    let id = UUID()
    let path: String
    let line: Int          // 1-based
    let column: Int?       // 1-based
    let severity: Severity
    let message: String
    let source: String

    var color: NSColor {
        switch severity {
        case .error: Palette.error
        case .warning: Palette.warning
        case .note: Palette.secondaryText
        }
    }
}

struct LineChange: Hashable {
    enum Kind: Hashable { case added, modified, deleted }
    let kind: Kind
    let lines: ClosedRange<Int>    // 1-based; for `deleted`, the line the removal follows
}

/// How much of what you wrote came from Tab, this session.
@Observable @MainActor
final class FillStats {
    static let shared = FillStats()
    var typed = 0
    var filled = 0
    var percent: Int? {
        let total = typed + filled
        return total < 40 ? nil : Int((Double(filled) / Double(total) * 100).rounded())
    }
}

extension EditorController {
    // MARK: Ghost-aware line mapping (1 real line may sit below ghost lines)

    private var ghostSpan: (line: Int, count: Int)? {
        guard let ghost = textView.ghostRange else { return nil }
        let newlines = textView.ghostText.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
        guard newlines > 0 else { return nil }
        return (lineIndex(for: ghost.location), newlines)
    }

    /// Storage line index (0-based) for a real line index (0-based).
    func storageLine(forReal real: Int) -> Int {
        guard let span = ghostSpan, real > span.line else { return real }
        return real + span.count
    }

    /// Real line index (0-based) for a storage line index, or nil for ghost lines.
    func realLine(forStorage index: Int) -> Int? {
        guard let span = ghostSpan, index > span.line else { return index }
        if index <= span.line + span.count { return nil }
        return index - span.count
    }

    var realLineCount: Int { lineStarts.count - (ghostSpan?.count ?? 0) }

    /// The full-width rect of a real line (1-based), in text view coordinates.
    func lineRect(forLine line: Int) -> NSRect? {
        guard line >= 1 else { return nil }
        let index = storageLine(forReal: line - 1)
        guard index < lineStarts.count else { return nil }
        let start = lineStarts[index]
        var rect: NSRect
        if start >= storage.length {
            rect = layoutManager.extraLineFragmentRect
            if rect.isEmpty { return nil }
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: start)
            rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        rect.origin.y += textView.textContainerOrigin.y
        rect.origin.x = 0
        rect.size.width = textView.bounds.width
        return rect
    }

    func lineEndX(forLine line: Int) -> CGFloat {
        let index = storageLine(forReal: line - 1)
        guard index < lineStarts.count else { return 0 }
        let start = lineStarts[index]
        let end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : storage.length
        guard end > start, end <= storage.length else { return textView.textContainerOrigin.x }
        let glyph = layoutManager.glyphIndexForCharacter(at: end - 1)
        let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        return used.maxX + textView.textContainerOrigin.x
    }

    // MARK: Drawing (called from the text view's background pass)

    func drawAnnotations(in dirty: NSRect) {
        if let line = executionLine, let rect = lineRect(forLine: line), rect.intersects(dirty) {
            Palette.executionLine.setFill()
            rect.fill()
        }
        // Fix hints come first on their line; a problem's message follows them.
        let hintWidths = drawFixHints(in: dirty)
        guard !diagnostics.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: max(10.5, fontSize - 2), weight: .regular)
        var seen = Set<Int>()
        for d in diagnostics.sorted(by: { $0.severity < $1.severity }) where !seen.contains(d.line) {
            seen.insert(d.line)
            guard let rect = lineRect(forLine: d.line), rect.intersects(dirty) else { continue }
            d.color.withAlphaComponent(0.06).setFill()
            rect.fill()
            // The message, quietly, after the end of the line.
            let x = lineEndX(forLine: d.line) + 28 + (hintWidths[d.line].map { $0 + 16 } ?? 0)
            let available = textView.bounds.width - x - 16
            guard available > 60 else { continue }
            let message = d.message.replacingOccurrences(of: "\n", with: " ")
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: d.color.withAlphaComponent(0.85)]
            let height = font.ascender - font.descender
            let box = NSRect(x: x, y: rect.minY + (lineHeight - height) / 2, width: available, height: height + 2)
            (message as NSString).draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
        }
    }

    func revealLine(_ line: Int) {
        guard let rect = lineRect(forLine: line) else { return }
        textView.scrollToVisible(rect.insetBy(dx: 0, dy: -lineHeight * 4))
    }

    // MARK: Diagnostics

    func setDiagnostics(_ list: [Diagnostic]) {
        diagnostics = list
        applyUnderlines()
    }

    /// Problems get a thick dotted underline in their color; fixable mistakes a fine one in the accent.
    func applyUnderlines() {
        let full = NSRange(location: 0, length: storage.length)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: full)
        let ns = storage.string as NSString
        for fix in codeFixes {
            let range = storageRange(forText: fix.anchor)
            guard range.length > 0, NSMaxRange(range) <= storage.length else { continue }
            layoutManager.addTemporaryAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                .underlineColor: Palette.sky,
            ], forCharacterRange: range)
        }
        for d in diagnostics where d.severity != .note {
            let index = storageLine(forReal: d.line - 1)
            guard index < lineStarts.count else { continue }
            let start = lineStarts[index]
            let end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : storage.length
            guard end >= start else { continue }
            var range: NSRange
            if let column = d.column, column >= 1 {
                let loc = min(start + column - 1, end)
                var stop = loc
                while stop < end, Tokenizer.isIdent(ns.character(at: stop)) { stop += 1 }
                if stop == loc { stop = min(loc + 1, end) }
                range = NSRange(location: loc, length: stop - loc)
            } else {
                var s = start
                while s < end, ns.character(at: s) == 32 || ns.character(at: s) == 9 { s += 1 }
                range = NSRange(location: s, length: end - s)
            }
            guard range.length > 0, NSMaxRange(range) <= storage.length else { continue }
            layoutManager.addTemporaryAttributes([
                .underlineStyle: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
                .underlineColor: d.color,
            ], forCharacterRange: range)
        }
        textView.needsDisplay = true
        ruler.needsDisplay = true
    }

    // MARK: Halo Fill

    var fillFamily: String {
        if let fileURL { return FillEngine.family(for: fileURL) }
        return language.id == "javascript" || language.id == "typescript" ? "js" : language.id
    }

    func requestFill(immediately: Bool = false) {
        fillWork?.cancel()
        guard Preferences.shared.fillEnabled, textView.ghostRange == nil else { return }
        let selection = textView.selectedRange()
        guard selection.length == 0, !textView.hasMarkedText() else { return }
        fillGeneration += 1
        let generation = fillGeneration
        smartToken += 1
        let token = smartToken
        let smart = SmartFill.shared.isReady
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.fillGeneration else { return }
            let caret = self.textView.selectedRange()
            guard caret.length == 0, self.textView.ghostRange == nil else { return }
            if smart, let context = self.smartContext(at: caret.location) {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    var shown: String?
                    // Show the first finished line at once, then let the ghost grow
                    // as the model writes — unless you've started typing.
                    let result = await SmartFill.shared.stream(prefix: context.prefix, line: context.line,
                                                               suffix: context.suffix, indent: context.indent) { [weak self] partial in
                        guard let self, let cleaned = SmartFillCleanup.clean(partial, context: context) else { return }
                        self.offerSmart(cleaned, shown: &shown, generation: generation, token: token, caret: caret, length: context.length)
                    }
                    guard let result else {
                        // The model errored or was cancelled: if still current, the pattern engine answers.
                        if shown == nil, self.stillValid(generation: generation, caret: caret, length: context.length) {
                            self.patternFill(generation: generation, caret: caret)
                        }
                        return
                    }
                    // An empty answer means the model sees nothing to add: show nothing.
                    if let cleaned = SmartFillCleanup.clean(result, context: context) {
                        self.offerSmart(cleaned, shown: &shown, generation: generation, token: token, caret: caret, length: context.length)
                    }
                }
            } else {
                self.patternFill(generation: generation, caret: caret)
            }
        }
        fillWork = work
        // The model is fast; still, let a burst of keystrokes settle first.
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0.0 : (smart ? 0.06 : 0.035)), execute: work)
    }

    /// Shows or grows a streamed suggestion, as long as nothing else happened.
    private func offerSmart(_ text: String, shown: inout String?, generation: Int, token: Int, caret: NSRange, length: Int) {
        guard token == smartToken, textView.selectedRange() == caret,
              textView.window?.firstResponder === textView else { return }
        let ghostLength = textView.ghostRange?.length ?? 0
        guard storage.length - ghostLength == length else { return }
        if let previous = shown {
            // Only extend our own, untouched ghost.
            guard textView.ghostRange != nil, textView.ghostText == previous, text != previous, text.hasPrefix(previous) else { return }
        } else {
            guard generation == fillGeneration, textView.ghostRange == nil else { return }
        }
        textView.showGhost(text)
        shown = text
    }

    private func stillValid(generation: Int, caret: NSRange, length: Int) -> Bool {
        generation == fillGeneration && storage.length == length && textView.selectedRange() == caret
            && textView.ghostRange == nil && textView.window?.firstResponder === textView
    }

    /// The pattern engine: instant, and the fallback when no model is loaded.
    private func patternFill(generation: Int, caret: NSRange) {
        let length = storage.length
        let request = FillEngine.Request(text: storage.string, caret: caret.location, family: fillFamily,
                                         fileURL: fileURL, indentUnit: textView.indentUnit)
        FillEngine.shared.suggest(request) { [weak self] suggestion in
            guard let self, let suggestion, self.stillValid(generation: generation, caret: caret, length: length) else { return }
            self.textView.showGhost(suggestion)
        }
    }

    struct SmartContext {
        let prefix: String      // text before the current line
        let line: String        // current line up to the caret
        let rest: String        // current line after the caret
        let suffix: String      // everything after the caret (bounded)
        let indent: Int
        let length: Int
    }

    private func smartContext(at caret: Int) -> SmartContext? {
        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let lineStart = lineRange.location
        var lineEnd = NSMaxRange(lineRange)
        if lineEnd > lineStart, lineEnd <= ns.length, ns.character(at: lineEnd - 1) == 10 { lineEnd -= 1 }
        let rest = ns.substring(with: NSRange(location: caret, length: max(0, lineEnd - caret)))
        // Only at the end of a line, or before closing punctuation.
        guard rest.trimmingCharacters(in: .whitespaces).allSatisfy({ ")]}>\"'`;,".contains($0) }) else { return nil }
        let line = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        var prefixStart = max(0, lineStart - 8000)
        if prefixStart > 0 {
            let nl = ns.range(of: "\n", options: [], range: NSRange(location: prefixStart, length: lineStart - prefixStart))
            if nl.location != NSNotFound { prefixStart = nl.location + 1 }
        }
        let prefix = ns.substring(with: NSRange(location: prefixStart, length: lineStart - prefixStart))
        let suffixEnd = min(ns.length, caret + 3000)
        let suffix = ns.substring(with: NSRange(location: caret, length: suffixEnd - caret))
        var indent = 0
        for ch in line { if ch == " " { indent += 1 } else if ch == "\t" { indent += textView.indentUnit } else { break } }
        return SmartContext(prefix: prefix, line: line, rest: rest, suffix: suffix, indent: indent, length: ns.length)
    }

    func cancelFill() {
        fillWork?.cancel()
        smartToken += 1
        fillGeneration += 1
    }
}

/// Tidies a raw model completion into a ghost suggestion.
enum SmartFillCleanup {
    static let maxLines = 16

    static func clean(_ raw: String?, context: EditorController.SmartContext) -> String? {
        guard var s = raw, !s.isEmpty else { return nil }
        // Drop trailing whitespace and blank lines.
        while let last = s.last, last.isWhitespace { s.removeLast() }
        guard s.contains(where: { !$0.isWhitespace }) else { return nil }

        var lines = s.components(separatedBy: "\n")
        if lines.count > maxLines { lines = Array(lines.prefix(maxLines)) }

        // Stop where the block ends. A line below the caret's level always ends
        // it (the server stops there too, but may already have streamed its first
        // word). After code like `for x in xs:` the block that follows ends back
        // at that line's level. On an empty line the caret is already inside a
        // block (a function body), so `return totals` after a loop still belongs
        // to it; at the top level the next unit after a blank line ends it.
        let base = context.indent
        let onEmptyLine = context.line.trimmingCharacters(in: .whitespaces).isEmpty
        var deeper = false
        var blankRun = 0
        for i in lines.indices.dropFirst() {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun > 1 { lines = Array(lines[..<i]); break }
                continue
            }
            let afterBlank = blankRun > 0
            blankRun = 0
            let width = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            if width > base { deeper = true; continue }
            let ends = width < base || (onEmptyLine ? deeper && base == 0 && afterBlank : deeper)
            if ends { lines = Array(lines[..<i]); break }
        }

        // Don't repeat code that already follows the caret.
        let following = context.suffix.components(separatedBy: "\n").dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let next = following.first, lines.count > 1,
           let cut = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == next }) {
            lines = Array(lines[..<cut])
        }
        s = lines.joined(separator: "\n")
        while let last = s.last, last.isWhitespace { s.removeLast() }

        // The closers after the caret are already there.
        let rest = context.rest.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty, !s.contains("\n"), s.hasSuffix(rest) { s = String(s.dropLast(rest.count)) }
        // A suggestion that starts on a blank line after an empty line is noise.
        if context.line.trimmingCharacters(in: .whitespaces).isEmpty, s.hasPrefix("\n") {
            s = String(s.drop(while: { $0 == "\n" }))
        }
        return s.contains(where: { !$0.isWhitespace }) ? s : nil
    }
}
