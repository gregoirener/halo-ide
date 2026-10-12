import AppKit

/// Mistakes: fixed the moment they're typed, proposed for code written earlier.
extension EditorController {
    var fixFamily: String? {
        FixEngine.family(language: language.id, fileExtension: fileURL?.pathExtension ?? "")
    }

    /// Fix ranges are in the real text; the storage may hold a ghost suggestion.
    func storageRange(forText range: NSRange) -> NSRange {
        guard let ghost = textView.ghostRange, range.location >= ghost.location else { return range }
        return NSRange(location: range.location + ghost.length, length: range.length)
    }

    // MARK: Watching edits

    func noteEditForFixes() {
        // ⌘Z right after an auto-fix means "I meant that": never change it again.
        if textView.undoManager?.isUndoing == true, !lastAutoFixes.isEmpty {
            let ns = storage.string as NSString
            for fix in lastAutoFixes {
                let restored = NSRange(location: fix.range.location, length: (fix.original as NSString).length)
                if NSMaxRange(restored) <= ns.length, ns.substring(with: restored) == fix.original { FixEngine.shared.ignore(fix.original) }
            }
            lastAutoFixes = []
            autoFixNotice = nil
        }
        // Keep suggestions in place while typing: shift those after an edit, drop those it touched.
        if !codeFixes.isEmpty, !fixEdits.isEmpty {
            for (edited, delta) in fixEdits {
                let oldEnd = edited.location + edited.length - delta
                codeFixes = codeFixes.compactMap { fix in
                    var fix = fix
                    func moved(_ r: NSRange) -> NSRange? {
                        if NSMaxRange(r) <= edited.location, !(r.length == 0 && r.location == edited.location && !fix.insertsLine) { return r }
                        if r.location >= oldEnd { return NSRange(location: r.location + delta, length: r.length) }
                        return nil
                    }
                    guard let anchor = moved(fix.anchor), let range = moved(fix.range) else { return nil }
                    fix.anchor = anchor
                    fix.range = range
                    return fix
                }
            }
            applyUnderlines()
        }
        fixEdits = []
        scheduleFixScan()
    }

    func scheduleFixScan(after delay: TimeInterval = 0.6) {
        fixScanWork?.cancel()
        guard Preferences.shared.suggestFixes, let family = fixFamily else {
            if !codeFixes.isEmpty { codeFixes = []; applyUnderlines() }
            return
        }
        fixScanGeneration += 1
        let generation = fixScanGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.fixScanGeneration else { return }
            let text = self.text
            Task.detached(priority: .utility) {
                let found = FixEngine.shared.fixes(in: text, family: family)
                await MainActor.run { [weak self] in
                    guard let self, generation == self.fixScanGeneration, self.text == text else { return }
                    // Leave the word under the caret alone while it's being typed.
                    let caret = self.textView.selectedRange().location
                    self.codeFixes = found.filter { !(NSMaxRange($0.anchor) == caret || NSLocationInRange(caret, $0.anchor) && $0.anchor.location != caret) }
                    self.applyUnderlines()
                    self.textView.needsDisplay = true
                }
            }
        }
        fixScanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Fixing what was just typed

    /// Called after a character that finishes a word (space, bracket, Enter…). True if something was fixed.
    @discardableResult
    func fixJustTyped(boundary: Int, lineFinished: Bool) -> Bool {
        guard Preferences.shared.autoFix, let family = fixFamily, textView.ghostRange == nil else { return false }
        let fixes = FixEngine.shared.justTyped(in: storage.string, family: family, boundary: boundary, lineFinished: lineFinished)
        guard !fixes.isEmpty else { return false }
        var caret = textView.selectedRange().location
        var applied: [CodeFix] = []
        // Close the typing step first, so ⌘Z takes back only the fix.
        textView.breakUndoCoalescing()
        textView.undoManager?.beginUndoGrouping()
        for fix in fixes.reversed() {
            let delta = (fix.replacement as NSString).length - fix.range.length
            textView.replace(fix.range, with: fix.replacement)
            if fix.range.location < caret { caret = max(fix.range.location, caret + delta) }
            var done = fix
            done.range = NSRange(location: fix.range.location, length: (fix.replacement as NSString).length)
            applied.append(done)
        }
        textView.undoManager?.endUndoGrouping()
        textView.undoManager?.setActionName("Fix Mistake")
        textView.setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
        lastAutoFixes = applied
        if let first = fixes.first {
            let summary = fixes.count == 1 ? "\(first.original.trimmingCharacters(in: .whitespaces)) → \(first.label)" : "Fixed \(fixes.count) mistakes"
            autoFixNotice = (applied[applied.count - 1].range, summary, Date().addingTimeInterval(3.2))
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) { [weak self] in self?.textView.needsDisplay = true }
            NSAccessibility.post(element: textView, notification: .announcementRequested,
                                 userInfo: [.announcement: "Fixed: \(summary)", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        flashFixed(applied.map(\.range))
        return true
    }

    private func flashFixed(_ ranges: [NSRange]) {
        for range in ranges where NSMaxRange(range) <= storage.length && range.length > 0 {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: Palette.sky.withAlphaComponent(0.18), forCharacterRange: range)
        }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 1.2 : 0.7)) { [weak self] in
            guard let self else { return }
            for range in ranges where NSMaxRange(range) <= self.storage.length {
                self.layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            }
        }
    }

    // MARK: Applying suggestions

    var caretLineFixes: [CodeFix] {
        let ns = text as NSString
        let caret = min(textView.selectedRange().location, ns.length)
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        return codeFixes.filter { NSLocationInRange($0.anchor.location, line) || ($0.anchor.location == NSMaxRange(line) && line.length == 0) }
            .sorted { abs($0.anchor.location - caret) < abs($1.anchor.location - caret) }
    }

    /// ⌥↩: the fix nearest the caret on its line.
    @discardableResult
    func applySuggestedFix() -> Bool {
        guard let fix = caretLineFixes.first else { return false }
        apply(fix)
        return true
    }

    func apply(_ fix: CodeFix) {
        let ns = storage.string as NSString
        let range = storageRange(forText: fix.range)
        textView.removeGhost()
        guard NSMaxRange(range) <= ns.length, fix.insertsLine || ns.substring(with: range) == fix.original else {
            scheduleFixScan(after: 0)
            return
        }
        let caret = textView.selectedRange().location
        textView.replace(range, with: fix.replacement)
        let delta = (fix.replacement as NSString).length - range.length
        textView.setSelectedRange(NSRange(location: range.location <= caret ? caret + delta : caret, length: 0))
        textView.undoManager?.setActionName("Fix Mistake")
        codeFixes.removeAll { $0 == fix }
        flashFixed(fix.insertsLine ? [] : [NSRange(location: range.location, length: (fix.replacement as NSString).length)])
        scheduleFixScan(after: 0.1)
    }

    /// Every suggestion in the file, as one undoable change.
    func applyAllFixes() {
        let fixes = codeFixes
        guard !fixes.isEmpty else { return }
        textView.removeGhost()
        textView.undoManager?.beginUndoGrouping()
        var inserted = Set<String>()
        // Replacements from the end, so earlier ranges stay valid; added lines last.
        for fix in fixes.filter({ !$0.insertsLine }).sorted(by: { $0.range.location > $1.range.location }) {
            let ns = storage.string as NSString
            guard NSMaxRange(fix.range) <= ns.length, ns.substring(with: fix.range) == fix.original else { continue }
            textView.replace(fix.range, with: fix.replacement)
        }
        for fix in fixes.filter(\.insertsLine) where inserted.insert(fix.replacement).inserted {
            let point = min(fix.range.location, storage.length)
            textView.replace(NSRange(location: point, length: 0), with: fix.replacement)
        }
        textView.undoManager?.endUndoGrouping()
        textView.undoManager?.setActionName("Fix All Mistakes")
        codeFixes = []
        applyUnderlines()
        scheduleFixScan(after: 0.1)
    }

    // MARK: Drawing

    private var hintFont: NSFont { NSFont.systemFont(ofSize: max(10.5, fontSize - 2), weight: .medium) }

    private func realLineNumber(forText location: Int) -> Int? {
        let storageLocation = storageRange(forText: NSRange(location: location, length: 0)).location
        return realLine(forStorage: lineIndex(for: min(storageLocation, storage.length))).map { $0 + 1 }
    }

    private func hintText(for fix: CodeFix, onCaretLine: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString(string: "→ " + fix.label, attributes: [.font: hintFont, .foregroundColor: Palette.sky])
        if onCaretLine {
            out.append(NSAttributedString(string: "   ⌥↩", attributes: [.font: hintFont, .foregroundColor: Palette.tertiaryText]))
        }
        return out
    }

    /// Draws each line's first suggestion (and a just-made fix) after the line; returns their widths by line.
    func drawFixHints(in dirty: NSRect) -> [Int: CGFloat] {
        var widths: [Int: CGFloat] = [:]
        let caretLine = realLineNumber(forText: textView.selectedRange().location)
        var seen = Set<Int>()
        for fix in codeFixes {
            guard let line = realLineNumber(forText: fix.anchor.location), seen.insert(line).inserted,
                  let rect = lineRect(forLine: line), rect.intersects(dirty) else { continue }
            let hint = hintText(for: fix, onCaretLine: line == caretLine)
            let x = lineEndX(forLine: line) + 28
            let size = hint.size()
            guard textView.bounds.width - x - 16 > size.width else { continue }
            hint.draw(at: NSPoint(x: x, y: rect.minY + (lineHeight - size.height) / 2))
            widths[line] = size.width
        }
        if let notice = autoFixNotice {
            let remaining = notice.until.timeIntervalSinceNow
            if remaining <= 0 {
                autoFixNotice = nil
            } else if let line = realLineNumber(forText: notice.range.location), let rect = lineRect(forLine: line), rect.intersects(dirty) {
                let alpha = min(1, remaining / 0.8)
                let text = NSMutableAttributedString(string: notice.text, attributes: [.font: hintFont, .foregroundColor: Palette.secondaryText.withAlphaComponent(alpha)])
                text.append(NSAttributedString(string: "   ⌘Z undoes", attributes: [.font: hintFont, .foregroundColor: Palette.tertiaryText.withAlphaComponent(alpha)]))
                let x = lineEndX(forLine: line) + 28 + (widths[line].map { $0 + 16 } ?? 0)
                let size = text.size()
                if textView.bounds.width - x - 16 > size.width {
                    text.draw(at: NSPoint(x: x, y: rect.minY + (lineHeight - size.height) / 2))
                    widths[line] = (widths[line].map { $0 + 16 } ?? 0) + size.width
                }
                if remaining < 0.8 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30) { [weak self] in self?.textView.setNeedsDisplay(rect) }
                }
            }
        }
        return widths
    }

    /// The suggestion whose hint is under a click.
    func fixHint(at point: NSPoint) -> CodeFix? {
        let caretLine = realLineNumber(forText: textView.selectedRange().location)
        var seen = Set<Int>()
        for fix in codeFixes {
            guard let line = realLineNumber(forText: fix.anchor.location), seen.insert(line).inserted, let rect = lineRect(forLine: line),
                  point.y >= rect.minY, point.y < rect.maxY else { continue }
            let x = lineEndX(forLine: line) + 28
            let width = hintText(for: fix, onCaretLine: line == caretLine).size().width
            if point.x >= x - 4, point.x <= x + width + 4 { return fix }
        }
        return nil
    }
}
