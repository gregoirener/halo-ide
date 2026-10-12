import Foundation

/// A mistake Halo can fix: replace `range` with `replacement`.
struct CodeFix: Hashable, Sendable {
    var range: NSRange
    var replacement: String
    var why: String
    /// Safe to apply the moment it's typed (otherwise it's only suggested).
    var auto: Bool
    var rule: String
    var original: String
    /// Where to show it — the mistake itself, even when the fix (an import) goes elsewhere.
    var anchor: NSRange
    var insertsLine = false

    /// What the hint shows: "time.sleep", "import time".
    var label: String {
        let first = replacement.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? replacement
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "remove" }
        return replacement.contains("\n") && !insertsLine ? trimmed + " …" : trimmed
    }
}

/// Knows the mistakes people make — wrong API names, habits carried over from
/// other languages, slips of the finger — and how to fix them. Pure Foundation,
/// so tools/fixbench can run it on real code.
final class FixEngine: @unchecked Sendable {
    static let shared = FixEngine()

    private let lock = NSLock()
    private var ignored: Set<String> = []
    private lazy var knowledge = FixKnowledge.load()

    /// Fixes for this file's language, or nil when Halo has no rules for it.
    static func family(language: String, fileExtension: String) -> String? {
        switch language {
        case "python": return "python"
        case "javascript", "typescript": return "javascript"
        case "c": return "c"
        case "cpp": return ["m", "mm"].contains(fileExtension.lowercased()) ? nil : "cpp"
        case "java", "swift", "go", "rust": return language
        default: return nil
        }
    }

    /// The user undid a fix: leave that text alone from now on.
    func ignore(_ original: String) { lock.withLock { _ = ignored.insert(original) } }

    /// Every fix in the file (or only those inside `limit`), mistakes first-come.
    func fixes(in text: String, family: String, limit: NSRange? = nil, typingAt: Int? = nil) -> [CodeFix] {
        guard let knowledge = knowledge.families[family] else { return [] }
        let ignored = lock.withLock { self.ignored }
        let context = FileContext(text: text, family: family, knowledge: knowledge, wholeFile: limit == nil)
        let scope = limit ?? NSRange(location: 0, length: context.ns.length)
        if let typingAt, !context.mask.isCode(typingAt) { return [] }   // still inside a string or comment
        var found: [CodeFix] = []
        found += context.ruleFixes(in: scope)
        found += context.memberFixes(in: scope)
        found += context.typoFixes(in: scope)
        found += context.importFixes(in: scope)
        found += context.specialFixes(in: scope)

        // First fix wins where two overlap; skip what the user has rejected.
        var kept: [CodeFix] = []
        for fix in found where !ignored.contains(fix.original) && fix.replacement != fix.original {
            if kept.contains(where: { NSIntersectionRange($0.anchor, fix.anchor).length > 0 || ($0.anchor.location == fix.anchor.location) }) { continue }
            kept.append(fix)
        }
        return kept.sorted { $0.anchor.location < $1.anchor.location }
    }

    /// Characters that finish what you were typing: only then is a fix safe
    /// (`=` might become `==`, a quote opens a string that isn't done yet).
    static func isBoundary(_ c: unichar) -> Bool {
        switch c {
        case 32, 9, 10, 13, 40, 41, 91, 93, 123, 125, 44, 59, 58: return true   // space tab newline ( ) [ ] { } , ; :
        default: return false
        }
    }

    /// The fixes for what was just typed: `boundary` is where the character that
    /// finished it (space, bracket, newline…) went in. When `lineFinished` (Enter
    /// at the end of a line being written), every sure fix on that line applies.
    func justTyped(in text: String, family: String, boundary: Int, lineFinished: Bool = false) -> [CodeFix] {
        let ns = text as NSString
        guard boundary < ns.length, Self.isBoundary(ns.character(at: boundary)) else { return [] }
        let typedNewline = ns.character(at: boundary) == 10
        let line = ns.lineRange(for: NSRange(location: max(0, boundary - 1), length: 0))
        var lineEnd = NSMaxRange(line)
        while lineEnd > line.location, [10, 13].contains(ns.character(at: lineEnd - 1)) { lineEnd -= 1 }
        // What was typed since the previous boundary: the fix has to touch it.
        var chunkStart = boundary
        while chunkStart > line.location, !Self.isBoundary(ns.character(at: chunkStart - 1)) { chunkStart -= 1 }
        let found = fixes(in: text, family: family, limit: line, typingAt: boundary)
        return found.filter { fix in
            guard fix.auto, !fix.insertsLine, fix.range.location <= boundary else { return false }
            let end = NSMaxRange(fix.range)
            if lineFinished && typedNewline { return end <= boundary + 1 }
            guard end >= chunkStart - 1, end <= boundary + 2 else { return false }
            // Whole-line fixes wait for the line to be finished.
            return typedNewline || end < lineEnd || (end == lineEnd && boundary < lineEnd && fix.range.location > line.location)
        }
    }
}

// MARK: - Knowledge

final class FixKnowledge: @unchecked Sendable {
    struct Rule {
        let id: String
        let regex: NSRegularExpression
        let template: String
        let why: String
        let auto: Bool
        let undefinedGroup: Int?
        let module: String?
        let when: NSRegularExpression?
        let unless: NSRegularExpression?
        /// May reach into string literals (getElementById("#id")).
        let strings: Bool
    }

    struct Family {
        var rules: [Rule] = []
        var keywords: Set<String> = []
        var builtins: Set<String> = []
        /// Names that exist (from the SDK) but aren't worth suggesting.
        var known: Set<String> = []
        /// Module or global → its members.
        var members: [String: Set<String>] = [:]
        /// Methods and properties of the built-in types.
        var methods: Set<String> = []
        /// Every attribute name known to exist (never a typo).
        var attributes: Set<String> = []
        /// Name → the line that brings it in.
        var imports: [String: String] = [:]
    }

    let families: [String: Family]
    let problems: [String]

    private init(families: [String: Family], problems: [String]) {
        self.families = families
        self.problems = problems
    }

    static var directory: URL? {
        if let path = ProcessInfo.processInfo.environment["HALO_FIX_DATA"] { return URL(fileURLWithPath: path) }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fixes"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("rules.json").path) { return bundled }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Fixes")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    static func load(from directory: URL? = FixKnowledge.directory) -> FixKnowledge {
        guard let directory,
              let rulesData = try? Data(contentsOf: directory.appendingPathComponent("rules.json")),
              let rules = (try? JSONSerialization.jsonObject(with: rulesData)) as? [String: [String: Any]] else {
            return FixKnowledge(families: [:], problems: ["no fix data"])
        }
        let membersData = try? Data(contentsOf: directory.appendingPathComponent("members.json"))
        let members = membersData.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: [String: [String]]] } ?? [:]
        var problems: [String] = []
        var families: [String: Family] = [:]

        func regex(_ pattern: String?, id: String) -> NSRegularExpression? {
            guard let pattern else { return nil }
            do { return try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) } catch {
                problems.append("\(id): \(error.localizedDescription)")
                return nil
            }
        }

        for (name, spec) in rules {
            var family = Family()
            for raw in spec["rules"] as? [[String: Any]] ?? [] {
                let id = raw["id"] as? String ?? "?"
                guard let match = regex(raw["match"] as? String, id: id) else { continue }
                family.rules.append(Rule(id: id, regex: match, template: raw["with"] as? String ?? "", why: raw["why"] as? String ?? "",
                                         auto: raw["auto"] as? Bool ?? false, undefinedGroup: raw["undefined"] as? Int,
                                         module: raw["module"] as? String, when: regex(raw["when"] as? String, id: id + ".when"),
                                         unless: regex(raw["unless"] as? String, id: id + ".unless"), strings: raw["strings"] as? Bool ?? false))
            }
            family.keywords = Set(spec["keywords"] as? [String] ?? [])
            family.builtins = Set(spec["builtins"] as? [String] ?? [])
            family.methods = Set(spec["methods"] as? [String] ?? [])
            family.imports = spec["imports"] as? [String: String] ?? [:]
            for (root, list) in spec["members"] as? [String: [String]] ?? [:] { family.members[root] = Set(list) }

            // Generated from the Python and JavaScript runtimes and the SDK headers.
            for (key, list) in members[name] ?? [:] {
                switch key {
                case "@builtins", "@globals": family.builtins.formUnion(list)
                case "@keywords": family.keywords.formUnion(list)
                case "@known": family.known.formUnion(list)
                case "@attrs": family.attributes.formUnion(list)
                case let k where k.hasPrefix("@"): family.methods.formUnion(list.filter { !$0.hasPrefix("_") })
                default: family.members[key] = Set(list)
                }
            }
            if name == "cpp", let c = members["c"]?["@known"] { family.known.formUnion(c) }
            family.attributes.formUnion(family.methods)
            family.members.values.forEach { family.attributes.formUnion($0) }
            families[name] = family
        }
        return FixKnowledge(families: families, problems: problems)
    }
}

// MARK: - Where the code is (not strings, not comments)

struct CodeMask {
    private var skipped: [NSRange] = []

    func overlapsSkipped(_ range: NSRange) -> Bool {
        var lo = 0, hi = skipped.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = skipped[mid]
            if NSMaxRange(range) <= r.location { hi = mid - 1 } else if range.location >= NSMaxRange(r) { lo = mid + 1 } else { return true }
        }
        return false
    }

    func isCode(_ location: Int) -> Bool {
        var lo = 0, hi = skipped.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = skipped[mid]
            if location < r.location { hi = mid - 1 } else if location >= NSMaxRange(r) { lo = mid + 1 } else { return false }
        }
        return true
    }

    init(_ s: NSString, family: String) {
        let n = s.length
        var i = 0
        func at(_ k: Int) -> unichar { k < n ? s.character(at: k) : 0 }
        let slash: unichar = 47, star: unichar = 42, hash: unichar = 35, newline: unichar = 10, backslash: unichar = 92
        let dq: unichar = 34, sq: unichar = 39, bt: unichar = 96
        let python = family == "python"
        while i < n {
            let c = at(i)
            let start = i
            if python, c == hash {
                while i < n, at(i) != newline { i += 1 }
                skipped.append(NSRange(location: start, length: i - start))
                continue
            }
            if !python, c == slash, at(i + 1) == slash {
                while i < n, at(i) != newline { i += 1 }
                skipped.append(NSRange(location: start, length: i - start))
                continue
            }
            if !python, c == slash, at(i + 1) == star {
                i += 2
                while i < n, !(at(i) == star && at(i + 1) == slash) { i += 1 }
                i = min(n, i + 2)
                skipped.append(NSRange(location: start, length: i - start))
                continue
            }
            // #include <path> and "path": not code.
            if (family == "c" || family == "cpp"), c == hash {
                var k = i + 1
                while k < n, at(k) == 32 || at(k) == 9 { k += 1 }
                let word = k + 7 <= n ? s.substring(with: NSRange(location: k, length: 7)) : ""
                if word == "include" || word.hasPrefix("import") {
                    var open = k
                    while open < n, at(open) != 60, at(open) != dq, at(open) != newline { open += 1 }
                    var close = open
                    while close < n, at(close) != newline { close += 1 }
                    if open < close { skipped.append(NSRange(location: open, length: close - open)) }
                    i = close
                    continue
                }
            }
            let isQuote = c == dq || c == sq || (c == bt && (family == "javascript" || family == "go"))
            if isQuote {
                // Rust lifetimes ('a) and generic quotes that don't close nearby aren't strings.
                if family == "rust", c == sq, !(at(i + 2) == sq || (at(i + 1) == backslash && (at(i + 3) == sq || at(i + 4) == sq))) {
                    i += 1
                    continue
                }
                let triple = (python || family == "swift") && at(i + 1) == c && at(i + 2) == c
                if triple {
                    i += 3
                    while i < n, !(at(i) == c && at(i + 1) == c && at(i + 2) == c) { i += at(i) == backslash ? 2 : 1 }
                    i = min(n, i + 3)
                } else {
                    i += 1
                    let multiline = c == bt
                    while i < n, at(i) != c {
                        if at(i) == newline, !multiline { break }
                        i += at(i) == backslash && c != bt ? 2 : 1
                    }
                    i = min(n, i + 1)
                }
                // Python string prefixes (f"", rb"") belong to the string.
                var from = start
                if python {
                    while from > 0, let p = UnicodeScalar(at(from - 1)), "rRbBuUfF".unicodeScalars.contains(p),
                          from - 1 == 0 || !(CharacterSet.alphanumerics.contains(UnicodeScalar(at(from - 2)) ?? " ") || at(from - 2) == 95) { from -= 1 }
                }
                skipped.append(NSRange(location: from, length: i - from))
                continue
            }
            i += 1
        }
    }
}

// MARK: - One pass over one file

private final class FileContext {
    struct Token {
        let name: String
        let range: NSRange
        let afterDot: Bool
    }

    let text: String
    let ns: NSString
    let family: String
    let knowledge: FixKnowledge.Family
    let mask: CodeMask

    /// Scanning the whole file (counts come from one pass) or one line (counts on demand).
    let wholeFile: Bool

    init(text: String, family: String, knowledge: FixKnowledge.Family, wholeFile: Bool) {
        self.text = text
        ns = text as NSString
        self.family = family
        self.knowledge = knowledge
        self.wholeFile = wholeFile
        mask = CodeMask(text as NSString, family: family)
    }

    func tokens(in scope: NSRange) -> [Token] {
        if wholeFile { return tokens.filter { NSLocationInRange($0.range.location, scope) } }
        return Self.scanTokens(text, ns, family: family, mask: mask, range: scope)
    }

    private var countCache: [String: Int] = [:]

    /// Uses of a name (bare) or of .name (attribute) in code.
    func count(_ name: String, attribute: Bool) -> Int {
        if wholeFile { return (attribute ? attributeCounts : bareCounts)[name] ?? 0 }
        let key = (attribute ? "." : "") + name
        if let cached = countCache[key] { return cached }
        var total = 0
        var search = NSRange(location: 0, length: ns.length)
        while true {
            let r = ns.range(of: name, options: .literal, range: search)
            guard r.location != NSNotFound else { break }
            let before: unichar = r.location > 0 ? ns.character(at: r.location - 1) : 32
            let after: unichar = NSMaxRange(r) < ns.length ? ns.character(at: NSMaxRange(r)) : 32
            let isWord = { (c: unichar) -> Bool in (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 }
            if !isWord(before), !isWord(after), (before == 46) == attribute, mask.isCode(r.location) { total += 1 }
            search = NSRange(location: NSMaxRange(r), length: ns.length - NSMaxRange(r))
        }
        countCache[key] = total
        return total
    }

    var whole: NSRange { NSRange(location: 0, length: ns.length) }

    // MARK: Tokens and what the file defines

    lazy var tokens: [Token] = Self.scanTokens(text, ns, family: family, mask: mask, range: whole)

    static let wordPattern = try! NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*")
    static let jsWordPattern = try! NSRegularExpression(pattern: "[A-Za-z_$][A-Za-z0-9_$]*")

    static func scanTokens(_ text: String, _ ns: NSString, family: String, mask: CodeMask, range: NSRange) -> [Token] {
        var out: [Token] = []
        for m in (family == "javascript" ? jsWordPattern : wordPattern).matches(in: text, range: range) where mask.isCode(m.range.location) {
            let before = m.range.location > 0 ? ns.character(at: m.range.location - 1) : 0
            if before >= 48 && before <= 57 { continue }   // 0x1F, 1e10
            out.append(Token(name: ns.substring(with: m.range), range: m.range, afterDot: before == 46))
        }
        return out
    }

    lazy var bareCounts: [String: Int] = tokens.filter { !$0.afterDot }.reduce(into: [:]) { $0[$1.name, default: 0] += 1 }
    lazy var attributeCounts: [String: Int] = tokens.filter(\.afterDot).reduce(into: [:]) { $0[$1.name, default: 0] += 1 }

    /// Names the file defines, where (token start), and which came only from `import x`.
    lazy var definitions: (names: Set<String>, sites: Set<Int>, importedModules: Set<String>) = {
        var names = Set<String>()
        var sites = Set<Int>()
        var imported = Set<String>()
        let identifier = try! NSRegularExpression(pattern: family == "javascript" ? "[A-Za-z_$][\\w$]*" : "[A-Za-z_]\\w*")
        let skipWords: Set<String> = ["as", "mut", "const", "let", "var", "in", "of", "await", "async", "static", "final", "unsigned", "signed", "struct", "enum", "inout", "_"]

        func add(_ name: String, at location: Int) {
            guard !skipWords.contains(name) else { return }
            names.insert(name)
            sites.insert(location)
        }
        func identifiers(in range: NSRange) -> [(String, Int)] {
            identifier.matches(in: text, range: range).map { (ns.substring(with: $0.range), $0.range.location) }
        }
        func pieces(_ range: NSRange) -> [NSRange] {
            // Split on commas outside brackets.
            var out: [NSRange] = []
            var depth = 0, start = range.location
            for k in range.location..<NSMaxRange(range) {
                switch ns.character(at: k) {
                case 40, 91, 123, 60: depth += 1          // ( [ { <
                case 41, 93, 125, 62: depth = max(0, depth - 1)
                case 44 where depth == 0: out.append(NSRange(location: start, length: k - start)); start = k + 1
                default: break
                }
            }
            out.append(NSRange(location: start, length: NSMaxRange(range) - start))
            return out
        }

        for (pattern, mode) in Self.definitionPatterns(family) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            for m in re.matches(in: text, range: whole) where m.numberOfRanges > 1 {
                let group = m.range(at: 1)
                guard group.location != NSNotFound, mask.isCode(m.range.location) else { continue }
                switch mode {
                case .single:
                    add(ns.substring(with: group), at: group.location)
                case .all:
                    identifiers(in: group).forEach { add($0.0, at: $0.1) }
                case .imports:
                    for piece in pieces(group) {
                        let words = identifiers(in: piece)
                        if let asIndex = words.firstIndex(where: { $0.0 == "as" }), asIndex + 1 < words.count {
                            add(words[asIndex + 1].0, at: words[asIndex + 1].1)
                        } else if let first = words.first {
                            add(first.0, at: first.1)
                            if family == "python", words.count >= 1, ns.substring(with: m.range).trimmingCharacters(in: .whitespaces).hasPrefix("import") {
                                imported.insert(first.0)
                            }
                        }
                    }
                case .params(let typed):
                    for piece in pieces(group) {
                        var part = piece
                        let text = ns.substring(with: piece)
                        // Drop the default value.
                        if let eq = text.range(of: "=") { part.length = text.distance(from: text.startIndex, to: eq.lowerBound) }
                        let partText = ns.substring(with: part)
                        if partText.contains("{") || partText.contains("[") && !typed {
                            identifiers(in: part).forEach { add($0.0, at: $0.1) }
                            continue
                        }
                        if let colon = partText.range(of: ":"), !partText.contains("::") {
                            part.length = partText.distance(from: partText.startIndex, to: colon.lowerBound)
                            if family == "swift" { identifiers(in: part).forEach { add($0.0, at: $0.1) } }
                            else if let last = identifiers(in: part).last { add(last.0, at: last.1) }
                        } else if typed, let last = identifiers(in: part).last {
                            add(last.0, at: last.1)
                        } else if let first = identifiers(in: part).first(where: { !skipWords.contains($0.0) }) {
                            add(first.0, at: first.1)
                        }
                    }
                }
            }
        }
        return (names, sites, imported)
    }()

    enum Extract { case single, all, imports, params(typed: Bool) }

    static func definitionPatterns(_ family: String) -> [(String, Extract)] {
        let assign: (String, Extract) = (#"(?<![\w.$])([A-Za-z_$][\w$]*)[ \t]*(?:[-+*/%|&^]|<<|>>|\*\*|//)?=(?![=>])"#, .single)
        switch family {
        case "python":
            return [(#"^[ \t]*(?:async[ \t]+)?def[ \t]+([A-Za-z_]\w*)"#, .single), (#"^[ \t]*class[ \t]+([A-Za-z_]\w*)"#, .single),
                    (#"([A-Za-z_]\w*)[ \t]*:="#, .single), (#"^[ \t]*(?:async[ \t]+)?def[ \t]+\w+[ \t]*\(([^)]*)\)"#, .params(typed: false)),
                    (#"\blambda\b([^:\n]*):"#, .params(typed: false)), (#"^[ \t]*import[ \t]+([^\n#;]+)"#, .imports),
                    (#"^[ \t]*from[ \t]+[\w.]+[ \t]+import[ \t]+\(?([^)#;]+?)\)?[ \t]*(?:#.*)?$"#, .imports),
                    (#"^[ \t]*from[ \t]+[\w.]+[ \t]+import[ \t]*\(([^)]*)\)"#, .imports),
                    (#"\bfor[ \t]+([\w, ()\[\]]+?)[ \t]+in\b"#, .all), (#"\bas[ \t]+([A-Za-z_]\w*)"#, .single),
                    (#"^[ \t]*(?:global|nonlocal)[ \t]+([\w, ]+)"#, .all),
                    (#"^[ \t]*([A-Za-z_]\w*(?:[ \t]*,[ \t]*[A-Za-z_]\w*)+)[ \t]*="#, .all),
                    (#"^[ \t]*([A-Za-z_]\w*)[ \t]*:[^=\n]+="#, .single), (#"^[ \t]*[\[(]([\w, *]+)[\])][ \t]*=(?!=)"#, .all), assign]
        case "javascript":
            return [(#"\b(?:function\*?|class|let|const|var)[ \t]+([A-Za-z_$][\w$]*)"#, .single), assign,
                    (#"(?<![\w$.])([A-Za-z_$][\w$]*)[ \t]*=>"#, .single),
                    (#"^[ \t]*(?:static[ \t]+|async[ \t]+|get[ \t]+|set[ \t]+|public[ \t]+|private[ \t]+|protected[ \t]+)*([A-Za-z_$][\w$]*)[ \t]*\([^)\n]*\)[ \t]*(?::[^{\n]+)?\{"#, .single),
                    (#"catch[ \t]*\([ \t]*([A-Za-z_$][\w$]*)"#, .single), (#"\bimport[ \t]+([A-Za-z_$][\w$]*)[ \t]*(?:,|from)"#, .single),
                    (#"\bas[ \t]+([A-Za-z_$][\w$]*)"#, .single), (#"\bfunction\*?[ \t]*[\w$]*[ \t]*\(([^)]*)\)"#, .params(typed: false)),
                    (#"\(([^()]*)\)[ \t]*(?::[^=\n]+)?=>"#, .params(typed: false)),
                    (#"^[ \t]*(?:async[ \t]+)?[A-Za-z_$][\w$]*[ \t]*\(([^)]*)\)[ \t]*(?::[^{\n]+)?\{"#, .params(typed: false)),
                    (#"\b(?:let|const|var)[ \t]*[{\[]([^}\]]*)[}\]]"#, .all), (#"\bimport[ \t]*(?:[\w$]+[ \t]*,[ \t]*)?\{([^}]*)\}"#, .all),
                    (#"\b(?:interface|type|enum|namespace)[ \t]+([A-Za-z_$][\w$]*)"#, .single),
                    (#"^[ \t]*(?:readonly[ \t]+|public[ \t]+|private[ \t]+|protected[ \t]+|static[ \t]+)*([A-Za-z_$][\w$]*)[ \t]*[?!]?:[ \t]*[\w$<{\[(]"#, .single)]
        case "c", "cpp":
            return [(#"\b(?:int|char|float|double|void|long|short|unsigned|signed|bool|_Bool|size_t|ssize_t|auto|FILE|[A-Za-z_]\w*_t|struct[ \t]+\w+|enum[ \t]+\w+|union[ \t]+\w+|const[ \t]+\w+|std::\w+(?:<[^;(){}]*>)?|[A-Z]\w*(?:<[^;(){}]*>)?|string|vector<[^;(){}]*>|map<[^;(){}]*>)[ \t*&]+([A-Za-z_]\w*)"#, .single),
                    (#",[ \t*&]*([A-Za-z_]\w*)[ \t]*(?=[=\[;,])"#, .single), (#"#[ \t]*define[ \t]+([A-Za-z_]\w*)"#, .single),
                    (#"\btypedef\b[^;]*?\b([A-Za-z_]\w*)[ \t]*;"#, .single), (#"\}[ \t]*([A-Za-z_]\w*)[ \t]*;"#, .single),
                    (#"\benum\b[^{;]*\{([^}]*)\}"#, .all), assign,
                    (#"\b(?:class|struct|namespace|union|enum(?:[ \t]+class)?)[ \t]+([A-Za-z_]\w*)"#, .single),
                    (#"\busing[ \t]+([A-Za-z_]\w*)[ \t]*="#, .single), (#"\btemplate[ \t]*<([^>]*)>"#, .params(typed: true)),
                    (#"for[ \t]*\([^;:)]*?([A-Za-z_]\w*)[ \t]*:(?!:)"#, .single), (#"\[([^\]]*)\][ \t]*\("#, .all),
                    (#"\b[A-Za-z_]\w*[ \t]*\(([^()]*)\)[ \t]*(?:const[ \t]*)?(?:\{|;|$)"#, .params(typed: true)),
                    (#"^[ \t]*([A-Za-z_]\w*)[ \t]*:[ \t]*$"#, .single)]
        case "java":
            return [(#"\b(?:class|interface|enum|record)[ \t]+([A-Za-z_]\w*)"#, .single),
                    (#"\b(?:[A-Z]\w*(?:<[^;(){}=]*>)?(?:\[\])*|int|long|short|byte|char|float|double|boolean|var|void)(?:\[\])*[ \t]+([a-zA-Z_]\w*)[ \t]*[=;,:)(]"#, .single),
                    assign, (#"([A-Za-z_]\w*)[ \t]*->"#, .single), (#"\(([^()]*)\)[ \t]*->"#, .params(typed: false)),
                    (#"catch[ \t]*\([^)]*?([A-Za-z_]\w*)[ \t]*\)"#, .single),
                    (#"\b\w+[ \t]*\(([^()]*)\)[ \t]*(?:throws[^{]*)?\{"#, .params(typed: true))]
        case "swift":
            return [(#"\b(?:func|let|var|class|struct|enum|protocol|typealias|actor|case|associatedtype)[ \t]+([A-Za-z_]\w*)"#, .single),
                    (#"\b(?:if|guard|while)[ \t]+(?:let|var)[ \t]+([A-Za-z_]\w*)"#, .single),
                    (#"\bfor[ \t]+(?:case[ \t]+let[ \t]+)?\(?([\w, ]+?)\)?[ \t]+in\b"#, .all),
                    (#"\{[ \t]*(?:\[[^\]]*\][ \t]*)?\(?([\w, ]+?)\)?[ \t]+in\b"#, .all),
                    (#"\bfunc[ \t]+\w+[ \t]*(?:<[^>]*>)?[ \t]*\(([^)]*)\)"#, .params(typed: false)),
                    (#"\binit[ \t]*\??[ \t]*\(([^)]*)\)"#, .params(typed: false)), assign, (#"catch[ \t]+let[ \t]+(\w+)"#, .single),
                    (#"\bcase[ \t]+([A-Za-z_][\w, ]*?)[ \t]*(?:[=:({};]|$)"#, .all)]
        case "go":
            return [(#"\bfunc[ \t]+(?:\([^)]*\)[ \t]*)?([A-Za-z_]\w*)"#, .single),
                    (#"\bfunc[ \t]*(?:\([^)]*\)[ \t]*)?\w*[ \t]*\(([^)]*)\)"#, .params(typed: false)),
                    (#"\bfunc[ \t]*\(([^)]*)\)"#, .params(typed: false)), (#"\)[ \t]*\(([^)]*)\)[ \t]*\{"#, .params(typed: false)),
                    (#"([A-Za-z_][\w, ]*?)[ \t]*:="#, .all),
                    (#"\b(?:var|const|type)[ \t]+([A-Za-z_]\w*)"#, .single), (#"\b(?:var|const)[ \t]*\(([^)]*)\)"#, .all),
                    (#"\bfor[ \t]+([\w, ]+?)[ \t]*:?=[ \t]*range"#, .all), assign,
                    (#"^[ \t]*import[ \t]+(?:\w+[ \t]+)?"(?:[^"]*/)?(\w+)""#, .single),
                    (#"^[ \t]*(?:\w+[ \t]+)?"(?:[^"\n]*/)?(\w+)"[ \t]*$"#, .single),
                    (#"^[ \t]*([A-Za-z_]\w*)[ \t]+[\w*\[\].]+[ \t]*(?:`[^`]*`)?[ \t]*$"#, .single)]
        case "rust":
            return [(#"\b(?:fn|struct|enum|trait|type|mod|const|static|let(?:[ \t]+mut)?|union)[ \t]+([A-Za-z_]\w*)"#, .single),
                    (#"\blet[ \t]+(?:mut[ \t]+)?\(([^)]*)\)"#, .all), (#"\bfn[ \t]+\w+[ \t]*(?:<[^>]*>)?[ \t]*\(([^)]*)\)"#, .params(typed: false)),
                    (#"\|([^|\n]*)\|"#, .params(typed: false)), (#"\bfor[ \t]+\(?([\w, ]+?)\)?[ \t]+in\b"#, .all),
                    (#"\b(?:Some|Ok|Err)\(([A-Za-z_]\w*)\)"#, .single), (#"\buse[ \t]+[\w:]+::\{([^}]*)\}"#, .all),
                    (#"\buse[ \t]+[\w:]*::([A-Za-z_]\w*)[ \t]*;"#, .single), (#"\bas[ \t]+([A-Za-z_]\w*)"#, .single), assign]
        default:
            return [assign]
        }
    }

    func isDefined(_ name: String) -> Bool {
        wholeFile ? definitions.names.contains(name) : quickDefinition(name).other || quickDefinition(name).imported
    }

    private var quickCache: [String: (other: Bool, imported: Bool)] = [:]

    /// Is one name defined, and how — without analysing the whole file (for keystrokes).
    func quickDefinition(_ name: String) -> (other: Bool, imported: Bool) {
        if let cached = quickCache[name] { return cached }
        let n = NSRegularExpression.escapedPattern(for: name)
        let other: String
        var imported = "(?!)"
        switch family {
        case "python":
            other = #"^[ \t]*(?:async[ \t]+)?def[ \t]+N\b|^[ \t]*class[ \t]+N\b|(?<![\w.])N[ \t]*(?:[-+*/%|&^]|<<|>>|\*\*|//)?=(?![=>])|\bfor[ \t]+[^\n:]*?(?<![\w.])N\b[^\n:]*?[ \t]+in\b|\bas[ \t]+N\b|^[ \t]*from[ \t]+[\w.]+[ \t]+import[^\n]*\bN\b|^[ \t]*(?:global|nonlocal)[ \t]+[^\n]*\bN\b|\blambda\b[^:\n]*\bN\b[^:\n]*:|^[ \t]*(?:async[ \t]+)?def[ \t]+\w+[ \t]*\([^)]*(?<![\w.])N\b|N[ \t]*:=|^[ \t]*[\[(]?[\w, *]*\bN\b[\w, *]*[\])]?[ \t]*=(?!=)"#
            imported = #"^[ \t]*import[ \t]+[^\n#]*?(?<![\w.])N\b"#
        case "javascript":
            other = #"\b(?:function\*?|class|let|const|var|interface|type|enum)[ \t]+N\b|(?<![\w$.])N[ \t]*(?:[-+*/%|&^]|<<|>>|\*\*)?=(?![=>])|(?<![\w$.])N[ \t]*=>|\bimport\b[^;]*\bN\b|\bas[ \t]+N\b|catch[ \t]*\([ \t]*N\b|[(,{][ \t]*N[ \t]*[,)=:}]|^[ \t]*(?:async[ \t]+)?N[ \t]*\([^)\n]*\)[ \t]*\{"#
        case "go":
            other = #"\bfunc[ \t]+(?:\([^)]*\)[ \t]*)?N\b|\b(?:var|const|type)[ \t]+N\b|(?<![\w.])N[ \t]*(?:,[ \t]*\w+[ \t]*)*:?=(?!=)|(?<![\w.])\w+[ \t]*,[ \t]*N[ \t]*:?=|[(,][ \t]*N[ \t]+[\w*\[]|^[ \t]*import[ \t]+(?:\w+[ \t]+)?"(?:[^"\n]*/)?N"|^[ \t]*(?:\w+[ \t]+)?"(?:[^"\n]*/)?N"[ \t]*$"#
        default:
            other = #"\b(?:def|class|function|func|fn|let|const|var|val|struct|enum|interface|type|typedef|define|union|trait|mod|static)[ \t]+(?:mut[ \t]+)?N\b|(?<![\w.$])N[ \t]*:?=(?![=>])|[\w>\]*&][ \t*&]+N[ \t]*[=;,)(\[]|#[ \t]*define[ \t]+N\b|[(,|][ \t]*N[ \t]*[,):|]|\bimport\b[^\n]*\bN\b|\buse\b[^;]*\bN\b"#
        }
        // Only the lines that mention the name are worth a regex.
        var lines: [NSRange] = []
        var search = whole
        while true {
            let hit = ns.range(of: name, options: .literal, range: search)
            guard hit.location != NSNotFound else { break }
            let line = ns.lineRange(for: hit)
            if lines.last != line { lines.append(line) }
            search = NSRange(location: NSMaxRange(line), length: ns.length - NSMaxRange(line))
            if search.length <= 0 { break }
        }
        func found(_ pattern: String) -> Bool {
            guard pattern != "(?!)" else { return false }
            guard let re = try? NSRegularExpression(pattern: pattern.replacingOccurrences(of: "N", with: n), options: .anchorsMatchLines) else { return true }
            return lines.contains { line in re.matches(in: text, range: line).contains { mask.isCode($0.range.location) } }
        }
        let result = (other: found(other), imported: found(imported))
        quickCache[name] = result
        return result
    }

    /// import/use/#include statements, whose names aren't typos or missing imports.
    lazy var importStatements: [NSRange] = {
        let pattern: String
        switch family {
        case "python": pattern = #"^[ \t]*(?:from[ \t]+[\w.]+[ \t]+import[ \t]*\([^)]*\)|(?:from|import)[ \t]+(?:[^\n]*\\\n)*[^\n]*)"#
        case "javascript": pattern = #"^[ \t]*(?:import\b[^;]*?(?:from[ \t]*["'][^"'\n]*["']|["'][^"'\n]*["'])|export\b[^\n]*\bfrom\b[^\n]*)"#
        case "java": pattern = #"^[ \t]*(?:import|package)\b[^\n]*"#
        case "go": pattern = #"^[ \t]*import[ \t]*\([^)]*\)|^[ \t]*import[^\n]*"#
        case "rust": pattern = #"^[ \t]*(?:pub[ \t]+)?use\b[^;]*;"#
        case "swift": pattern = #"^[ \t]*(?:@testable[ \t]+)?import\b[^\n]*"#
        default: pattern = #"^[ \t]*#[^\n]*"#
        }
        let re = try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        return re.matches(in: text, range: whole).map(\.range)
    }()

    func inImportStatement(_ location: Int) -> Bool { importStatements.contains { NSLocationInRange(location, $0) } }

    lazy var wildcardImport: Bool = {
        let pattern = family == "python" ? #"from\s+\S+\s+import\s+\*"# : family == "java" ? #"import\s+static\s+[\w.]+\.\*"# : "(?!)"
        return text.range(of: pattern, options: .regularExpression) != nil
    }()

    /// A name refers to the standard module, not something the file made itself.
    func isModule(_ name: String) -> Bool {
        if !wholeFile { return !quickDefinition(name).other }
        return !definitions.names.contains(name) || definitions.importedModules.contains(name)
    }

    // MARK: Python imports → modules

    lazy var pythonModules: [String: String] = {
        guard family == "python" else { return [:] }
        var aliases: [String: String] = [:]
        let known = Set(knowledge.members.keys)
        let importLine = try! NSRegularExpression(pattern: #"^[ \t]*import[ \t]+([^\n#;]+)"#, options: .anchorsMatchLines)
        for m in importLine.matches(in: text, range: whole) where mask.isCode(m.range.location) {
            for piece in ns.substring(with: m.range(at: 1)).split(separator: ",") {
                let words = piece.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard let module = words.first else { continue }
                if words.count >= 3, words[1] == "as" { aliases[words[2]] = module }
                else { aliases[String(module.split(separator: ".")[0])] = String(module.split(separator: ".")[0]) }
            }
        }
        let fromLine = try! NSRegularExpression(pattern: #"^[ \t]*from[ \t]+([\w.]+)[ \t]+import[ \t]+\(?([^)#\n]+)"#, options: .anchorsMatchLines)
        for m in fromLine.matches(in: text, range: whole) where mask.isCode(m.range.location) {
            let package = ns.substring(with: m.range(at: 1))
            for piece in ns.substring(with: m.range(at: 2)).split(separator: ",") {
                let words = piece.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard let name = words.first else { continue }
                let local = words.count >= 3 && words[1] == "as" ? words[2] : name
                if known.contains(package + "." + name) { aliases[local] = package + "." + name }
            }
        }
        return aliases
    }()

    // MARK: Rules

    func ruleFixes(in scope: NSRange) -> [CodeFix] {
        var out: [CodeFix] = []
        for rule in knowledge.rules {
            let matches = rule.regex.matches(in: text, range: scope)
            guard !matches.isEmpty else { continue }
            if let when = rule.when, when.firstMatch(in: text, range: whole) == nil { continue }
            if let unless = rule.unless, unless.firstMatch(in: text, range: whole) != nil { continue }
            if let module = rule.module, !isModule(module) { continue }
            for m in matches where m.range.length > 0 && mask.isCode(m.range.location) {
                if !rule.strings, mask.overlapsSkipped(m.range) { continue }
                if let group = rule.undefinedGroup, group < m.numberOfRanges, m.range(at: group).location != NSNotFound,
                   isDefined(ns.substring(with: m.range(at: group))) { continue }
                let original = ns.substring(with: m.range)
                let replacement = rule.regex.replacementString(for: m, in: text, offset: 0, template: rule.template)
                guard replacement != original else { continue }
                let why = rule.regex.replacementString(for: m, in: text, offset: 0, template: rule.why.replacingOccurrences(of: "\\", with: "\\\\"))
                out.append(CodeFix(range: m.range, replacement: replacement, why: why, auto: rule.auto, rule: rule.id,
                                   original: original, anchor: m.range))
            }
        }
        return out
    }

    // MARK: Module and global members (time.slep → time.sleep)

    func memberFixes(in scope: NSRange) -> [CodeFix] {
        guard !knowledge.members.isEmpty else { return [] }
        let chain = try! NSRegularExpression(pattern: #"(?<![\w.$])([A-Za-z_$][\w$]*)((?:\.[A-Za-z_$][\w$]*)+)"#)
        var out: [CodeFix] = []
        for m in chain.matches(in: text, range: scope) where mask.isCode(m.range.location) {
            let root = ns.substring(with: m.range(at: 1))
            var module: String
            switch family {
            case "python":
                guard let mapped = pythonModules[root] ?? (knowledge.members[root] != nil && isModule(root) ? root : nil) else { continue }
                module = mapped
            case "go":
                guard knowledge.members[root] != nil, isDefined(root) else { continue }   // imported packages are "defined"
                module = root
            default:
                guard knowledge.members[root] != nil, !isDefined(root) else { continue }
                module = root
            }
            // Walk submodules (os.path), then check the next name.
            var location = m.range(at: 2).location
            let parts = ns.substring(with: m.range(at: 2)).split(separator: ".").map(String.init)
            for part in parts {
                location += 1
                let partRange = NSRange(location: location, length: (part as NSString).length)
                defer { location += partRange.length }
                if knowledge.members[module + "." + part] != nil { module += "." + part; continue }
                guard let members = knowledge.members[module], !members.contains(part) else { break }
                // Assigned by the file itself (time.custom = …) is fine.
                let after = NSMaxRange(partRange)
                if after < ns.length, let next = ns.substring(from: after).first(where: { $0 != " " && $0 != "\t" }), next == "=",
                   !ns.substring(from: after).trimmingCharacters(in: .whitespaces).hasPrefix("==") { break }
                let chainText = ns.substring(with: NSRange(location: m.range.location, length: NSMaxRange(partRange) - m.range.location))
                if text.components(separatedBy: chainText).count > 2 { break }       // used twice: deliberate
                if var (candidate, auto) = Self.closest(part, in: members, strict: false) {
                    let caseOnly = part.lowercased() == candidate.lowercased()
                    if !caseOnly, family != "python" && family != "javascript" { break }
                    if Self.isEdgeEdit(part, candidate), !caseOnly { break }
                    if part == part.uppercased() { auto = auto && caseOnly }
                    let called = after < ns.length && ns.substring(from: after).trimmingCharacters(in: .whitespaces).hasPrefix("(")
                    out.append(CodeFix(range: partRange, replacement: candidate,
                                       why: "\(module) has no \(part)\(called ? "()" : ""); it's \(module).\(candidate)",
                                       auto: auto, rule: "\(family).member", original: part, anchor: partRange))
                }
                break
            }
        }
        return out
    }

    // MARK: Typos (pritn, retrun, self.nmae)

    func typoFixes(in scope: NSRange) -> [CodeFix] {
        if wildcardImport { return [] }
        let strongBare = knowledge.keywords.union(knowledge.builtins)
        let capitalizedAreTypes = ["java", "swift", "go", "javascript", "cpp", "c", "rust"].contains(family)
        var out: [CodeFix] = []

        for token in tokens(in: scope) {
            let name = token.name
            let length = (name as NSString).length
            guard length >= 4, !name.hasPrefix("_") else { continue }
            if token.afterDot {
                guard !knowledge.attributes.contains(name), count(name, attribute: true) == 1 else { continue }
            } else {
                guard !strongBare.contains(name), !knowledge.known.contains(name), knowledge.members[name] == nil,
                      knowledge.imports[name] == nil, count(name, attribute: false) == 1 else { continue }
            }
            // Suspicious: now look at the whole file.
            let defined = definitions.names
            guard !definitions.sites.contains(token.range.location), !inImportStatement(token.range.location) else { continue }
            if name == name.uppercased() { continue }                                  // CONSTANTS and MACROS
            if capitalizedAreTypes, name.first?.isUppercase == true { continue }       // types come from imports
            let next = nextCharacter(after: NSMaxRange(token.range))
            if next == "=" && !followsEquals(NSMaxRange(token.range)) { continue }       // being assigned
            if next == ":", family != "python", family != "c", family != "cpp" { continue } // object keys, labels

            if token.afterDot {
                let frequentAttributes = self.frequentAttributes
                guard !frequentAttributes.contains(name), !defined.contains(name), !receiverHasMembers(token) else { continue }
                let called = next == "("
                let candidates = (called ? knowledge.methods : []).union(frequentAttributes)
                guard let (candidate, close) = Self.closest(name, in: candidates, strict: true), !Self.distinctPair(name, candidate) else { continue }
                let builtinMethod = knowledge.methods.contains(candidate)
                let caseOnly = name.lowercased() == candidate.lowercased()
                // Only Python knows every attribute that exists; elsewhere a one-off name is usually an API Halo hasn't heard of.
                if family != "python", !(caseOnly && builtinMethod) { continue }
                if Self.isEdgeEdit(name, candidate), !caseOnly { continue }
                // Python knows every attribute that exists, so a one-letter slip on a call is safe to fix.
                let auto = caseOnly ? builtinMethod : (family == "python" && close && builtinMethod && called && length >= 5 && !Self.isEdgeEdit(name, candidate))
                out.append(CodeFix(range: token.range, replacement: candidate, why: builtinMethod ? "Did you mean .\(candidate)?" : "Did you mean .\(candidate)? (used elsewhere in this file)",
                                   auto: auto, rule: "\(family).typo.member", original: name, anchor: token.range))
                continue
            }

            guard !defined.contains(name) else { continue }
            // Keywords only where they fit; languages whose names span many files only compare with keywords.
            let fitting = keywords(at: token.range.location)
            let multiFile = ["swift", "go", "java", "rust"].contains(family)
            var candidates: Set<String> = (usesLibraries || multiFile) ? [] : knowledge.builtins.union(frequentBare)
            candidates.formUnion(fitting)
            guard !candidates.isEmpty else { continue }
            if !fitting.isEmpty, restOfLineIsEmpty(after: NSMaxRange(token.range)), !lineIsFinished(at: token.range.location) { continue }
            guard let (candidate, close) = Self.closest(name, in: candidates, strict: true), close || name.lowercased() == candidate.lowercased(),
                  !Self.distinctPair(name, candidate), !Self.isEdgeEdit(name, candidate) else { continue }
            let strong = knowledge.keywords.contains(candidate) || knowledge.builtins.contains(candidate)
            // VerifyFlags vs verify_flags, Value vs value: two names, not a slip.
            if !strong, name.lowercased().replacingOccurrences(of: "_", with: "") == candidate.lowercased().replacingOccurrences(of: "_", with: "") { continue }
            out.append(CodeFix(range: token.range, replacement: candidate, why: "Did you mean \(candidate)?",
                               auto: close && candidate.count >= 4 && (multiFile ? knowledge.keywords.contains(candidate) : (strong || count(candidate, attribute: false) >= 2)),
                               rule: "\(family).typo", original: name, anchor: token.range))
        }
        return out
    }

    /// C and C++ files that include non-standard headers get most names (and
    /// standard headers) from places Halo can't see.
    lazy var usesLibraries: Bool = {
        guard family == "c" || family == "cpp" else { return false }
        let include = try! NSRegularExpression(pattern: #"^[ \t]*#[ \t]*include[ \t]*([<"])([^>"\n]+)[>"]"#, options: .anchorsMatchLines)
        let standard: Set<String> = ["stdio.h", "stdlib.h", "string.h", "math.h", "time.h", "ctype.h", "stdbool.h", "stdint.h", "limits.h", "assert.h",
            "errno.h", "signal.h", "unistd.h", "stdarg.h", "stddef.h", "float.h", "locale.h", "setjmp.h", "iso646.h", "inttypes.h", "wchar.h",
            "pthread.h", "fcntl.h", "dirent.h", "sys/types.h", "sys/stat.h", "sys/time.h", "termios.h", "complex.h", "stdatomic.h",
            "iostream", "vector", "string", "map", "set", "unordered_map", "unordered_set", "algorithm", "cmath", "cstdio", "cstdlib",
            "cstring", "memory", "utility", "functional", "numeric", "sstream", "fstream", "iomanip", "queue", "stack", "deque", "list",
            "array", "tuple", "optional", "variant", "thread", "mutex", "chrono", "random", "limits", "climits", "cassert", "bitset", "iterator",
            "ctime", "cctype", "cstdint"]
        return include.matches(in: text, range: whole).contains { m in
            ns.substring(with: m.range(at: 1)) == "\"" || !standard.contains(ns.substring(with: m.range(at: 2)))
        }
    }()

    lazy var frequentBare: Set<String> = Set(bareCounts.filter { $0.value >= 2 }.map(\.key)).union(definitions.names)
    lazy var frequentAttributes: Set<String> = Set(attributeCounts.filter { $0.value >= 2 }.map(\.key))

    private func restOfLineIsEmpty(after location: Int) -> Bool {
        var k = location
        while k < ns.length {
            let c = ns.character(at: k)
            if c == 10 { return true }
            if c != 32 && c != 9 { return false }
            k += 1
        }
        return true
    }

    private func lineIsFinished(at location: Int) -> Bool {
        ns.range(of: "\n", options: .literal, range: NSRange(location: location, length: ns.length - location)).location != NSNotFound
    }

    private func nextCharacter(after location: Int) -> Character? {
        var k = location
        while k < ns.length {
            let c = ns.character(at: k)
            if c != 32 && c != 9 { return Character(UnicodeScalar(c) ?? " ") }
            k += 1
        }
        return nil
    }

    private func followsEquals(_ location: Int) -> Bool {
        let rest = ns.substring(from: location).trimmingCharacters(in: .whitespaces)
        return rest.hasPrefix("==") || rest.hasPrefix("=>")
    }

    /// Keywords that fit at this spot: statement keywords where a statement
    /// starts, expression keywords (lambda, function, new…) after = ( , :
    private func keywords(at location: Int) -> Set<String> {
        var k = location - 1
        while k >= 0, ns.character(at: k) == 32 || ns.character(at: k) == 9 { k -= 1 }
        let c: unichar = k >= 0 ? ns.character(at: k) : 10
        if c == 10 || c == 59 || c == 123 || c == 125 || (family == "python" && c == 58) { return knowledge.keywords }   // \n ; { } and python's :
        if c == 61 || c == 40 || c == 44 || c == 58 || c == 91 {                                                     // = ( , : [
            return knowledge.keywords.intersection(Self.expressionKeywords)
        }
        return []
    }

    static let expressionKeywords: Set<String> = ["lambda", "not", "await", "yield", "None", "True", "False", "function", "typeof", "new", "async",
                                                  "this", "null", "true", "false", "nil", "self", "func", "sizeof", "instanceof", "void", "delete"]

    /// x.attr where x is a module or global Halo knows (handled by memberFixes).
    private func receiverHasMembers(_ token: Token) -> Bool {
        let dot = token.range.location - 1
        var start = dot
        while start > 0, let c = UnicodeScalar(ns.character(at: start - 1)), CharacterSet.alphanumerics.contains(c) || c == "_" || c == "$" { start -= 1 }
        guard start < dot else { return false }
        let receiver = ns.substring(with: NSRange(location: start, length: dot - start))
        if family == "python" { return pythonModules[receiver] != nil || (knowledge.members[receiver] != nil && isModule(receiver)) }
        return knowledge.members[receiver] != nil
    }

    // MARK: Missing imports and includes

    func importFixes(in scope: NSRange) -> [CodeFix] {
        guard family == "python" || family == "c" || family == "cpp" || family == "java", !wildcardImport else { return [] }
        var out: [CodeFix] = []
        var offered = Set<String>()
        for token in tokens(in: scope) where !token.afterDot && !inImportStatement(token.range.location) {
            let name = token.name
            var line: String?
            switch family {
            case "python":
                guard !isDefined(name), !knowledge.builtins.contains(name) else { continue }
                if nextCharacter(after: NSMaxRange(token.range)) == ".", knowledge.members[name] != nil, !Self.ambiguousModules.contains(name) {
                    line = "import \(name)"
                } else if let wanted = knowledge.imports[name] {
                    line = wanted
                }
            case "c", "cpp":
                guard !usesLibraries, !isDefined(name), let wanted = knowledge.imports[name] else { continue }
                let header = wanted.replacingOccurrences(of: "#include ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                let base = header.replacingOccurrences(of: ".h", with: "")
                let pattern = #"#[ \t]*include[ \t]*[<"](?:"# + NSRegularExpression.escapedPattern(for: header) + "|c" + NSRegularExpression.escapedPattern(for: base)
                    + "|" + NSRegularExpression.escapedPattern(for: base) + #"|bits/stdc\+\+\.h)[>"]"#
                if text.range(of: pattern, options: .regularExpression) != nil { continue }
                // C++ gets the C headers through <iostream> and friends often enough; only suggest the obvious ones.
                if family == "cpp", text.range(of: #"#\s*include"#, options: .regularExpression) != nil, wanted.hasSuffix(".h>") { continue }
                line = wanted
            case "java":
                guard !isDefined(name), let wanted = knowledge.imports[name] else { continue }
                let package = wanted.replacingOccurrences(of: "import ", with: "").components(separatedBy: ".").dropLast().joined(separator: ".")
                if text.contains(wanted.replacingOccurrences(of: ";", with: "")) || text.contains("import \(package).*") { continue }
                line = wanted
            default: break
            }
            guard let line, !offered.contains(line), text.range(of: line) == nil else { continue }
            offered.insert(line)
            out.append(CodeFix(range: NSRange(location: importInsertionPoint, length: 0), replacement: line + "\n",
                               why: "\(name) needs \(line)", auto: false, rule: "\(family).import", original: name,
                               anchor: token.range, insertsLine: true))
        }
        return out
    }

    /// Module names that are just as often a variable someone forgot to define.
    static let ambiguousModules: Set<String> = ["array", "queue", "string", "copy", "select", "signal", "numbers", "operator", "calendar",
                                               "struct", "enum", "html", "email", "code", "test", "types", "token", "keyword", "site", "parser",
                                               "symbol", "io", "abc", "gc", "locale", "sched", "array"]

    /// After the last import/include, else after the header comments.
    private lazy var importInsertionPoint: Int = {
        let pattern: String
        switch family {
        case "python": pattern = #"^(?:import[ \t]+[^\n]+|from[ \t]+[\w.]+[ \t]+import[ \t]+(?:\([^)]*\)|[^\n]+))\n?"#
        case "java": pattern = #"^(?:import|package)[ \t]+[^\n]+\n?"#
        default: pattern = #"^[ \t]*#[ \t]*include[^\n]*\n?"#
        }
        let re = try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        if let last = re.matches(in: text, range: whole).last(where: { mask.isCode($0.range.location) }) {
            let end = NSMaxRange(last.range)
            if end > 0, end <= ns.length, ns.character(at: end - 1) != 10 { return end }   // no trailing newline: insert after
            return end
        }
        // Skip a shebang, leading comments and a module docstring.
        var location = 0
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            var first = line.location
            while first < NSMaxRange(line), ns.character(at: first) == 32 || ns.character(at: first) == 9 { first += 1 }
            let blank = first >= NSMaxRange(line) || ns.character(at: first) == 10
            guard blank || !mask.isCode(first) || ns.substring(from: first).hasPrefix("#!") else { break }
            location = NSMaxRange(line)
        }
        return location
    }()

    // MARK: Knowledge that needs a little reasoning

    func specialFixes(in scope: NSRange) -> [CodeFix] {
        var out: [CodeFix] = []
        if family == "python" {
            // name = input(…) compared with numbers later: it's text until int() makes it a number.
            let assignment = try! NSRegularExpression(pattern: #"^[ \t]*([A-Za-z_]\w*)[ \t]*=[ \t]*(input\((?:[^()\n]|\([^()\n]*\))*\))[ \t]*(?:#.*)?$"#, options: .anchorsMatchLines)
            for m in assignment.matches(in: text, range: scope) where mask.isCode(m.range.location) {
                let name = NSRegularExpression.escapedPattern(for: ns.substring(with: m.range(at: 1)))
                let after = NSRange(location: NSMaxRange(m.range), length: ns.length - NSMaxRange(m.range))
                let converted = #"\b"# + name + #"[ \t]*=[ \t]*(?:int|float)\("#
                if (try? NSRegularExpression(pattern: converted))?.firstMatch(in: text, range: after) != nil { continue }
                let numeric = #"(?<![\w.])"# + name + #"[ \t]*(?:[<>]=?|[-*/%]|\+[ \t]*\d)[ \t]*[\d(]|[\d)][ \t]*(?:[<>]=?|[-*/%])[ \t]*"# + name + #"\b|range\([ \t]*"# + name + #"\b"#
                guard let use = (try? NSRegularExpression(pattern: numeric))?.firstMatch(in: text, range: after), mask.isCode(use.range.location) else { continue }
                let decimal = ns.substring(with: use.range).range(of: #"\d\.\d"#, options: .regularExpression) != nil
                let call = m.range(at: 2)
                let original = ns.substring(with: call)
                out.append(CodeFix(range: call, replacement: "\(decimal ? "float" : "int")(\(original))",
                                   why: "input() returns text; wrap it in \(decimal ? "float" : "int")() to use it as a number",
                                   auto: false, rule: "python.input-number", original: original, anchor: call))
            }
        }
        if family == "javascript" {
            // const that is reassigned later.
            let declaration = try! NSRegularExpression(pattern: #"\bconst([ \t]+)([A-Za-z_$][\w$]*)[ \t]*=(?!=)"#)
            for m in declaration.matches(in: text, range: scope) where mask.isCode(m.range.location) {
                let name = NSRegularExpression.escapedPattern(for: ns.substring(with: m.range(at: 2)))
                let after = NSRange(location: NSMaxRange(m.range), length: ns.length - NSMaxRange(m.range))
                let declarations = #"\b(?:const|let|var)[ \t]+"# + name + #"\b|[(,{][ \t]*"# + name + #"[ \t]*[,)=}]|\bfunction\b[^(\n]*\([^)]*\b"# + name + #"\b|\b"# + name + #"[ \t]*=>"#
                if ((try? NSRegularExpression(pattern: declarations))?.numberOfMatches(in: text, range: whole) ?? 2) > 1 { continue }
                let reassigned = #"(?m)^[ \t]*"# + name + #"[ \t]*(?:[-+*/%]?=(?![=>])|\+\+|--)"#
                guard let hit = (try? NSRegularExpression(pattern: reassigned))?.firstMatch(in: text, range: after), mask.isCode(hit.range.location) else { continue }
                let keyword = NSRange(location: m.range.location, length: 5)
                out.append(CodeFix(range: keyword, replacement: "let", why: "\(ns.substring(with: m.range(at: 2))) changes later, so it can't be const",
                                   auto: false, rule: "javascript.const-reassigned", original: "const", anchor: keyword))
            }
        }
        return out
    }

    // MARK: Closeness

    /// The nearest name: case or underscores only (strong), one edit (strong for
    /// longer names), two edits for long names (a suggestion).
    static func closest(_ word: String, in candidates: Set<String>, strict: Bool) -> (String, Bool)? {
        let lower = word.lowercased()
        let squashed = lower.replacingOccurrences(of: "_", with: "")
        let w = Array(lower.utf16)
        var best: (String, Int)?
        for candidate in candidates where !candidate.hasPrefix("_") && candidate != word {
            let c = candidate.lowercased()
            if c == lower || c.replacingOccurrences(of: "_", with: "") == squashed { return (candidate, true) }
            let cu = Array(c.utf16)
            guard abs(cu.count - w.count) <= 2 else { continue }
            let limit = w.count >= 8 ? 2 : (w.count >= 4 ? 1 : 0)
            guard limit > 0 else { continue }
            let d = distance(w, cu, limit: limit)
            if d <= limit, best == nil || d < best!.1 || (d == best!.1 && candidate < best!.0) { best = (candidate, d) }
        }
        guard let best else { return nil }
        if strict, best.1 == 2, w.count < 8 { return nil }
        return (best.0, best.1 == 1 && w.count >= 4)
    }

    /// A letter added or dropped at the very start (epoll/poll, athrow/throw) is
    /// usually a different name, not a slip.
    static func isEdgeEdit(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        return x.dropFirst() == Substring(y) || y.dropFirst() == Substring(x)
    }

    /// Pairs that are probably two real names, not a typo: x/y, 1/2, item/items.
    static func distinctPair(_ a: String, _ b: String) -> Bool {
        let a8 = Array(a), b8 = Array(b)
        if a8.count == b8.count {
            let diff = zip(a8, b8).filter { $0 != $1 }
            if diff.count == 1, let (x, y) = diff.first {
                let pairy: Set<Character> = ["x", "y", "z", "w", "X", "Y", "Z", "W", "h", "v", "H", "V"]
                if x.isNumber || y.isNumber || (pairy.contains(x) && pairy.contains(y)) { return true }
            }
        }
        if a + "s" == b || b + "s" == a || a + "es" == b || b + "es" == a { return true }
        let digitsA = a.filter(\.isNumber), digitsB = b.filter(\.isNumber)
        if digitsA != digitsB, a.filter { !$0.isNumber } == b.filter { !$0.isNumber } { return true }
        return false
    }

    /// Optimal string alignment distance (a swap counts as one edit), with an early exit.
    static func distance(_ a: [UInt16], _ b: [UInt16], limit: Int) -> Int {
        if a == b { return 0 }
        let n = a.count, m = b.count
        if abs(n - m) > limit { return limit + 1 }
        var previous2 = [Int](repeating: 0, count: m + 1)
        var previous = Array(0...m)
        var current = [Int](repeating: 0, count: m + 1)
        for i in 1...max(1, n) where n > 0 {
            current[0] = i
            var rowMin = current[0]
            for j in 1...max(1, m) where m > 0 {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { value = min(value, previous2[j - 2] + 1) }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return limit + 1 }
            previous2 = previous
            previous = current
        }
        return previous[m]
    }
}
