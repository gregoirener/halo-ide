import AppKit

/// The editing surface. Plain NSTextView (TextKit 1) plus the small
/// behaviors that make typing code feel effortless: auto-indent, bracket
/// and quote pairing, soft tabs, line comments, line moves.
final class HaloTextView: NSTextView {
    var language: Language = .plain
    var indentUnit = 4
    weak var controller: EditorController?

    // Ghost suggestion (Halo Fill): lives in the text storage, grayed, never
    // in undo history, and vanishes on any edit or caret move.
    private(set) var ghostRange: NSRange?
    private(set) var ghostText = ""
    private var isApplyingGhost = false
    var indentString: String { String(repeating: " ", count: indentUnit) }

    private static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
    private static let closers: Set<Character> = [")", "]", "}", "\"", "'", "`"]
    private static let quotes: Set<Character> = ["\"", "'", "`"]

    private var ns: NSString { string as NSString }

    private func char(at i: Int) -> Character? {
        guard i >= 0, i < ns.length else { return nil }
        return Character(UnicodeScalar(ns.character(at: i)) ?? " ")
    }

    private func token(at i: Int) -> TokenKind? {
        guard let storage = textStorage, i >= 0, i < storage.length else { return nil }
        return (storage.attribute(.haloToken, at: i, effectiveRange: nil) as? String).flatMap(TokenKind.init)
    }

    /// One undoable replacement.
    func replace(_ range: NSRange, with text: String, select: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        breakUndoCoalescing()
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        breakUndoCoalescing()   // what's typed next is its own undo step
        if let select { setSelectedRange(select) }
        scrollRangeToVisible(selectedRange())
    }

    // MARK: Current line

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        if let ghost = ghostRange, !isApplyingGhost {
            let first = ranges.first?.rangeValue ?? NSRange(location: ghost.location, length: 0)
            if !(first.location == ghost.location && first.length == 0 && ranges.count == 1) {
                // Positions were computed with the ghost present; map them back.
                ranges = ranges.map { value in
                    var r = value.rangeValue
                    if r.location >= NSMaxRange(ghost) { r.location -= ghost.length }
                    else if r.location > ghost.location { r.location = ghost.location; r.length = 0 }
                    return NSValue(range: r)
                }
                removeGhost()
            }
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        setNeedsDisplay(visibleRect, avoidAdditionalLayout: true)
    }

    // The ghost isn't in the undo history, so it must be gone before undo
    // or redo replays edits — otherwise their ranges are off by its length.
    private var watchedUndoManager: UndoManager?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        if let old = watchedUndoManager {
            center.removeObserver(self, name: .NSUndoManagerWillUndoChange, object: old)
            center.removeObserver(self, name: .NSUndoManagerWillRedoChange, object: old)
        }
        watchedUndoManager = undoManager
        guard let manager = undoManager else { return }
        center.addObserver(self, selector: #selector(undoWillChange), name: .NSUndoManagerWillUndoChange, object: manager)
        center.addObserver(self, selector: #selector(undoWillChange), name: .NSUndoManagerWillRedoChange, object: manager)
    }

    @objc private func undoWillChange(_ note: Notification) {
        removeGhost()
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if ghostRange != nil, !isApplyingGhost { removeGhost() }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    // MARK: Ghost suggestions

    func showGhost(_ text: String) {
        removeGhost()
        let caret = selectedRange()
        guard caret.length == 0, !text.isEmpty, let storage = textStorage else { return }
        var attrs = typingAttributes
        attrs[.foregroundColor] = Palette.ghost
        attrs[.haloGhost] = true
        attrs.removeValue(forKey: .haloToken)
        isApplyingGhost = true
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: caret.location, length: 0), with: NSAttributedString(string: text, attributes: attrs))
        storage.endEditing()
        ghostRange = NSRange(location: caret.location, length: (text as NSString).length)
        ghostText = text
        super.setSelectedRanges([NSValue(range: caret)], affinity: .downstream, stillSelecting: false)
        isApplyingGhost = false
        controller?.ghostDidChange()
    }

    func removeGhost() {
        guard let ghost = ghostRange, let storage = textStorage else { return }
        isApplyingGhost = true
        if NSMaxRange(ghost) <= storage.length {
            storage.beginEditing()
            storage.replaceCharacters(in: ghost, with: "")
            storage.endEditing()
        }
        ghostRange = nil
        ghostText = ""
        isApplyingGhost = false
        controller?.ghostDidChange()
    }

    var isManipulatingGhost: Bool { isApplyingGhost }

    /// Tab: take the whole suggestion. ⌘→: take the next word.
    func acceptGhost(wordOnly: Bool = false) {
        guard let ghost = ghostRange else { return }
        let full = ghostText
        var take = full
        if wordOnly {
            var end = full.startIndex
            while end < full.endIndex, full[end].isWhitespace { end = full.index(after: end) }
            if end < full.endIndex {
                let isWord: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" }
                if isWord(full[end]) {
                    while end < full.endIndex, isWord(full[end]) { end = full.index(after: end) }
                } else {
                    end = full.index(after: end)
                }
            }
            take = String(full[..<end])
        }
        removeGhost()
        let at = ghost.location
        // If the suggestion already contains the closers to the right of the
        // caret (an auto-inserted ")"), accepting replaces them.
        var replaceLength = 0
        if !wordOnly {
            let lineEnd = NSMaxRange(ns.lineRange(for: NSRange(location: at, length: 0)))
            let restRange = NSRange(location: at, length: max(0, lineEnd - at - (char(at: lineEnd - 1) == "\n" ? 1 : 0)))
            let rest = ns.substring(with: restRange)
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !take.hasPrefix("\n"), trimmed.allSatisfy({ ")]}>\"'`;,".contains($0) }), take.contains(trimmed) {
                replaceLength = restRange.length
            }
        }
        // A trailing "newline + indent" only keeps a closing brace on its own
        // line; the caret belongs at the end of the real code.
        var caretOffset = (take as NSString).length
        if let r = take.range(of: "\n *$", options: .regularExpression), r.lowerBound != take.startIndex {
            caretOffset -= (String(take[r]) as NSString).length
        }
        replace(NSRange(location: at, length: replaceLength), with: take, select: NSRange(location: at + caretOffset, length: 0))
        FillStats.shared.filled += take.count
        let remaining = String(full.dropFirst(take.count))
        if !remaining.isEmpty { showGhost(remaining) } else { controller?.requestFill(immediately: true) }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer, selectedRange().length == 0 else {
            controller?.drawAnnotations(in: rect)
            return
        }
        let caret = selectedRange().location
        var lineRect: NSRect
        if caret >= ns.length, !lm.extraLineFragmentRect.isEmpty {
            lineRect = lm.extraLineFragmentRect
        } else if ns.length > 0 {
            let paragraph = ns.paragraphRange(for: NSRange(location: min(caret, ns.length - 1), length: 0))
            let glyphs = lm.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
            lineRect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
            if glyphs.length > 0 {
                let first = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                let last = lm.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
                lineRect = first.union(last)
            }
        } else {
            lineRect = lm.extraLineFragmentRect
        }
        guard !lineRect.isEmpty else { controller?.drawAnnotations(in: rect); return }
        lineRect.origin.y += textContainerOrigin.y
        lineRect.origin.x = 0
        lineRect.size.width = bounds.width
        if lineRect.intersects(rect) {
            Palette.currentLine.setFill()
            lineRect.fill()
        }
        controller?.drawAnnotations(in: rect)
    }

    // MARK: Typing

    override func insertText(_ insert: Any, replacementRange: NSRange) {
        let typed = (insert as? String) ?? (insert as? NSAttributedString)?.string ?? ""
        // Typing what the ghost already shows just consumes it.
        if ghostRange != nil, !typed.isEmpty, !hasMarkedText(), replacementRange.location == NSNotFound, ghostText.hasPrefix(typed) {
            let remaining = String(ghostText.dropFirst(typed.count))
            removeGhost()
            let insertAt = selectedRange().location
            insertTextCore(insert, replacementRange: replacementRange)
            FillStats.shared.typed += typed.count
            // The word before may be a mistake; fixing it makes the rest of the ghost stale.
            if typed.utf16.count == 1, let unit = typed.utf16.first, FixEngine.isBoundary(unit),
               controller?.fixJustTyped(boundary: insertAt, lineFinished: false) == true {
                controller?.requestFill()
                return
            }
            if !remaining.isEmpty { showGhost(remaining) } else { controller?.requestFill() }
            return
        }
        removeGhost()
        let insertAt = replacementRange.location == NSNotFound ? selectedRange().location : replacementRange.location
        insertTextCore(insert, replacementRange: replacementRange)
        if !hasMarkedText() {
            FillStats.shared.typed += typed.count
            // A word just ended: fix it if it's a mistake Halo is sure about.
            if typed.utf16.count == 1, let unit = typed.utf16.first, FixEngine.isBoundary(unit) {
                controller?.fixJustTyped(boundary: insertAt, lineFinished: false)
            }
            controller?.requestFill()
        }
    }

    private func insertTextCore(_ insert: Any, replacementRange: NSRange) {
        guard !hasMarkedText(), let s = insert as? String, s.count == 1, let ch = s.first else {
            return super.insertText(insert, replacementRange: replacementRange)
        }
        let sel = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let next = char(at: sel.location)

        // Type over an auto-inserted closer.
        if Self.closers.contains(ch), sel.length == 0, next == ch {
            if !Self.quotes.contains(ch) || token(at: sel.location) == .string || token(at: sel.location - 1) == .string || char(at: sel.location - 1) == ch {
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                return
            }
        }

        guard let close = Self.pairs[ch], allowsPairing(ch) else {
            return super.insertText(insert, replacementRange: replacementRange)
        }

        // Wrap a selection.
        if sel.length > 0 {
            let inner = ns.substring(with: sel)
            replace(sel, with: "\(ch)\(inner)\(close)", select: NSRange(location: sel.location + 1, length: (inner as NSString).length))
            return
        }

        let nextIsOpen = next == nil || next!.isWhitespace || ")]},;:".contains(next!)
        if Self.quotes.contains(ch) {
            let prev = char(at: sel.location - 1)
            let prevIsWord = prev.map { $0.isLetter || $0.isNumber || $0 == "\\" } ?? false
            let insideString = token(at: sel.location - 1) == .string && token(at: sel.location) == .string
            guard nextIsOpen, !prevIsWord, !insideString else {
                return super.insertText(insert, replacementRange: replacementRange)
            }
        } else if !nextIsOpen {
            return super.insertText(insert, replacementRange: replacementRange)
        }
        super.insertText("\(ch)\(close)", replacementRange: replacementRange)
        setSelectedRange(NSRange(location: selectedRange().location - 1, length: 0))
    }

    private func allowsPairing(_ ch: Character) -> Bool {
        switch language.id {
        case "plain": return ch != "'" && ch != "\"" && ch != "`"
        case "markdown": return ch != "'"
        case "rust": return ch != "'"
        default: return true
        }
    }

    override func insertNewline(_ sender: Any?) {
        removeGhost()
        let at = selectedRange().location
        // Enter finishes a line you were writing: its sure fixes all apply.
        let lineStart = ns.lineRange(for: NSRange(location: at, length: 0)).location
        let writingIt = controller?.lastEditLocation.map { $0 >= lineStart && $0 <= at } ?? false
        insertNewlineCore()
        controller?.fixJustTyped(boundary: at, lineFinished: writingIt)
        controller?.requestFill()
    }

    /// ⌥↩ applies the suggested fix on this line (or inserts a plain newline).
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        if controller?.applySuggestedFix() == true { return }
        super.insertNewlineIgnoringFieldEditor(sender)
    }

    @objc func applySuggestedFix(_ sender: Any?) {
        if controller?.applySuggestedFix() != true { NSSound.beep() }
    }

    @objc func applyAllSuggestedFixes(_ sender: Any?) {
        controller?.applyAllFixes()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, let fix = controller?.fixHint(at: point) {
            controller?.apply(fix)
            return
        }
        super.mouseDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if ghostRange != nil { removeGhost() } else { super.cancelOperation(sender) }
    }

    override func moveToEndOfLine(_ sender: Any?) {
        if ghostRange != nil { acceptGhost(wordOnly: true) } else { super.moveToEndOfLine(sender) }
    }

    override func moveToRightEndOfLine(_ sender: Any?) {
        if ghostRange != nil { acceptGhost(wordOnly: true) } else { super.moveToRightEndOfLine(sender) }
    }

    private func insertNewlineCore() {
        let sel = selectedRange()
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let beforeCaret = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
        let indent = String(beforeCaret.prefix { $0 == " " || $0 == "\t" })
        let trimmed = beforeCaret.trimmingCharacters(in: .whitespaces)

        var opens = trimmed.hasSuffix("{") || trimmed.hasSuffix("(") || trimmed.hasSuffix("[")
        if ["python", "yaml"].contains(language.id), trimmed.hasSuffix(":") { opens = true }
        if language.id == "ruby", ["do", "then"].contains(where: { trimmed.hasSuffix($0) }) || trimmed.hasPrefix("def ") { opens = true }

        // Continue markdown lists.
        var bullet = ""
        if language.id == "markdown", let match = trimmed.range(of: #"^([-*+]|\d+\.) "#, options: .regularExpression) {
            bullet = String(trimmed[match])
            if trimmed == bullet.trimmingCharacters(in: .whitespaces) || trimmed == String(bullet.dropLast()) {
                replace(NSRange(location: line.location, length: sel.location - line.location), with: "", select: NSRange(location: line.location, length: 0))
                return
            }
            if let n = Int(bullet.dropLast(2)) { bullet = "\(n + 1). " }
        }

        let next = char(at: sel.location)
        let closesImmediately = opens && next.map { "}])".contains($0) } == true
        var text = "\n" + indent + (opens ? indentString : "") + bullet
        let caret = sel.location + (text as NSString).length
        if closesImmediately { text += "\n" + indent }
        replace(sel, with: text, select: NSRange(location: caret, length: 0))
    }

    override func insertTab(_ sender: Any?) {
        if ghostRange != nil { acceptGhost(); return }
        let sel = selectedRange()
        if sel.length > 0, ns.substring(with: sel).contains("\n") {
            shiftLines(by: 1)
            return
        }
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let column = sel.location - line.location
        let spaces = indentUnit - (column % indentUnit)
        super.insertText(String(repeating: " ", count: spaces), replacementRange: sel)
    }

    override func insertBacktab(_ sender: Any?) { shiftLines(by: -1) }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, sel.location > 0 {
            if let prev = char(at: sel.location - 1), let next = char(at: sel.location), Self.pairs[prev] == next {
                replace(NSRange(location: sel.location - 1, length: 2), with: "", select: NSRange(location: sel.location - 1, length: 0))
                return
            }
            // Soft-tab aware: delete back to the previous indent stop.
            let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let lead = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
            if !lead.isEmpty, lead.allSatisfy({ $0 == " " }) {
                let remove = lead.count % indentUnit == 0 ? indentUnit : lead.count % indentUnit
                let range = NSRange(location: sel.location - remove, length: remove)
                replace(range, with: "", select: NSRange(location: range.location, length: 0))
                return
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: Line operations

    private var selectedLinesRange: NSRange {
        var sel = selectedRange()
        if sel.length > 0, char(at: NSMaxRange(sel) - 1) == "\n" { sel.length -= 1 }
        return ns.lineRange(for: sel)
    }

    func shiftLines(by direction: Int) {
        let range = selectedLinesRange
        let block = ns.substring(with: range)
        var lines = block.components(separatedBy: "\n")
        let trailingNewline = block.hasSuffix("\n")
        if trailingNewline { lines.removeLast() }
        let shifted = lines.map { line -> String in
            if direction > 0 { return line.isEmpty ? line : indentString + line }
            let lead = line.prefix { $0 == " " }.count
            return String(line.dropFirst(min(lead, indentUnit)))
        }
        let result = shifted.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        replace(range, with: result, select: NSRange(location: range.location, length: (result as NSString).length - (trailingNewline ? 1 : 0)))
    }

    @objc func toggleComment(_ sender: Any?) {
        let range = selectedLinesRange
        let block = ns.substring(with: range)
        let trailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if trailingNewline { lines.removeLast() }

        let result: String
        if let prefix = language.lineComment {
            let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
            let minIndent = nonEmpty.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
            result = lines.map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
                if allCommented {
                    guard let r = line.range(of: prefix) else { return line }
                    var out = line
                    out.removeSubrange(r)
                    if out[r.lowerBound...].hasPrefix(" ") { out.remove(at: r.lowerBound) }
                    return out
                }
                let idx = line.index(line.startIndex, offsetBy: minIndent)
                return String(line[..<idx]) + prefix + " " + String(line[idx...])
            }.joined(separator: "\n")
        } else if let block = language.blockComment {
            let joined = lines.joined(separator: "\n")
            let t = joined.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(block.open), t.hasSuffix(block.close) {
                result = joined
                    .replacingOccurrences(of: block.open + " ", with: "", options: [], range: joined.range(of: block.open + " "))
                    .replacingOccurrences(of: " " + block.close, with: "", options: .backwards)
            } else {
                let lead = joined.prefix { $0 == " " }
                result = lead + block.open + " " + joined.dropFirst(lead.count) + " " + block.close
            }
        } else {
            NSSound.beep()
            return
        }
        let final = result + (trailingNewline ? "\n" : "")
        replace(range, with: final, select: NSRange(location: range.location, length: (final as NSString).length - (trailingNewline ? 1 : 0)))
    }

    @objc func duplicateLine(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0 {
            let text = ns.substring(with: sel)
            replace(NSRange(location: NSMaxRange(sel), length: 0), with: text, select: NSRange(location: NSMaxRange(sel), length: sel.length))
            return
        }
        let range = ns.lineRange(for: sel)
        var line = ns.substring(with: range)
        if !line.hasSuffix("\n") { line = "\n" + line.trimmingCharacters(in: .newlines); replace(NSRange(location: NSMaxRange(range), length: 0), with: line, select: NSRange(location: sel.location + (line as NSString).length, length: 0)); return }
        replace(NSRange(location: range.location, length: 0), with: line, select: NSRange(location: sel.location + (line as NSString).length, length: 0))
    }

    @objc func moveLineUp(_ sender: Any?) { moveLines(up: true) }
    @objc func moveLineDown(_ sender: Any?) { moveLines(up: false) }

    private func moveLines(up: Bool) {
        let sel = selectedRange()
        let range = selectedLinesRange
        let block = ns.substring(with: range)
        if up {
            guard range.location > 0 else { return }
            let prev = ns.lineRange(for: NSRange(location: range.location - 1, length: 0))
            let prevText = ns.substring(with: prev)
            let moved = block.hasSuffix("\n") ? block + prevText : block + "\n" + prevText.dropLast()
            let combined = NSRange(location: prev.location, length: NSMaxRange(range) - prev.location)
            replace(combined, with: moved, select: NSRange(location: sel.location - prev.length, length: sel.length))
        } else {
            guard NSMaxRange(range) < ns.length else { return }
            let next = ns.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
            let nextText = ns.substring(with: next)
            let nextLen = (nextText as NSString).length
            let moved: String
            let shift: Int
            if nextText.hasSuffix("\n") {
                moved = nextText + block; shift = nextLen
            } else {
                moved = nextText + "\n" + block.dropLast(); shift = nextLen + 1
            }
            let combined = NSRange(location: range.location, length: NSMaxRange(next) - range.location)
            replace(combined, with: moved, select: NSRange(location: sel.location + shift, length: sel.length))
        }
    }

    // MARK: Navigation helpers

    func goTo(line target: Int, column: Int = 1, flash: Bool = true) {
        var line = 1
        var location = 0
        let length = ns.length
        while line < target, location < length {
            let r = ns.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(r)
            line += 1
        }
        let lineRange = ns.lineRange(for: NSRange(location: min(location, length), length: 0))
        let caret = min(lineRange.location + max(0, column - 1), NSMaxRange(lineRange))
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: caret, length: 0))
        centerSelection()
        if flash, lineRange.length > 0 {
            var visible = lineRange
            if char(at: NSMaxRange(visible) - 1) == "\n" { visible.length -= 1 }
            if visible.length > 0 { showFindIndicator(for: visible) }
        }
    }

    func centerSelection() {
        guard let lm = layoutManager, let tc = textContainer, let clip = enclosingScrollView?.contentView else { return }
        let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: min(selectedRange().location, max(0, ns.length - 1)), length: 0), actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        if ns.length == 0 || selectedRange().location >= ns.length { rect = lm.extraLineFragmentRect.isEmpty ? rect : lm.extraLineFragmentRect }
        let y = max(0, rect.midY + textContainerOrigin.y - clip.bounds.height / 2)
        let maxY = max(0, frame.height - clip.bounds.height)
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: min(y, maxY)))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }
}
