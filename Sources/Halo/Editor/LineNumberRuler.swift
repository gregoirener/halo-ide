import AppKit

/// The gutter: breakpoints on the left, line numbers, git change bars on
/// the right. Click a line number to toggle a breakpoint.
final class LineNumberRuler: NSRulerView {
    weak var editor: EditorController?
    private var hoverLine: Int?
    private static let breakpointColumn: CGFloat = 18
    private static let gitColumn: CGFloat = 7

    init(scrollView: NSScrollView, editor: EditorController) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor.textView
        clipsToBounds = true
        ruleThickness = 56
    }

    required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var requiredThickness: CGFloat { ruleThickness }

    func updateThickness() {
        guard let editor else { return }
        let digits = max(3, String(editor.realLineCount).count)
        let width = CGFloat(digits) * EditorFont.regular(editor.fontSize - 1).maximumAdvancement.width
            + Self.breakpointColumn + Self.gitColumn + 14
        if abs(width - ruleThickness) > 0.5 { ruleThickness = width.rounded() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let line = line(at: convert(event.locationInWindow, from: nil))
        if line != hoverLine { hoverLine = line; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hoverLine = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let editor, let line = line(at: convert(event.locationInWindow, from: nil)) else { return }
        editor.onToggleBreakpoint?(line)
    }

    /// Real (1-based) line under a point in ruler coordinates.
    private func line(at point: NSPoint) -> Int? {
        guard let editor, let lm = editor.textView.layoutManager, let tc = editor.textView.textContainer else { return nil }
        let tv = editor.textView
        let yInText = point.y - convert(NSPoint.zero, from: tv).y - tv.textContainerOrigin.y
        let length = (tv.string as NSString).length
        var storageIndex: Int
        if length == 0 || yInText >= lm.extraLineFragmentRect.minY && !lm.extraLineFragmentRect.isEmpty {
            storageIndex = editor.lineStarts.count - 1
        } else {
            let glyph = lm.glyphIndex(for: NSPoint(x: 1, y: max(0, yInText)), in: tc)
            let char = lm.characterIndexForGlyph(at: glyph)
            storageIndex = editor.lineIndex(for: char)
        }
        guard let real = editor.realLine(forStorage: storageIndex) else { return nil }
        return real + 1
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        Palette.editorBackground.setFill()
        rect.fill()

        guard let editor, let lm = editor.textView.layoutManager, let tc = editor.textView.textContainer,
              let clip = scrollView?.contentView else { return }

        let tv = editor.textView
        let starts = editor.lineStarts
        let length = (tv.string as NSString).length
        let glyphRange = lm.glyphRange(forBoundingRect: clip.bounds, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let caretLine = editor.realLine(forStorage: editor.lineIndex(for: tv.selectedRange().location)).map { $0 + 1 }
        let offsetY = convert(NSPoint.zero, from: tv).y + tv.textContainerOrigin.y
        let lineHeight = editor.lineHeight

        let font = EditorFont.regular(editor.fontSize - 1)
        let strong = EditorFont.medium(editor.fontSize - 1)
        let numbersRight = ruleThickness - Self.gitColumn - 6

        var errorLines: [Int: NSColor] = [:]
        for d in editor.diagnostics.sorted(by: { $0.severity > $1.severity }) where d.severity != .note { errorLines[d.line] = d.color }

        var changeByLine: [Int: LineChange.Kind] = [:]
        for change in editor.lineChanges {
            for l in change.lines { changeByLine[l] = change.kind }
        }

        var index = editor.lineIndex(for: charRange.location)
        while index < starts.count {
            let start = starts[index]
            if start > NSMaxRange(charRange) { break }
            defer { index += 1 }
            guard let real = editor.realLine(forStorage: index) else { continue }   // ghost line
            let line = real + 1
            let fragment: NSRect
            if start >= length {
                fragment = lm.extraLineFragmentRect
                if fragment.isEmpty && length > 0 { break }
            } else {
                fragment = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: start), effectiveRange: nil, withoutAdditionalLayout: true)
            }
            let y = fragment.minY + offsetY
            let rowRect = NSRect(x: 0, y: y, width: ruleThickness, height: lineHeight)

            // Breakpoint (or its hover preview) and the execution marker.
            let dot = NSRect(x: 5, y: y + (lineHeight - 10) / 2, width: 10, height: 10)
            if editor.breakpoints.contains(line) {
                Palette.breakpoint.setFill()
                NSBezierPath(ovalIn: dot).fill()
            } else if hoverLine == line {
                Palette.breakpoint.withAlphaComponent(0.3).setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            if editor.executionLine == line {
                let arrow = NSBezierPath()
                let midY = y + lineHeight / 2
                arrow.move(to: NSPoint(x: 3, y: midY - 5))
                arrow.line(to: NSPoint(x: 11, y: midY - 5))
                arrow.line(to: NSPoint(x: 16, y: midY))
                arrow.line(to: NSPoint(x: 11, y: midY + 5))
                arrow.line(to: NSPoint(x: 3, y: midY + 5))
                arrow.close()
                Palette.executionMarker.setFill()
                arrow.fill()
            }

            // Number.
            let label = "\(line)" as NSString
            let color = errorLines[line] ?? (line == caretLine ? Palette.text : Palette.gutterText)
            let attrs: [NSAttributedString.Key: Any] = [.font: line == caretLine ? strong : font, .foregroundColor: color]
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: numbersRight - size.width, y: y + (lineHeight - size.height) / 2), withAttributes: attrs)

            // Git change bar.
            if let kind = changeByLine[line] {
                let barX = ruleThickness - Self.gitColumn + 1
                switch kind {
                case .added, .modified:
                    (kind == .added ? Palette.added : Palette.sky).withAlphaComponent(0.8).setFill()
                    NSBezierPath(roundedRect: NSRect(x: barX, y: rowRect.minY, width: 3, height: lineHeight), xRadius: 1.5, yRadius: 1.5).fill()
                case .deleted:
                    let tri = NSBezierPath()
                    tri.move(to: NSPoint(x: barX - 1, y: rowRect.maxY - 4))
                    tri.line(to: NSPoint(x: barX + 5, y: rowRect.maxY))
                    tri.line(to: NSPoint(x: barX - 1, y: rowRect.maxY + 4))
                    tri.close()
                    Palette.error.withAlphaComponent(0.8).setFill()
                    tri.fill()
                }
            }
        }
    }
}
