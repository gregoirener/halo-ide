import AppKit

extension Notification.Name {
    static let haloEditorSettingsChanged = Notification.Name("HaloEditorSettingsChanged")
}

/// Owns one editor's text system: storage → layout manager → container →
/// text view, plus the gutter, highlighter, bracket matching and line index.
/// Each open document keeps its own controller so undo history, selection
/// and scroll position survive tab switches.
@MainActor
final class EditorController: NSObject, NSTextStorageDelegate, NSLayoutManagerDelegate, NSTextViewDelegate {
    let scrollView: NSScrollView
    let textView: HaloTextView
    let storage: NSTextStorage
    let layoutManager: NSLayoutManager
    let textContainer: NSTextContainer
    private(set) var ruler: LineNumberRuler!

    private(set) var language: Language
    private(set) var highlighter: SyntaxHighlighter
    private(set) var lineStarts: [Int] = [0]
    private(set) var fontSize: CGFloat
    private(set) var lineHeight: CGFloat = 20
    private var baselineNudge: CGFloat = 0

    var onTextChange: (() -> Void)?
    var onEdit: (() -> Void)?
    var onSelectionChange: ((_ line: Int, _ column: Int, _ selected: Int) -> Void)?

    private var fullPassWork: DispatchWorkItem?
    private var bracketRanges: [NSRange] = []
    private var suppressDirty = false
    private var pendingEdit: NSRange?
    private var pendingFullPass = false

    // Feature state drawn by the text view and gutter.
    var fileURL: URL? { didSet { if fileURL != oldValue { scheduleFixScan(after: 0.2) } } }
    var diagnostics: [Diagnostic] = []
    var breakpoints: Set<Int> = [] { didSet { if breakpoints != oldValue { ruler?.needsDisplay = true } } }
    var executionLine: Int? { didSet { if executionLine != oldValue { textView.needsDisplay = true; ruler?.needsDisplay = true } } }
    var lineChanges: [LineChange] = [] { didSet { if lineChanges != oldValue { ruler?.needsDisplay = true } } }
    var onToggleBreakpoint: ((Int) -> Void)?
    var fillWork: DispatchWorkItem?
    var fillGeneration = 0
    /// Identifies the current streamed suggestion; any new request retires the old one.
    var smartToken = 0

    // Mistake fixes: suggestions for existing code, and what was fixed while typing.
    var codeFixes: [CodeFix] = []
    var fixScanWork: DispatchWorkItem?
    var fixScanGeneration = 0
    var lastAutoFixes: [CodeFix] = []
    var autoFixNotice: (range: NSRange, text: String, until: Date)?
    /// Where the last edit happened (to know whether Enter finishes a line you were writing).
    var lastEditLocation: Int?
    /// Edits since the suggestions were found: (range after the edit, change in length).
    var fixEdits: [(NSRange, Int)] = []

    /// When set (Ascend mode), text is centered in a column of this width.
    var centeredWidth: CGFloat? { didSet { layoutInsets() } }
    var wrapsLines = true { didSet { applyWrapping() } }

    init(text: String, language: Language, settings: Preferences) {
        self.language = language
        self.fontSize = settings.fontSize
        self.highlighter = SyntaxHighlighter(language: language)
        highlighter.fontSize = settings.fontSize

        storage = NSTextStorage(string: text, attributes: highlighter.attributes(for: nil))
        layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.usesFontLeading = false
        storage.addLayoutManager(layoutManager)
        textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 6
        layoutManager.addTextContainer(textContainer)

        textView = HaloTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: textContainer)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        super.init()

        storage.delegate = self
        layoutManager.delegate = self
        wrapsLines = settings.wordWrap

        configureTextView()
        configureScrollView()
        applyFont()
        recomputeLineStarts()
        ruler.updateThickness()
        highlighter.highlightAll(storage)

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .haloEditorSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(frameChanged), name: NSView.frameDidChangeNotification, object: scrollView)
    }

    private func configureTextView() {
        let tv = textView
        tv.language = language
        tv.controller = self
        tv.indentUnit = Self.detectIndent(storage.string) ?? language.indentUnit
        tv.delegate = self
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.allowsCharacterPickerTouchBarItem = false
        tv.drawsBackground = true
        tv.backgroundColor = Palette.editorBackground
        tv.insertionPointColor = Palette.caret
        tv.selectedTextAttributes = [.backgroundColor: Palette.selection]
        tv.textContainerInset = NSSize(width: 8, height: 14)
        tv.isVerticallyResizable = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        tv.setAccessibilityLabel("Code editor")
    }

    private func configureScrollView() {
        let sv = scrollView
        sv.documentView = textView
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = !wrapsLines
        sv.autohidesScrollers = true
        sv.scrollerStyle = .overlay
        sv.drawsBackground = true
        sv.backgroundColor = Palette.editorBackground
        sv.borderType = .noBorder
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        sv.postsFrameChangedNotifications = true
        sv.contentView.postsBoundsChangedNotifications = true
        sv.findBarPosition = .aboveContent

        ruler = LineNumberRuler(scrollView: sv, editor: self)
        sv.verticalRulerView = ruler
        sv.hasVerticalRuler = true
        sv.rulersVisible = true
        applyWrapping()
    }

    private func applyWrapping() {
        guard ruler != nil else { return }
        if wrapsLines {
            textContainer.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            scrollView.hasHorizontalScroller = false
            textView.frame.size.width = scrollView.contentSize.width
        } else {
            textContainer.widthTracksTextView = false
            textContainer.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            scrollView.hasHorizontalScroller = true
        }
        layoutInsets()
    }

    private func applyFont() {
        let font = EditorFont.regular(fontSize)
        let natural = layoutManager.defaultLineHeight(for: font)
        lineHeight = (natural * Preferences.shared.lineSpacing).rounded()
        baselineNudge = ((lineHeight - natural) / 2).rounded()
        highlighter.fontSize = fontSize
        textView.font = font
        textView.typingAttributes = highlighter.attributes(for: nil)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        let style = NSMutableParagraphStyle()
        style.defaultTabInterval = space * CGFloat(textView.indentUnit)
        style.tabStops = []
        textView.defaultParagraphStyle = style
        layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        highlighter.highlightAll(storage)
        ruler?.updateThickness()
        ruler?.needsDisplay = true
    }

    @objc private func settingsChanged() {
        let s = Preferences.shared
        if s.fontSize != fontSize || abs(lineHeight - (layoutManager.defaultLineHeight(for: EditorFont.regular(fontSize)) * s.lineSpacing).rounded()) > 0.5 {
            fontSize = s.fontSize
            applyFont()
        }
        if wrapsLines != s.wordWrap { wrapsLines = s.wordWrap }
        scheduleFixScan(after: 0.05)
    }

    @objc private func boundsChanged() { ruler.needsDisplay = true }
    @objc private func frameChanged() { layoutInsets() }

    private func layoutInsets() {
        guard ruler != nil else { return }
        let available = scrollView.contentSize.width
        if let width = centeredWidth, available > width {
            textView.textContainerInset = NSSize(width: ((available - width) / 2).rounded(), height: 64)
            scrollView.rulersVisible = false
        } else {
            textView.textContainerInset = NSSize(width: 8, height: 14)
            scrollView.rulersVisible = centeredWidth == nil
        }
        ruler.needsDisplay = true
    }

    // MARK: Public

    /// The document's real text (without any ghost suggestion).
    var text: String {
        guard let ghost = textView.ghostRange, NSMaxRange(ghost) <= storage.length else { return storage.string }
        return (storage.string as NSString).replacingCharacters(in: ghost, with: "")
    }

    func setText(_ text: String) {
        suppressDirty = true
        let selection = textView.selectedRange()
        textView.replace(NSRange(location: 0, length: storage.length), with: text)
        textView.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
        suppressDirty = false
    }

    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    func lineIndex(for location: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= location { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    static func detectIndent(_ text: String) -> Int? {
        var twos = 0, fours = 0, sampled = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(400) {
            let lead = line.prefix { $0 == " " }.count
            guard lead > 0, line.count > lead else { continue }
            sampled += 1
            if lead % 4 == 0 { fours += 1 } else if lead % 2 == 0 { twos += 1 }
        }
        guard sampled >= 3 else { return nil }
        return twos > fours / 3 ? 2 : 4
    }

    // MARK: Line index

    func recomputeLineStarts() {
        var starts = [0]
        starts.reserveCapacity(lineStarts.count + 8)
        var i = 0
        for unit in storage.string.utf16 {
            i += 1
            if unit == 10 { starts.append(i) }
        }
        lineStarts = starts
    }

    // MARK: NSTextStorageDelegate

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            guard !textView.isManipulatingGhost else { return }
            pendingEdit = pendingEdit.map { NSUnionRange($0, editedRange) } ?? editedRange
            fixEdits.append((editedRange, delta))
        }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        if let edit = pendingEdit {
            pendingEdit = nil
            highlighter.highlightLines(around: edit, in: storage)
            lastEditLocation = NSMaxRange(edit)
        }
        noteEditForFixes()
        let oldCount = lineStarts.count
        recomputeLineStarts()
        if String(oldCount).count != String(lineStarts.count).count { ruler.updateThickness() }
        ruler.needsDisplay = true
        scheduleFullPass()
        if !suppressDirty { onTextChange?() }
        onEdit?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !textView.isManipulatingGhost { fillGeneration += 1 }
        ruler.needsDisplay = true
        updateBracketMatch()
        let sel = textView.selectedRange()
        let line = lineIndex(for: sel.location)
        let column = sel.location - lineStarts[line] + 1
        onSelectionChange?((realLine(forStorage: line) ?? line) + 1, column, sel.length)
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        false
    }

    func scheduleFullPass() {
        fullPassWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Never color a ghost suggestion; run again once it's gone.
            if self.textView.ghostRange != nil { self.pendingFullPass = true; return }
            self.highlighter.highlightAll(self.storage)
        }
        fullPassWork = work
        let delay = storage.length > 200_000 ? 0.35 : 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func ghostDidChange() {
        recomputeLineStarts()
        ruler.needsDisplay = true
        if textView.ghostRange == nil, pendingFullPass {
            pendingFullPass = false
            scheduleFullPass()
        }
    }

    // MARK: Bracket matching

    private func updateBracketMatch() {
        for r in bracketRanges where NSMaxRange(r) <= storage.length {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
        }
        bracketRanges = []
        let sel = textView.selectedRange()
        guard sel.length == 0, storage.length > 0 else { return }
        let ns = storage.string as NSString
        let open: [unichar: unichar] = [40: 41, 91: 93, 123: 125]
        let close: [unichar: unichar] = [41: 40, 93: 91, 125: 123]

        func isCode(_ i: Int) -> Bool {
            let kind = storage.attribute(.haloToken, at: i, effectiveRange: nil) as? String
            return kind != TokenKind.comment.rawValue && kind != TokenKind.string.rawValue
        }

        var candidates: [Int] = []
        if sel.location > 0 { candidates.append(sel.location - 1) }
        if sel.location < ns.length { candidates.append(sel.location) }
        for i in candidates {
            let c = ns.character(at: i)
            guard isCode(i) else { continue }
            if let target = open[c] {
                if let match = scan(ns, from: i + 1, step: 1, open: c, close: target, isCode: isCode) {
                    highlightBrackets(i, match); return
                }
            } else if let target = close[c] {
                if let match = scan(ns, from: i - 1, step: -1, open: c, close: target, isCode: isCode) {
                    highlightBrackets(i, match); return
                }
            }
        }
    }

    private func scan(_ ns: NSString, from start: Int, step: Int, open: unichar, close: unichar, isCode: (Int) -> Bool) -> Int? {
        var depth = 0
        var i = start
        var budget = 20_000
        while i >= 0, i < ns.length, budget > 0 {
            let c = ns.character(at: i)
            if c == open || c == close, isCode(i) {
                if c == close { if depth == 0 { return i }; depth -= 1 } else { depth += 1 }
            }
            i += step
            budget -= 1
        }
        return nil
    }

    private func highlightBrackets(_ a: Int, _ b: Int) {
        bracketRanges = [NSRange(location: a, length: 1), NSRange(location: b, length: 1)]
        for r in bracketRanges {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: Palette.bracketMatch, forCharacterRange: r)
        }
    }

    // MARK: NSLayoutManagerDelegate — fixed, airy line height with centered glyphs

    nonisolated func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        let (height, nudge) = MainActor.assumeIsolated { (lineHeight, baselineNudge) }
        lineFragmentRect.pointee.size.height = height
        lineFragmentUsedRect.pointee.size.height = height
        baselineOffset.pointee += nudge
        return true
    }
}
