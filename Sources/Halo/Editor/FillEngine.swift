import Foundation

/// Halo Fill — offline, model-free inline completion.
///
/// Every file in the project (and, weighted higher, the buffer being edited)
/// is tokenized into a stream of symbols. To complete, the engine looks up
/// every earlier place where the last few symbols before the caret appeared,
/// measures how far back each match agrees, and lets those places vote on
/// what comes next. The continuation all strong matches agree on becomes the
/// ghost suggestion. Code is repetitive, so this finds a lot: the next
/// argument list, the rest of a familiar call, the line that always follows
/// this one.
///
/// All state lives on one serial queue; callers get results on the main queue.
final class FillEngine: @unchecked Sendable {
    static let shared = FillEngine()

    struct Request {
        let text: String          // full buffer
        let caret: Int            // UTF-16 offset
        let family: String
        let fileURL: URL?
        let indentUnit: Int
    }

    private let queue = DispatchQueue(label: "halo.fill", qos: .userInitiated)
    private var vocab = Vocabulary()
    private var families: [String: FamilyCorpus] = [:]
    private var projectRoot: URL?
    private var rebuildWork: [String: DispatchWorkItem] = [:]

    static let maxFileBytes = 400_000
    static let maxFamilyTokens = 1_500_000

    // MARK: - Indexing

    func indexProject(root: URL, files: [IndexedFile]) {
        queue.async { [self] in
            projectRoot = root
            families = [:]
            var byFamily: [String: [URL]] = [:]
            for file in files {
                let family = Self.family(for: file.url)
                guard family != "plain" else { continue }
                byFamily[family, default: []].append(file.url)
            }
            for (family, urls) in byFamily {
                var corpus = FamilyCorpus()
                var total = 0
                for url in urls {
                    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.maxFileBytes,
                          let data = try? Data(contentsOf: url), !data.prefix(2000).contains(0),
                          let text = String(data: data, encoding: .utf8) else { continue }
                    let tokens = Tokenizer.tokenize(Array(text.utf16), vocab: &vocab)
                    corpus.files[url.standardizedFileURL.path] = tokens
                    total += tokens.count
                    if total > Self.maxFamilyTokens { break }
                }
                corpus.rebuild(vocab: &vocab)
                families[family] = corpus
            }
        }
    }

    /// Re-learns one file after it's saved.
    func update(url: URL, text: String) {
        let family = Self.family(for: url)
        guard family != "plain" else { return }
        queue.async { [self] in
            var corpus = families[family] ?? FamilyCorpus()
            corpus.files[url.standardizedFileURL.path] = Tokenizer.tokenize(Array(text.utf16), vocab: &vocab)
            families[family] = corpus
            rebuildWork[family]?.cancel()
            let work = DispatchWorkItem { [self] in families[family]?.rebuild(vocab: &vocab) }
            rebuildWork[family] = work
            queue.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    func reset() {
        queue.async { [self] in families = [:]; projectRoot = nil }
    }

    static func family(for url: URL) -> String {
        let id = Language.detect(url: url).id
        switch id {
        case "javascript", "typescript": return "js"
        case "c", "objc": return "c"
        case "cpp": return "cpp"
        case "plain":
            let ext = url.pathExtension.lowercased()
            return ext.isEmpty ? "plain" : "ext:" + ext
        default: return id
        }
    }

    // MARK: - Suggesting

    func suggest(_ request: Request, completion: @escaping (String?) -> Void) {
        queue.async { [self] in
            let result = predict(request)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Synchronous variant for tests and benchmarks.
    func suggestNow(_ request: Request) -> String? { queue.sync { predict(request) } }

    /// Blocks until queued indexing work has finished (tests).
    func waitUntilIdle() { queue.sync {} }

    /// How picky a voting pass is. Your own code is trusted with strict
    /// agreement; the built-in library and weak matches are used as fallbacks.
    struct Mode {
        var firstShare: Double
        var nextShare: Double
        var minExact: Int
        var minShape: Int
        static let strict = Mode(firstShare: 0.5, nextShare: 0.7, minExact: 4, minShape: 6)
        static let combined = Mode(firstShare: 0.45, nextShare: 0.65, minExact: 3, minShape: 5)
        /// Last resort: take the most likely continuation even without a majority.
        static let relaxed = Mode(firstShare: 0.0, nextShare: 0.5, minExact: 2, minShape: 3)
    }

    var exponent = 2.0

    private func predict(_ r: Request) -> String? {
        let units = Array(r.text.utf16)
        let caret = min(r.caret, units.count)

        // Current line split around the caret.
        var lineStart = caret
        while lineStart > 0, units[lineStart - 1] != 10 { lineStart -= 1 }
        var lineEnd = caret
        while lineEnd < units.count, units[lineEnd] != 10 { lineEnd += 1 }
        let rest = String(utf16CodeUnits: Array(units[caret..<lineEnd]), count: lineEnd - caret)
        let restTrimmed = rest.trimmingCharacters(in: .whitespaces)
        // Only suggest at the end of a line, or before closing punctuation.
        guard restTrimmed.allSatisfy({ ")]}>\"'`;,".contains($0) }) else { return nil }

        // Partial identifier under the caret.
        var wordStart = caret
        while wordStart > lineStart, Tokenizer.isIdent(units[wordStart - 1]) { wordStart -= 1 }
        var prefix = String(utf16CodeUnits: Array(units[wordStart..<caret]), count: caret - wordStart)
        // A number isn't a word being typed; it's context.
        if let first = prefix.utf16.first, Tokenizer.isDigit(first) {
            prefix = ""
            wordStart = caret
        }
        // A word right after the indentation has no leading space in the token stream.
        let onlyIndentBefore = units[lineStart..<wordStart].allSatisfy { $0 == 32 || $0 == 9 }
        let spaceBeforePrefix = !onlyIndentBefore && (units[wordStart - 1] == 32 || units[wordStart - 1] == 9)

        // Context: symbols before the partial word (bounded window).
        let windowStart = max(0, wordStart - 6000)
        let contextEnd = prefix.isEmpty ? caret : (spaceBeforePrefix ? wordStart - 1 : wordStart)
        let contextUnits = Array(units[windowStart..<max(windowStart, contextEnd)])
        var context = Tokenizer.tokenize(contextUnits, vocab: &vocab, startsMidFile: windowStart > 0)
        if context.count > 64 { context = Array(context.suffix(64)) }

        // The buffer itself, minus the line being typed, is the freshest corpus.
        var bufferUnits = Array(units[0..<lineStart])
        if lineEnd < units.count { bufferUnits.append(contentsOf: units[lineEnd...]) }
        var buffer = FamilyCorpus()
        buffer.files["<buffer>"] = Tokenizer.tokenize(bufferUnits, vocab: &vocab)
        buffer.rebuild(vocab: &vocab)

        var local: [(corpus: FamilyCorpus, weight: Double)] = [(buffer, 2.2)]
        if let project = families[r.family] {
            // Avoid double counting the saved copy of this same file.
            local.append((project.excluding(r.fileURL?.standardizedFileURL.path), 1.0))
        }
        let library = starterCorpus(r.family)

        // Names a suggestion may use: yours (file + project) and the language's own.
        var known = Self.builtins[r.family] ?? []
        known.formUnion(Vocabulary.keywords)
        for (corpus, _) in local {
            for sym in corpus.identifierCounts.keys {
                let t = vocab.text(sym)
                if isWordSymbol(t) { known.insert(t.trimmingCharacters(in: .whitespaces)) }
            }
        }
        for sym in context {
            let t = vocab.text(sym)
            if isWordSymbol(t) { known.insert(t.trimmingCharacters(in: .whitespaces)) }
        }
        knownNames = known

        let indent = Self.indentWidth(units, lineStart: lineStart, lineEnd: lineEnd, indentUnit: r.indentUnit)
        let prefixSymbol: String? = prefix.isEmpty ? nil : (spaceBeforePrefix ? " " : "") + prefix
        let afterSpace = prefix.isEmpty && caret > lineStart && (units[caret - 1] == 32 || units[caret - 1] == 9)
        let lineBefore = String(utf16CodeUnits: Array(units[lineStart..<caret]), count: caret - lineStart)
        do {
            let words = lineBefore.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).map(String.init)
            let opens = lineBefore.filter { $0 == "(" }.count - lineBefore.filter { $0 == ")" }.count
            lineSeed = (words.first ?? "", words.contains(where: { Self.functionWords.contains($0) }), max(0, opens))
        }

        // After a blank line you're starting something new: only your own code
        // gets to guess what.
        let previousLineBlank: Bool = {
            guard lineBefore.trimmingCharacters(in: .whitespaces).isEmpty, lineStart > 0 else { return false }
            var i = lineStart - 1          // the newline ending the previous line
            var sawText = false
            while i > 0, units[i - 1] != 10 {
                if units[i - 1] != 32 && units[i - 1] != 9 { sawText = true }
                i -= 1
            }
            return !sawText
        }()

        // One vote across your file, your project and the built-in library —
        // the longest agreement wins — then a last-resort guess.
        let everything = local + (library.map { [($0, 1.0)] } ?? [])
        var passes: [([(corpus: FamilyCorpus, weight: Double)], Mode)] = []
        if previousLineBlank {
            // Starting something new: only strong evidence (top level: your code only).
            passes = indent == 0 ? [(local, .strict)] : [(everything, .strict)]
        } else {
            passes = [(everything, .combined), (everything, .relaxed)]
        }

        let trimmedBefore = lineBefore.trimmingCharacters(in: .whitespaces)
        let opensBlock = trimmedBefore.hasSuffix("{") || trimmedBefore.hasSuffix(":")
        let insideEmptyBraces = restTrimmed == "}" && trimmedBefore.hasSuffix("{")

        for (sources, mode) in passes {
            guard let text = vote(context: context, prefixSymbol: prefixSymbol, sources: sources, indent: indent,
                                  mode: mode, opensBlock: opensBlock) else { continue }
            if var cleaned = finalize(afterSpace && text.hasPrefix(" ") ? String(text.dropFirst()) : text,
                                      prefixSymbol: prefixSymbol, rest: insideEmptyBraces ? "" : restTrimmed, lineBefore: lineBefore) {
                // Between auto-paired braces, keep the closing brace on its own line.
                if insideEmptyBraces {
                    guard cleaned.hasPrefix("\n") else { continue }
                    cleaned += "\n" + String(repeating: " ", count: indent)
                }
                return cleaned
            }
        }
        // 4. Finish the identifier from words seen nearby.
        if prefix.utf16.count >= 2, let word = completeWord(prefix: prefix, sources: local + (library.map { [($0, 0.5)] } ?? [])) {
            return word
        }
        // 5. Structure: close what's open and end the line the way this language does.
        return structural(lineBefore: lineBefore, family: r.family, rest: restTrimmed)
    }

    /// Set per request: identifiers a suggestion is allowed to use, and what
    /// the line being typed already says (its first word, whether it's a
    /// function signature, open parentheses).
    private var knownNames: Set<String> = []
    private var lineSeed = (opener: "", hasFunc: false, parens: 0)
    private static let functionWords: Set<String> = ["def", "func", "function", "fn", "lambda", "fun", "sub", "proc"]

    private static let modifiers: Set<String> = ["public", "private", "protected", "static", "final", "override", "async",
                                                  "export", "mutating", "open", "internal", "fileprivate", "inline", "virtual", "abstract"]

    private static let definers: Set<String> = [
        "def", "class", "for", "let", "const", "var", "function", "fn", "func", "as", "import", "from", "struct", "enum",
        "interface", "int", "float", "double", "char", "void", "bool", "boolean", "long", "short", "String", "auto",
        "string", "number", "val", "case", "catch", "except", "lambda", "type", "typedef", "unsigned", "size_t", "with",
    ]

    static let builtins: [String: Set<String>] = [
        "python": ["print", "len", "range", "input", "int", "str", "float", "list", "dict", "set", "tuple", "bool", "open", "enumerate",
                   "zip", "map", "filter", "sorted", "reversed", "sum", "min", "max", "abs", "round", "isinstance", "type", "super",
                   "object", "Exception", "ValueError", "KeyError", "IndexError", "TypeError", "RuntimeError", "StopIteration",
                   "NotImplementedError", "ZeroDivisionError", "any", "all", "iter", "next", "hasattr", "getattr", "setattr",
                   "repr", "format", "chr", "ord", "divmod", "pow", "id", "hash", "callable", "vars", "dir", "help", "exit",
                   "self", "cls", "__name__", "__init__", "__str__", "__repr__", "__len__", "__eq__", "__iter__", "_"],
        "js": ["console", "Math", "JSON", "Object", "Array", "String", "Number", "Boolean", "Promise", "fetch", "document",
               "window", "setTimeout", "clearTimeout", "setInterval", "clearInterval", "require", "module", "exports",
               "process", "Date", "Error", "TypeError", "Map", "Set", "WeakMap", "Symbol", "parseInt", "parseFloat", "isNaN",
               "Infinity", "NaN", "undefined", "null", "this", "arguments", "localStorage", "navigator", "event", "globalThis",
               "Record", "Partial", "Readonly", "Pick", "Omit", "ReturnType", "Parameters", "React", "useState", "useEffect"],
        "c": ["printf", "scanf", "malloc", "calloc", "realloc", "free", "strlen", "strcpy", "strncpy", "strcmp", "strcat",
              "memset", "memcpy", "fopen", "fclose", "fprintf", "fgets", "fputs", "puts", "putchar", "getchar", "exit",
              "NULL", "size_t", "FILE", "sizeof", "EOF", "stdin", "stdout", "stderr", "main", "argc", "argv", "rand", "srand",
              "time", "abs", "sqrt", "pow", "atoi", "perror", "EXIT_SUCCESS", "EXIT_FAILURE", "true", "false", "bool"],
        "cpp": ["std", "cout", "cin", "cerr", "endl", "string", "vector", "map", "unordered_map", "set", "pair", "make_pair",
                "sort", "find", "begin", "end", "size", "push_back", "printf", "NULL", "nullptr", "main", "argc", "argv",
                "unique_ptr", "shared_ptr", "make_unique", "make_shared", "move", "swap", "max", "min", "abs", "getline",
                "to_string", "stoi", "exception", "runtime_error", "size_t", "auto", "this", "true", "false"],
        "java": ["System", "out", "println", "print", "printf", "String", "Math", "Integer", "Double", "Boolean", "Long",
                 "Character", "List", "ArrayList", "Map", "HashMap", "Set", "HashSet", "Scanner", "Arrays", "Collections",
                 "Exception", "RuntimeException", "IllegalArgumentException", "IllegalStateException", "Override", "Object",
                 "main", "args", "this", "super", "null", "true", "false", "length", "size", "add", "get", "put", "equals",
                 "toString", "hashCode", "Optional", "Stream", "Collectors"],
        "swift": ["print", "Int", "String", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Character", "URL", "Data",
                  "Date", "JSONDecoder", "JSONEncoder", "Task", "MainActor", "View", "Text", "VStack", "HStack", "ZStack",
                  "Button", "Image", "List", "ForEach", "State", "Binding", "self", "Self", "nil", "true", "false", "count",
                  "isEmpty", "append", "map", "filter", "reduce", "sorted", "first", "last", "min", "max", "abs", "Error",
                  "Result", "Optional", "some", "any", "Codable", "Identifiable", "Hashable", "Equatable"],
    ]

    private final class Node {
        var weight = 0.0
        var children: [Int32: Node] = [:]
    }

    private func isWordSymbol(_ text: String) -> Bool {
        let word = text.hasPrefix(" ") ? text.dropFirst() : Substring(text)
        guard let first = word.unicodeScalars.first else { return false }
        return first == "_" || first == "$" || CharacterSet.letters.contains(first)
    }

    private func vote(context: [Int32], prefixSymbol: String?, sources: [(corpus: FamilyCorpus, weight: Double)],
                      indent: Int, mode: Mode, opensBlock: Bool = false) -> String? {
        guard !context.isEmpty || prefixSymbol != nil else { return nil }
        let root = Node()
        var strongest = 0
        var candidates = 0
        var informative = 0     // matched words, not just brackets and newlines

        func wordsIn(_ tokens: [Int32], from pos: Int, length: Int) -> Int {
            var n = 0
            for i in max(0, pos - length)..<pos where tokens[i] > 0 {
                if vocab.text(tokens[i]).contains(where: { $0.isLetter || $0.isNumber }) { n += 1 }
            }
            return n
        }

        /// Walks one continuation into the vote trie. `rename` maps the
        /// matched code's identifiers onto yours (shape matches).
        func insert(_ corpus: FamilyCorpus, from start: Int, score: Double, lines allowLines: Int, rename: [String: String]) {
            root.weight += score
            var p = start, lines = 0, steps = 0, sawContent = false, leading = 0
            var level = indent
            // Collect first, so a suggestion that would use an unknown name can be
            // cut back to its last complete line instead of ending mid-thought.
            var sequence: [Int32] = []
            var definedHere = Set<String>()
            var previousWord = ""
            var lineOpener = lineSeed.opener
            var lineHasFunc = lineSeed.hasFunc
            var parens = lineSeed.parens
            var lineIsDefinition = false
            var inString: Character?
            var inComment = false
            var truncated = false
            defer {
                if truncated {
                    if let lastNewline = sequence.lastIndex(where: { vocab.isNewline($0) }),
                       sequence[..<lastNewline].contains(where: { !vocab.isNewline($0) }) {
                        sequence = Array(sequence[..<lastNewline])
                    } else {
                        sequence = []
                    }
                }
                if !sequence.isEmpty {
                    var node = root
                    for sym in sequence {
                        let child = node.children[sym] ?? Node()
                        node.children[sym] = child
                        node = child
                        node.weight += score
                    }
                }
            }
            while p < corpus.tokens.count, steps < 64 {
                var sym = corpus.tokens[p]
                if sym == 0 { break }
                if vocab.isNewline(sym) {
                    // Blank lines end a thought (a function, a block): stop there
                    // instead of running on into unrelated code.
                    // (Your own code may continue past one blank line into the next
                    // definition; the built-in library never does.)
                    if case .some(.none) = vocab.newlineDelta(sym) {
                        // Inside a block (a class body) the code continues after a blank
                        // line; at the top level a blank line ends the suggestion.
                        var continuesBlock = false
                        if p + 1 < corpus.tokens.count, let next = vocab.newlineDelta(corpus.tokens[p + 1]), let d = next {
                            continuesBlock = level + d > 0
                        }
                        if !continuesBlock && (sawContent || corpus.isLibrary || leading >= 2) { break }
                    } else if let d = vocab.newlineDelta(sym), let d {
                        level += d
                    }
                    if sawContent {
                        lines += 1
                        if lines >= allowLines { break }
                    } else {
                        // A suggestion may begin on the next line (caret at line end).
                        leading += 1
                        if leading > 2 { break }
                    }
                } else {
                    sawContent = true
                    if !rename.isEmpty {
                        let text = vocab.text(sym)
                        let spaced = text.hasPrefix(" ")
                        let word = spaced ? String(text.dropFirst()) : text
                        if let mapped = rename[word] { sym = vocab.id(spaced ? " " + mapped : mapped) }
                    }
                    let text = vocab.text(sym)
                    let bare = text.trimmingCharacters(in: .whitespaces)
                    // Strings and comments can say anything.
                    if let q = inString {
                        if bare.contains(q) { inString = nil }
                    } else if bare == "\"" || bare == "'" || bare == "`" || bare == "f\"" {
                        inString = bare.last
                    } else if bare == "#" || bare == "//" {
                        inComment = true
                    }
                    if corpus.isLibrary, isWordSymbol(text), inString == nil, !inComment {
                        let word = text.trimmingCharacters(in: .whitespaces)
                        let afterDot = previousWord == "." || previousWord == "?." || previousWord == "->" || previousWord == "::"
                        let nextText = p + 1 < corpus.tokens.count ? vocab.text(corpus.tokens[p + 1]).trimmingCharacters(in: .whitespaces) : ""
                        // Parameters of a function being defined on this line.
                        let inSignature = parens > 0 && (lineHasFunc || lineIsDefinition || Self.definers.contains(lineOpener) || Self.modifiers.contains(lineOpener))
                        // A method/function name: first word of a line like `name(...) {` or `name(...):`.
                        var opensDefinition = false
                        if lineOpener.isEmpty, nextText == "(" {
                            var q = p + 1
                            var last = ""
                            while q < corpus.tokens.count, corpus.tokens[q] > 0, !vocab.isNewline(corpus.tokens[q]) {
                                last = vocab.text(corpus.tokens[q]).trimmingCharacters(in: .whitespaces)
                                q += 1
                            }
                            opensDefinition = last == "{" || last == ":"
                            if opensDefinition { lineIsDefinition = true }
                        }
                        let defines = Self.definers.contains(previousWord) || Self.functionWords.contains(previousWord) || opensDefinition
                            || nextText == "=" || nextText == ":="
                            || (inSignature && (nextText == "," || nextText == ")" || nextText == ":" || nextText == "="))
                        if defines { definedHere.insert(word) }
                        if !(afterDot || defines || knownNames.contains(word) || definedHere.contains(word)) {
                            truncated = true
                            break
                        }
                    }
                    let trimmedText = text.trimmingCharacters(in: .whitespaces)
                    if lineOpener.isEmpty { lineOpener = trimmedText }
                    if Self.functionWords.contains(trimmedText) { lineHasFunc = true }
                    if trimmedText.contains("(") { parens += 1 }
                    if trimmedText.contains(")") { parens = max(0, parens - 1) }
                }
                if vocab.isNewline(sym) {
                    lineOpener = ""; lineHasFunc = false; parens = 0; lineIsDefinition = false; inComment = false
                    if inString != "`" { inString = nil }   // only template literals span lines
                }
                previousWord = vocab.text(sym).trimmingCharacters(in: .whitespaces)
                sequence.append(sym)
                p += 1
                steps += 1
            }
        }

        // Exact matches on the last few symbols.
        if !context.isEmpty {
            for order in [6, 3, 1] where context.count >= order {
                let tail = Array(context.suffix(order))
                guard !tail.contains(where: { $0 <= 0 }) else { continue }
                let h = FamilyCorpus.hash(tail[...], order: order)
                for (corpus, weight) in sources {
                    for pos in corpus.positions(hash: h, order: order, limit: 600) {
                        var length = 0
                        while length < 48 {
                            let ci = context.count - 1 - length
                            let ti = pos - 1 - length
                            guard ci >= 0, ti >= 0 else { break }
                            let t = corpus.tokens[ti]
                            if t == 0 || t != context[ci] { break }
                            length += 1
                        }
                        guard length >= order else { continue }   // hash collision
                        if let prefixSymbol {
                            guard pos < corpus.tokens.count, corpus.tokens[pos] > 0,
                                  vocab.text(corpus.tokens[pos]).hasPrefix(prefixSymbol) else { continue }
                        }
                        strongest = max(strongest, length)
                        informative = max(informative, wordsIn(corpus.tokens, from: pos, length: length))
                        candidates += 1
                        insert(corpus, from: pos, score: pow(Double(length), exponent) * weight,
                               lines: length >= 10 ? 6 : length >= 7 ? 3 : 1, rename: [:])
                    }
                }
                // Back off to shorter contexts only when longer ones found nothing:
                // one real match beats hundreds of one-symbol coincidences.
                if candidates > 0 { break }
            }
        }

        // Shape matches: same structure, different names. `export function ___(`
        // or `for ___ in range(` still predict what usually follows, renamed.
        if strongest < mode.minExact, prefixSymbol == nil, !context.isEmpty {
            let shape = context.map { vocab.skeleton($0) }
            var shapeStrongest = 0, shapeCandidates = 0
            for order in [6, 3] where shape.count >= order {
                let h = FamilyCorpus.hash(shape.suffix(order)[...], order: order + 100)
                for (corpus, weight) in sources {
                    for pos in corpus.positions(hash: h, order: order, limit: 400, shape: true) {
                        var length = 0
                        var rename: [String: String] = [:]
                        while length < 48 {
                            let ci = shape.count - 1 - length
                            let ti = pos - 1 - length
                            guard ci >= 0, ti >= 0 else { break }
                            let t = corpus.shapeTokens[ti]
                            if t == 0 || t != shape[ci] { break }
                            let theirs = corpus.tokens[ti], ours = context[ci]
                            if theirs != ours {
                                let a = vocab.text(theirs), b = vocab.text(ours)
                                if isWordSymbol(a), isWordSymbol(b) {
                                    rename[a.trimmingCharacters(in: .whitespaces)] = b.trimmingCharacters(in: .whitespaces)
                                }
                            }
                            length += 1
                        }
                        guard length >= max(order, mode.minShape) else { continue }
                        shapeStrongest = max(shapeStrongest, length)
                        informative = max(informative, wordsIn(corpus.tokens, from: pos, length: length))
                        shapeCandidates += 1
                        insert(corpus, from: pos, score: pow(Double(length), exponent) * weight * 0.5,
                               lines: length >= 8 ? 4 : length >= 5 ? 2 : 1, rename: rename)
                    }
                }
                if shapeCandidates > 0 { break }
            }
            if shapeCandidates > 0 && shapeStrongest >= mode.minShape {
                candidates += shapeCandidates
                strongest = max(strongest, mode.minExact)
            }
        }

        guard candidates > 0 else { return nil }
        // On a fresh line, guessing needs more evidence than mid-line.
        let freshLine = context.last.map { vocab.isNewline($0) } ?? false
        let weak = strongest < mode.minExact + (freshLine ? 1 : 0) || (freshLine && informative < 2)
        if weak && prefixSymbol == nil { return nil }

        // Descend while the matches agree.
        var out: [Int32] = []
        var node = root
        while let (sym, child) = node.children.max(by: { $0.value.weight < $1.value.weight }) {
            // Candidates that end here ("the function is over") vote for stopping.
            let endWeight = node.weight - node.children.values.reduce(0) { $0 + $1.weight }
            if endWeight > child.weight { break }
            let share = child.weight / max(node.weight, 0.0001)
            // A word that's already complete ("return") isn't a decision; the next symbol is.
            let firstDecision = out.isEmpty || (out.count == 1 && prefixSymbol != nil && vocab.text(out[0]) == prefixSymbol)
            if share < (firstDecision ? mode.firstShare : mode.nextShare) { break }
            out.append(sym)
            node = child
            if weak { break }   // weak evidence only finishes the word
        }
        while let last = out.last, vocab.isNewline(last) { out.removeLast() }
        guard out.contains(where: { !vocab.isNewline($0) }) else { return nil }
        // Proposing a whole next line needs more evidence than finishing this one.
        if let first = out.first, vocab.isNewline(first), informative < 2 { return nil }
        if let first = out.first, vocab.isNewline(first), mode.minExact < Mode.strict.minExact {
            // A line that opens a block ("{" or ":") naturally continues below it.
            let needed = (mode.firstShare == 0 ? 5 : mode.minExact + 1) - (opensBlock ? 1 : 0)
            if strongest < needed { return nil }
        }
        return render(out, indent: indent)
    }

    private func render(_ symbols: [Int32], indent: Int) -> String {
        var s = ""
        var level = indent
        for sym in symbols {
            if let delta = vocab.newlineDelta(sym) {
                if let delta { level = max(0, level + delta) }
                s += "\n" + (delta == nil ? "" : String(repeating: " ", count: level))
            } else {
                s += vocab.text(sym)
            }
        }
        return s
    }

    private func finalize(_ text: String, prefixSymbol: String?, rest: String, lineBefore: String) -> String? {
        var t = text
        if let prefixSymbol {
            guard t.hasPrefix(prefixSymbol) else { return nil }
            t = String(t.dropFirst(prefixSymbol.count))
        }
        // Suggesting the next line on an empty line would leave a blank line.
        if lineBefore.trimmingCharacters(in: .whitespaces).isEmpty, t.hasPrefix("\n") {
            t = String(t.drop(while: { $0 == "\n" }).drop(while: { $0 == " " }))
        }
        // Text already to the right of the caret shouldn't be suggested again.
        if !rest.isEmpty {
            if let range = t.range(of: rest, options: .backwards), range.upperBound == t.endIndex || t[range.upperBound...].allSatisfy(\.isWhitespace) {
                t = String(t[..<range.lowerBound])
            }
        }
        while let last = t.last, last == " " || last == "\t" || last == "\n" { t.removeLast() }
        guard !t.isEmpty, t.contains(where: { !$0.isWhitespace }) else { return nil }
        return t
    }

    private func completeWord(prefix: String, sources: [(corpus: FamilyCorpus, weight: Double)]) -> String? {
        var best: (String, Double)?
        for (corpus, weight) in sources {
            for (sym, count) in corpus.identifierCounts {
                let word = vocab.text(sym).trimmingCharacters(in: .whitespaces)
                guard word.count > prefix.count, word.hasPrefix(prefix) else { continue }
                let score = Double(count) * weight / Double(word.count - prefix.count + 4)
                if best == nil || score > best!.1 { best = (word, score) }
            }
        }
        guard let (word, _) = best else { return nil }
        return String(word.dropFirst(prefix.count))
    }

    // MARK: Structural fallback

    private static let semicolonFamilies: Set<String> = ["c", "js", "java", "csharp", "php", "dart", "rust", "solidity"]
    private static let braceFamilies: Set<String> = ["c", "js", "java", "csharp", "php", "dart", "rust", "swift", "go", "kotlin", "scala", "solidity", "zig", "groovy"]
    private static let blockKeywords: Set<String> = ["if", "elif", "else", "for", "while", "def", "class", "with", "try", "except", "finally", "async", "match", "case", "switch", "catch", "do", "func", "function", "fn", "struct", "enum", "interface", "guard", "repeat"]
    private static let typeLead: Set<String> = ["int", "void", "char", "float", "double", "bool", "long", "short", "unsigned", "static", "public", "private", "protected", "func", "function", "fn", "def", "auto", "String", "boolean", "size_t", "const", "inline", "override", "async", "export", "struct", "class", "extern"]

    /// When nothing was learned: close open brackets and end the line —
    /// `:` for Python blocks, ` {` for C-like blocks, `;` for statements.
    private func structural(lineBefore: String, family: String, rest: String) -> String? {
        let trimmed = lineBefore.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // A block was just opened; what comes next is content, not closers.
        if let last = trimmed.last, "{([".contains(last), !rest.isEmpty || last == "{" { return nil }
        let python = family == "python"
        var stack: [Character] = []
        var quote: Character?
        var previous: Character = " "
        for ch in trimmed {
            if let q = quote {
                if ch == q && previous != "\\" { quote = nil }
            } else if ch == "\"" || ch == "'" || ch == "`" {
                quote = ch
            } else if python && ch == "#" {
                break
            } else if !python && ch == "/" && previous == "/" {
                return nil   // inside a comment
            } else if "([{".contains(ch) {
                stack.append(ch)
            } else if let last = stack.last, (ch == ")" && last == "(") || (ch == "]" && last == "[") || (ch == "}" && last == "{") {
                stack.removeLast()
            }
            previous = ch
        }
        guard quote == nil else { return nil }
        let closers = String(stack.reversed().map { $0 == "(" ? ")" : $0 == "[" ? "]" : "}" })
        let firstWord = String(trimmed.prefix { $0.isLetter || $0 == "_" })
        let isBlock = Self.blockKeywords.contains(firstWord) || (firstWord == "else" )
        let line = trimmed + closers
        var suggestion = closers

        if python {
            if isBlock && !line.hasSuffix(":") { suggestion += ":" }
        } else if Self.braceFamilies.contains(family) {
            let looksLikeDefinition = Self.typeLead.contains(firstWord) && trimmed.contains("(") && !trimmed.contains("=")
            if (isBlock || looksLikeDefinition) && !line.hasSuffix("{") && !line.hasSuffix(";") {
                suggestion += " {"
            } else if Self.semicolonFamilies.contains(family), !line.hasSuffix(";"), !line.hasSuffix("{"), !line.hasSuffix("}"),
                      !line.hasSuffix(","), !line.hasSuffix(":"), let last = line.last, !"+-*/%=&|<>!?.".contains(last),
                      !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//"), !trimmed.hasPrefix("@") {
                suggestion += ";"
            }
        }
        if !rest.isEmpty, suggestion.hasPrefix(rest), suggestion.count == rest.count { return nil }
        return suggestion.isEmpty ? nil : suggestion
    }

    static func indentWidth(_ units: [UInt16], lineStart: Int, lineEnd: Int, indentUnit: Int) -> Int {
        var n = 0
        var i = lineStart
        while i < lineEnd {
            if units[i] == 32 { n += 1 } else if units[i] == 9 { n += indentUnit } else { break }
            i += 1
        }
        return n
    }

    // MARK: Built-in library

    private var starters: [String: FamilyCorpus] = [:]
    private var startersLoaded: Set<String> = []

    static let starterFiles: [String: [String]] = [
        "python": ["python.py"], "js": ["javascript.js", "typescript.ts"], "c": ["c.c"], "cpp": ["cpp.cpp", "c.c"],
        "java": ["java.java"], "swift": ["swift.swift"],
    ]

    static let corpusDirectory: URL? = {
        if let path = ProcessInfo.processInfo.environment["HALO_FILL_CORPUS"] { return URL(fileURLWithPath: path) }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("FillCorpus"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/FillCorpus")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }()

    private func starterCorpus(_ family: String) -> FamilyCorpus? {
        if !startersLoaded.contains(family) {
            startersLoaded.insert(family)
            var corpus = FamilyCorpus()
            corpus.isLibrary = true
            for name in Self.starterFiles[family] ?? [] {
                guard let url = Self.corpusDirectory?.appendingPathComponent(name),
                      let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                corpus.files["library:" + name] = Tokenizer.tokenize(Array(text.utf16), vocab: &vocab)
            }
            if !corpus.files.isEmpty {
                corpus.rebuild(vocab: &vocab)
                starters[family] = corpus
            }
        }
        return starters[family]
    }
}

// MARK: - Vocabulary

struct Vocabulary {
    private var ids: [String: Int32] = [:]
    private var texts: [String] = ["\u{0}"]           // id 0 = file boundary
    private var deltas: [Int32: Int?] = [:]          // newline symbols → indent delta (nil = blank line)

    mutating func id(_ text: String) -> Int32 {
        if let id = ids[text] { return id }
        let id = Int32(texts.count)
        texts.append(text)
        ids[text] = id
        if text.hasPrefix("\u{23CE}") {
            let rest = text.dropFirst()
            deltas[id] = rest == "=" ? .some(nil) : .some(Int(rest))
        }
        return id
    }

    func text(_ id: Int32) -> String { Int(id) < texts.count ? texts[Int(id)] : "" }

    private var shapes: [Int32: Int32] = [:]

    /// Identifiers collapse to a placeholder (keeping their leading space);
    /// keywords, punctuation and newlines stay as they are.
    mutating func skeleton(_ id: Int32) -> Int32 {
        if id <= 0 { return id }
        if let cached = shapes[id] { return cached }
        let t = text(id)
        let spaced = t.hasPrefix(" ")
        let word = spaced ? String(t.dropFirst()) : t
        var result = id
        if let first = word.unicodeScalars.first, first == "_" || first == "$" || CharacterSet.letters.contains(first),
           !Self.keywords.contains(word) {
            result = self.id(spaced ? " \u{2022}id" : "\u{2022}id")
        } else if let first = word.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
            result = self.id(spaced ? " \u{2022}num" : "\u{2022}num")
        }
        shapes[id] = result
        return result
    }

    static let keywords: Set<String> = [
        "if", "else", "elif", "for", "while", "do", "return", "break", "continue", "switch", "case", "default", "match",
        "try", "catch", "finally", "throw", "throws", "raise", "except", "with", "as", "in", "is", "not", "and", "or",
        "function", "func", "fn", "def", "lambda", "class", "struct", "enum", "interface", "protocol", "trait", "impl",
        "extension", "type", "typealias", "typedef", "let", "var", "const", "val", "static", "final", "public", "private",
        "protected", "internal", "fileprivate", "open", "export", "import", "from", "package", "module", "use", "using",
        "namespace", "include", "require", "new", "delete", "this", "self", "super", "true", "false", "null", "nil",
        "None", "True", "False", "undefined", "void", "int", "float", "double", "char", "bool", "string", "String",
        "async", "await", "yield", "guard", "defer", "where", "override", "mutating", "inout", "pub", "mut", "ref",
        "extends", "implements", "abstract", "virtual", "unsigned", "signed", "long", "short", "auto", "sizeof",
        "end", "then", "begin", "local", "print", "printf", "console", "log", "len", "range", "init",
    ]
    func isNewline(_ id: Int32) -> Bool { deltas[id] != nil }
    /// `nil` → not a newline. `.some(nil)` → blank line. `.some(d)` → indent change.
    func newlineDelta(_ id: Int32) -> Int?? { deltas[id] }
}

// MARK: - Tokenizer

enum Tokenizer {
    static func isIdent(_ c: UInt16) -> Bool {
        (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 || c == 36 || c > 127
    }
    static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }

    private static let ops3: Set<String> = ["===", "!==", "...", "<<=", ">>=", "**=", "??=", "..<", "<=>"]
    private static let ops2: Set<String> = ["==", "!=", "<=", ">=", "&&", "||", "->", "=>", "::", "+=", "-=", "*=", "/=", "%=",
                                            "&=", "|=", "^=", "<<", ">>", "++", "--", "??", "?.", "..", ":=", "**", "//", "/*", "*/", "#!", "<-"]

    /// Symbols carry their own leading space (" foo" vs "foo"), so rendering
    /// a prediction reproduces the spacing it was learned with. Newlines carry
    /// the indentation change of the next line.
    static func tokenize(_ u: [UInt16], vocab: inout Vocabulary, startsMidFile: Bool = false) -> [Int32] {
        var out: [Int32] = []
        out.reserveCapacity(u.count / 4)
        var i = 0
        var space = false
        var lineIndent = 0
        // Measure the first line's indentation.
        while i < u.count, u[i] == 32 || u[i] == 9 { lineIndent += u[i] == 9 ? 4 : 1; i += 1 }
        if startsMidFile {
            // Drop the (possibly cut) first line.
            while i < u.count, u[i] != 10 { i += 1 }
        }
        let n = u.count
        while i < n {
            let c = u[i]
            if c == 10 {
                // Look at the next line's indentation.
                var j = i + 1
                var indent = 0
                while j < n, u[j] == 32 || u[j] == 9 { indent += u[j] == 9 ? 4 : 1; j += 1 }
                if j < n && (u[j] == 10 || u[j] == 13) {
                    out.append(vocab.id("\u{23CE}="))
                } else {
                    out.append(vocab.id("\u{23CE}\(indent - lineIndent)"))
                    lineIndent = indent
                }
                i = j
                space = false
                continue
            }
            if c == 32 || c == 9 || c == 13 { space = true; i += 1; continue }

            let start = i
            if isIdent(c) {
                if isDigit(c) {
                    while i < n, isIdent(u[i]) || u[i] == 46 { i += 1 }
                } else {
                    while i < n, isIdent(u[i]) { i += 1 }
                }
            } else {
                i += 1
                if i + 1 < n, ops3.contains(String(utf16CodeUnits: [c, u[i], u[i + 1]], count: 3)) {
                    i += 2
                } else if i < n, ops2.contains(String(utf16CodeUnits: [c, u[i]], count: 2)) {
                    i += 1
                }
            }
            let text = String(utf16CodeUnits: Array(u[start..<i]), count: i - start)
            out.append(vocab.id(space ? " " + text : text))
            space = false
        }
        return out
    }
}

// MARK: - Corpus + k-gram index

struct FamilyCorpus {
    struct Entry { var hash: UInt64; var pos: Int32 }

    var files: [String: [Int32]] = [:]
    var isLibrary = false
    private(set) var tokens: [Int32] = []
    private(set) var fileRanges: [String: Range<Int>] = [:]
    private var indexes: [Int: [Entry]] = [:]
    private var shapeIndexes: [Int: [Entry]] = [:]
    private(set) var shapeTokens: [Int32] = []
    private(set) var identifierCounts: [Int32: Int32] = [:]
    private var excluded: Range<Int>?

    static let orders = [1, 3, 6]

    mutating func rebuild(vocab: inout Vocabulary) {
        tokens = [0]
        fileRanges = [:]
        for (path, toks) in files {
            let start = tokens.count
            tokens.append(contentsOf: toks)
            fileRanges[path] = start..<tokens.count
            tokens.append(0)
        }
        indexes = [:]
        for order in Self.orders {
            var entries: [Entry] = []
            entries.reserveCapacity(tokens.count)
            var i = order
            while i < tokens.count {
                let window = tokens[(i - order)..<i]
                if !window.contains(0) {
                    entries.append(Entry(hash: Self.hash(window, order: order), pos: Int32(i)))
                }
                i += 1
            }
            entries.sort { $0.hash != $1.hash ? $0.hash < $1.hash : $0.pos < $1.pos }
            indexes[order] = entries
        }
        var counts: [Int32: Int32] = [:]
        for t in tokens where t > 0 { counts[t, default: 0] += 1 }
        identifierCounts = counts

        shapeTokens = tokens.map { vocab.skeleton($0) }
        shapeIndexes = [:]
        for order in [3, 6] {
            var entries: [Entry] = []
            entries.reserveCapacity(shapeTokens.count)
            var i = order
            while i < shapeTokens.count {
                let window = shapeTokens[(i - order)..<i]
                if !window.contains(0) { entries.append(Entry(hash: Self.hash(window, order: order + 100), pos: Int32(i))) }
                i += 1
            }
            entries.sort { $0.hash != $1.hash ? $0.hash < $1.hash : $0.pos < $1.pos }
            shapeIndexes[order] = entries
        }
    }

    /// A view that ignores one file (the saved copy of the open buffer).
    func excluding(_ path: String?) -> FamilyCorpus {
        guard let path, let range = fileRanges[path] else { return self }
        var copy = self
        copy.excluded = range
        return copy
    }

    static func hash(_ window: ArraySlice<Int32>, order: Int) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325 &+ UInt64(order) &* 0x9E3779B97F4A7C15
        for t in window {
            h ^= UInt64(UInt32(bitPattern: t))
            h = h &* 0x100000001b3
        }
        return h
    }

    /// Positions (index of the symbol right after the k-gram), most recent last.
    func positions(hash: UInt64, order: Int, limit: Int, shape: Bool = false) -> [Int] {
        guard let entries = (shape ? shapeIndexes : indexes)[order], !entries.isEmpty else { return [] }
        var lo = 0, hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].hash < hash { lo = mid + 1 } else { hi = mid }
        }
        var out: [Int] = []
        var i = lo
        while i < entries.count, entries[i].hash == hash {
            let p = Int(entries[i].pos)
            if excluded?.contains(p) != true { out.append(p) }
            i += 1
        }
        if out.count > limit { out = Array(out.suffix(limit)) }
        return out
    }
}
