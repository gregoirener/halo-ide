import Foundation

enum TokenKind: String, CaseIterable {
    case comment, string, attribute, number, keyword, constant, type, function, property, heading, punctuation
}

/// A grammar is an ordered list of rules compiled into one alternation,
/// so the leftmost (then first-listed) rule wins — strings beat comments
/// inside quotes, comments beat keywords inside comments, and so on.
struct Grammar {
    let rules: [(TokenKind, String)]
}

struct Language: Identifiable, Hashable {
    let id: String
    let name: String
    let extensions: [String]
    var fileNames: [String] = []
    var lineComment: String?
    var blockComment: (open: String, close: String)?
    var indentUnit = 4
    let grammar: Grammar

    static func == (a: Language, b: Language) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let plain = Language(id: "plain", name: "Plain Text", extensions: ["txt"], grammar: Grammar(rules: []))

    static func detect(url: URL) -> Language {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if let byName = byFileName[name] ?? byFileName[name.lowercased()] { return byName }
        if let byExt = byExtension[ext] { return byExt }
        if name.hasPrefix(".env") { return .ini }
        if ext.isEmpty || plainExtensions.contains(ext) { return .plain }
        return .generic
    }

    private static let plainExtensions: Set<String> = ["txt", "text", "log", "csv", "tsv", "rst", "org", "rtf", "nfo", "out"]

    static let all: [Language] = [
        swift, javascript, typescript, python, rust, go, c, cpp, java, kotlin, ruby,
        shell, json, yaml, toml, html, css, markdown, sql,
    ] + extended + [plain]

    private static let byExtension: [String: Language] = {
        var map: [String: Language] = [:]
        for lang in all { for ext in lang.extensions where map[ext] == nil { map[ext] = lang } }
        return map
    }()

    private static let byFileName: [String: Language] = {
        var map: [String: Language] = [:]
        for lang in all { for name in lang.fileNames where map[name] == nil { map[name] = lang } }
        return map
    }()
}

// MARK: - Rule builders

private func words(_ list: String) -> String {
    let parts = list.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
    return "\\b(?:" + parts.joined(separator: "|") + ")\\b"
}

private enum R {
    static let slashComment = "//[^\\n]*"
    static let blockComment = "/\\*[\\s\\S]*?(?:\\*/|\\z)"
    static let hashComment = "#[^\\n]*"
    static let dq = "\"(?:\\\\.|[^\"\\\\\\n])*\"?"
    static let sq = "'(?:\\\\.|[^'\\\\\\n])*'?"
    static let backtick = "`(?:\\\\.|[^`\\\\])*`?"
    static let tripleDQ = "\"\"\"[\\s\\S]*?(?:\"\"\"|\\z)"
    static let tripleSQ = "'''[\\s\\S]*?(?:'''|\\z)"
    static let number = "\\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\\d[\\d_]*(?:\\.\\d[\\d_]*)?(?:[eE][+-]?\\d+)?)[a-zA-Z_]*\\b"
    static let capitalized = "\\b[A-Z][A-Za-z0-9_]*\\b"
    static let call = "\\b[a-zA-Z_][A-Za-z0-9_]*(?=\\s*\\()"
    static let member = "(?<=\\.)[a-zA-Z_][A-Za-z0-9_]*"
    static let atAttribute = "@[A-Za-z_][A-Za-z0-9_.]*"
    static let preprocessor = "^[ \\t]*#[ \\t]*[a-z]+"
}

// MARK: - Languages

extension Language {
    static let swift = Language(
        id: "swift", name: "Swift", extensions: ["swift"], fileNames: ["Package.swift"],
        lineComment: "//", blockComment: ("/*", "*/"),
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.string, R.tripleDQ), (.string, R.dq),
            (.attribute, R.atAttribute), (.attribute, "#[a-zA-Z]+"),
            (.number, R.number),
            (.keyword, words("""
                actor any as associatedtype async await break case catch class consume continue convenience default defer deinit didSet do dynamic else enum extension fallthrough fileprivate final for func get guard if import in indirect infix init inout internal is isolated lazy let macro mutating nonisolated nonmutating open operator optional override package postfix precedencegroup prefix private protocol public repeat required rethrows return set some static struct subscript super switch throw throws try typealias unowned var weak where while willSet borrowing consuming sending
                """)),
            (.constant, words("true false nil self Self")),
            (.type, R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let jsKeywords = """
        async await break case catch class const continue debugger default delete do else export extends finally for from function get if import in instanceof let new of return set static super switch throw try typeof var void while with yield
        """

    static let javascript = Language(
        id: "javascript", name: "JavaScript", extensions: ["js", "mjs", "cjs", "jsx"],
        lineComment: "//", blockComment: ("/*", "*/"), indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.string, R.backtick), (.string, R.dq), (.string, R.sq),
            (.attribute, R.atAttribute),
            (.number, R.number),
            (.keyword, words(jsKeywords)),
            (.constant, words("true false null undefined this NaN Infinity")),
            (.type, R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let typescript = Language(
        id: "typescript", name: "TypeScript", extensions: ["ts", "tsx", "mts", "cts"],
        lineComment: "//", blockComment: ("/*", "*/"), indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.string, R.backtick), (.string, R.dq), (.string, R.sq),
            (.attribute, R.atAttribute),
            (.number, R.number),
            (.keyword, words(jsKeywords + " abstract as asserts declare enum implements infer interface is keyof namespace never private protected public readonly satisfies type unique")),
            (.constant, words("true false null undefined this")),
            (.type, words("string number boolean any unknown object symbol bigint void") + "|" + R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let python = Language(
        id: "python", name: "Python", extensions: ["py", "pyi", "pyw"],
        lineComment: "#",
        grammar: Grammar(rules: [
            (.string, "\\b[rRbBfFuU]{0,2}" + R.tripleDQ), (.string, "\\b[rRbBfFuU]{0,2}" + R.tripleSQ),
            (.string, R.tripleDQ), (.string, R.tripleSQ),
            (.comment, R.hashComment),
            (.string, R.dq), (.string, R.sq),
            (.attribute, R.atAttribute),
            (.number, R.number),
            (.keyword, words("and as assert async await break case class continue def del elif else except finally for from global if import in is lambda match nonlocal not or pass raise return try while with yield")),
            (.constant, words("True False None self cls")),
            (.type, words("int float str bool list dict set tuple bytes object type") + "|" + R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let rust = Language(
        id: "rust", name: "Rust", extensions: ["rs"],
        lineComment: "//", blockComment: ("/*", "*/"),
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.string, "b?" + R.dq), (.string, "'(?:\\\\.|[^'\\\\\\n])'"),
            (.attribute, "#!?\\[[^\\]\\n]*\\]"), (.attribute, "'[a-zA-Z_][a-zA-Z0-9_]*\\b"),
            (.function, "\\b[a-z_][a-z0-9_]*!"),
            (.number, R.number),
            (.keyword, words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return static struct super trait type union unsafe use where while")),
            (.constant, words("true false self Self None Some Ok Err")),
            (.type, words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str") + "|" + R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let go = Language(
        id: "go", name: "Go", extensions: ["go"], fileNames: ["go.mod"],
        lineComment: "//", blockComment: ("/*", "*/"),
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.string, R.backtick), (.string, R.dq), (.string, R.sq),
            (.number, R.number),
            (.keyword, words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var")),
            (.constant, words("true false nil iota")),
            (.type, words("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any") + "|" + R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let cKeywords = "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while"

    static let c = Language(
        id: "c", name: "C", extensions: ["c", "h"],
        lineComment: "//", blockComment: ("/*", "*/"),
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.string, R.dq), (.string, R.sq),
            (.attribute, R.preprocessor),
            (.number, R.number),
            (.keyword, words(cKeywords)),
            (.constant, words("NULL true false")),
            (.type, words("size_t ssize_t uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t bool") + "|" + R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let cpp = Language(
        id: "cpp", name: "C++", extensions: ["cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm"],
        lineComment: "//", blockComment: ("/*", "*/"),
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.string, R.dq), (.string, R.sq),
            (.attribute, R.preprocessor), (.attribute, "@[a-zA-Z]+"),
            (.number, R.number),
            (.keyword, words(cKeywords + " alignas alignof and auto bool catch class concept consteval constexpr constinit co_await co_return co_yield decltype delete explicit export friend mutable namespace new noexcept not operator or override final private protected public requires static_assert template this thread_local throw try typeid typename using virtual")),
            (.constant, words("nullptr true false NULL nil YES NO self")),
            (.type, words("std string vector map size_t") + "|" + R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let java = Language(
        id: "java", name: "Java", extensions: ["java"],
        lineComment: "//", blockComment: ("/*", "*/"),
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.string, R.tripleDQ), (.string, R.dq), (.string, R.sq),
            (.attribute, R.atAttribute),
            (.number, R.number),
            (.keyword, words("abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public record return sealed static strictfp super switch synchronized throw throws transient try var void volatile while yield")),
            (.constant, words("true false null this")),
            (.type, words("boolean byte char double float int long short") + "|" + R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let kotlin = Language(
        id: "kotlin", name: "Kotlin", extensions: ["kt", "kts"],
        lineComment: "//", blockComment: ("/*", "*/"),
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.string, R.tripleDQ), (.string, R.dq), (.string, R.sq),
            (.attribute, R.atAttribute),
            (.number, R.number),
            (.keyword, words("abstract as break by catch class companion const constructor continue data do else enum external final finally for fun get if import in init inline inner interface internal is lateinit object open operator out override package private protected public reified return sealed set super suspend throw try typealias val var vararg when where while")),
            (.constant, words("true false null this it")),
            (.type, R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let ruby = Language(
        id: "ruby", name: "Ruby", extensions: ["rb", "rake", "gemspec"], fileNames: ["Gemfile", "Rakefile", "Podfile"],
        lineComment: "#", indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, R.hashComment),
            (.string, R.dq), (.string, R.sq),
            (.attribute, ":[a-zA-Z_][a-zA-Z0-9_?!]*"), (.attribute, "@{1,2}[a-zA-Z_][a-zA-Z0-9_]*"),
            (.number, R.number),
            (.keyword, words("alias and begin break case class def defined do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require require_relative attr_reader attr_writer attr_accessor private protected public")),
            (.constant, words("true false nil")),
            (.type, R.capitalized),
            (.function, R.call),
            (.property, R.member),
        ])
    )

    static let shell = Language(
        id: "shell", name: "Shell", extensions: ["sh", "bash", "zsh", "fish", "command"],
        fileNames: [".zshrc", ".bashrc", ".bash_profile", ".zprofile", ".profile"],
        lineComment: "#", indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, R.hashComment),
            (.string, R.dq), (.string, R.sq),
            (.attribute, "\\$\\{[^}\\n]*\\}|\\$[A-Za-z_0-9@#?*!$-]+"),
            (.number, R.number),
            (.keyword, words("if then else elif fi for while until do done case esac in function return local export source alias unset readonly shift break continue exit FROM RUN CMD COPY ADD WORKDIR ENV ARG EXPOSE ENTRYPOINT USER VOLUME LABEL")),
            (.constant, words("true false")),
            (.function, "^[ \\t]*[A-Za-z_][A-Za-z0-9_-]*(?=\\s*\\(\\))"),
            (.function, words("echo printf cd ls grep sed awk cat mkdir rm cp mv chmod chown curl git npm swift brew make test")),
        ])
    )

    static let json = Language(
        id: "json", name: "JSON", extensions: ["json", "jsonc", "json5"], fileNames: [".prettierrc", ".eslintrc"],
        lineComment: "//", blockComment: ("/*", "*/"), indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, R.slashComment),
            (.property, "\"(?:\\\\.|[^\"\\\\\\n])*\"(?=\\s*:)"),
            (.string, R.dq),
            (.number, "-?" + R.number),
            (.constant, words("true false null")),
            (.punctuation, "[{}\\[\\],:]"),
        ])
    )

    static let yaml = Language(
        id: "yaml", name: "YAML", extensions: ["yml", "yaml"],
        lineComment: "#", indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, "(?:^|(?<=\\s))#[^\\n]*"),
            (.string, R.dq), (.string, R.sq),
            (.property, "^[ \\t]*(?:- )?[A-Za-z0-9_.\\-/]+(?=\\s*:)"),
            (.attribute, "[&*][A-Za-z0-9_-]+|!![a-z]+"),
            (.number, R.number),
            (.constant, words("true false null yes no on off")),
            (.punctuation, "^[ \\t]*-(?= )|^---$"),
        ])
    )

    static let toml = Language(
        id: "toml", name: "TOML", extensions: ["toml"], fileNames: ["Cargo.lock"],
        lineComment: "#", indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, R.hashComment),
            (.string, R.tripleDQ), (.string, R.dq), (.string, R.sq),
            (.heading, "^[ \\t]*\\[\\[?[^\\]\\n]+\\]\\]?"),
            (.property, "^[ \\t]*[A-Za-z0-9_.\\-\"]+(?=\\s*=)"),
            (.number, R.number),
            (.constant, words("true false")),
        ])
    )

    static let html = Language(
        id: "html", name: "HTML", extensions: ["html", "htm", "xml", "svg", "plist", "xib", "storyboard", "vue", "svelte"],
        blockComment: ("<!--", "-->"), indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, "<!--[\\s\\S]*?(?:-->|\\z)"),
            (.attribute, "<!DOCTYPE[^>]*>|<\\?[^>]*\\?>"),
            (.string, R.dq), (.string, R.sq),
            (.keyword, "(?<=</|<)[A-Za-z][A-Za-z0-9:-]*"),
            (.property, "\\b[A-Za-z_:@][A-Za-z0-9_:.-]*(?==)"),
            (.number, "&[a-zA-Z0-9#]+;"),
            (.punctuation, "</?|/?>"),
        ])
    )

    static let css = Language(
        id: "css", name: "CSS", extensions: ["css", "scss", "sass", "less"],
        lineComment: nil, blockComment: ("/*", "*/"), indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, "(?<![:\"'])//[^\\n]*"),
            (.string, R.dq), (.string, R.sq),
            (.attribute, "@[a-zA-Z-]+"),
            (.number, "#[0-9a-fA-F]{3,8}\\b"),
            (.number, "-?\\b\\d*\\.?\\d+(?:px|em|rem|%|vh|vw|dvh|s|ms|deg|fr|ch|pt)?\\b"),
            (.property, "(?<![\\w-])--?[a-zA-Z][a-zA-Z0-9-]*(?=\\s*:)"),
            (.function, "\\b[a-zA-Z-]+(?=\\()"),
            (.type, "(?<![\\w-])[.#][a-zA-Z_][a-zA-Z0-9_-]*"),
            (.keyword, words("important inherit initial unset auto none")),
        ])
    )

    static let markdown = Language(
        id: "markdown", name: "Markdown", extensions: ["md", "markdown", "mdx"], fileNames: ["README", "CHANGELOG"],
        blockComment: ("<!--", "-->"), indentUnit: 2,
        grammar: Grammar(rules: [
            (.string, "```[\\s\\S]*?(?:```|\\z)"),
            (.comment, "<!--[\\s\\S]*?(?:-->|\\z)"),
            (.heading, "^#{1,6}[ \\t].*$"),
            (.comment, "^>[^\\n]*"),
            (.string, "`[^`\\n]+`"),
            (.keyword, "\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__"),
            (.attribute, "(?<![*\\w])\\*[^*\\n]+\\*(?!\\*)|(?<![_\\w])_[^_\\n]+_(?![_\\w])"),
            (.function, "!?\\[[^\\]\\n]*\\]\\([^)\\n]*\\)"),
            (.punctuation, "^[ \\t]*(?:[-*+]|\\d+\\.)(?=[ \\t])|^(?:-{3,}|\\*{3,})$"),
        ])
    )

    static let sql = Language(
        id: "sql", name: "SQL", extensions: ["sql"],
        lineComment: "--", blockComment: ("/*", "*/"), indentUnit: 2,
        grammar: Grammar(rules: [
            (.comment, R.blockComment), (.comment, "--[^\\n]*"),
            (.string, R.sq), (.string, R.dq),
            (.number, R.number),
            (.keyword, "(?i)" + words("select from where and or not insert into values update set delete create table index view drop alter add column primary key foreign references join left right inner outer full on as group by order having limit offset distinct union all case when then else end is null like in between exists returning with default unique check begin commit rollback")),
            (.type, "(?i)" + words("int integer bigint smallint text varchar char boolean bool date timestamp timestamptz real double numeric decimal serial uuid json jsonb blob")),
            (.function, R.call),
        ])
    )
}


// MARK: - The long tail
//
// A compact builder for the many C-like, hash-comment and ML-family
// languages: comments, strings, numbers, keywords, constants, types,
// calls and members, plus a few language-specific extras.

extension Language {
    fileprivate static func lineCommentRule(_ prefix: String) -> String {
        NSRegularExpression.escapedPattern(for: prefix) + "[^\\n]*"
    }

    fileprivate static func blockCommentRule(_ open: String, _ close: String) -> String {
        NSRegularExpression.escapedPattern(for: open) + "[\\s\\S]*?(?:" + NSRegularExpression.escapedPattern(for: close) + "|\\z)"
    }

    static func make(
        _ id: String, _ name: String, ext: [String], files: [String] = [],
        line: String? = "//", lineAlt: String? = nil, block: (open: String, close: String)? = ("/*", "*/"),
        strings: [String]? = nil, indent: Int = 4, caseInsensitive: Bool = false,
        keywords: String, types: String = "", constants: String = "true false null",
        extras: [(TokenKind, String)] = [], capitalizedTypes: Bool = true, calls: Bool = true, members: Bool = true
    ) -> Language {
        var rules: [(TokenKind, String)] = []
        if let block { rules.append((.comment, blockCommentRule(block.open, block.close))) }
        if let line { rules.append((.comment, line == "#" ? R.hashComment : lineCommentRule(line))) }
        if let lineAlt { rules.append((.comment, lineAlt == "#" ? R.hashComment : lineCommentRule(lineAlt))) }
        for str in strings ?? [R.dq, R.sq] { rules.append((.string, str)) }
        rules += extras
        rules.append((.number, R.number))
        let ci = caseInsensitive ? "(?i)" : ""
        if !keywords.isEmpty { rules.append((.keyword, ci + words(keywords))) }
        if !constants.isEmpty { rules.append((.constant, ci + words(constants))) }
        var typeRule = types.isEmpty ? "" : words(types)
        if capitalizedTypes { typeRule += (typeRule.isEmpty ? "" : "|") + R.capitalized }
        if !typeRule.isEmpty { rules.append((.type, typeRule)) }
        if calls { rules.append((.function, R.call)) }
        if members { rules.append((.property, R.member)) }
        return Language(id: id, name: name, extensions: ext, fileNames: files, lineComment: line,
                        blockComment: block, indentUnit: indent, grammar: Grammar(rules: rules))
    }

    static let generic = make("generic", "Code", ext: [], lineAlt: "#", strings: [R.tripleDQ, R.dq, R.sq, R.backtick], keywords: "if else elif for foreach while do loop return break continue switch case default match when try catch finally throw raise function func fn def let var const val class struct enum interface trait impl module namespace package import export from use using include require new delete public private protected static async await yield in is as and or not then end begin", constants: "true false null nil none None True False undefined self this")

    static let extended: [Language] = [
        make("csharp", "C#", ext: ["cs", "csx"], strings: ["@\"(?:\"\"|[^\"])*\"", "\\$?" + R.dq, R.sq], keywords: "abstract as async await base break case catch checked class const continue default delegate do else enum event explicit extern finally fixed for foreach get goto if implicit in init interface internal is lock namespace new operator out override params partial private protected public readonly record ref required return sealed set sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using value var virtual void volatile when where while with yield", types: "bool byte char decimal double dynamic float int long nint nuint object sbyte short string uint ulong ushort", constants: "true false null", extras: [(.attribute, "^[ \\t]*\\[[A-Z][A-Za-z0-9_.]*"), (.attribute, R.preprocessor)]),
        make("php", "PHP", ext: ["php", "phtml", "php8"], lineAlt: "#", keywords: "abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield", constants: "true false null TRUE FALSE NULL", extras: [(.attribute, "\\$[A-Za-z_][A-Za-z0-9_]*"), (.keyword, "<\\?php|\\?>")]),
        make("perl", "Perl", ext: ["pl", "pm", "t"], line: "#", block: nil, keywords: "my our local sub package use require no if elsif else unless while until for foreach last next redo return do eval die warn print printf say chomp split join push pop shift unshift keys values defined exists delete scalar ref bless qw", constants: "undef", extras: [(.attribute, "[$@%][A-Za-z_][A-Za-z0-9_]*")]),
        make("lua", "Lua", ext: ["lua"], line: "--", block: ("--[[", "]]"), strings: ["\\[\\[[\\s\\S]*?(?:\\]\\]|\\z)", R.dq, R.sq], indent: 2, keywords: "and break do else elseif end for function goto if in local not or repeat return then until while", constants: "true false nil self"),
        make("r", "R", ext: ["r", "rmd"], line: "#", block: nil, indent: 2, keywords: "if else repeat while function for in next break library require return switch", constants: "TRUE FALSE NULL NA NaN Inf T F", extras: [(.keyword, "<-|->|%>%|\\|>")]),
        make("julia", "Julia", ext: ["jl"], line: "#", block: ("#=", "=#"), strings: [R.tripleDQ, R.dq, R.sq], keywords: "abstract baremodule begin break catch const continue do else elseif end export finally for function global if import in let local macro module mutable quote return struct try type using while where", constants: "true false nothing missing NaN Inf", extras: [(.attribute, "@[A-Za-z_][A-Za-z0-9_!]*"), (.attribute, ":[A-Za-z_][A-Za-z0-9_]*")]),
        make("dart", "Dart", ext: ["dart"], strings: [R.tripleDQ, R.tripleSQ, R.dq, R.sq], indent: 2, keywords: "abstract as assert async await base break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory final finally for get hide if implements import in interface is late library mixin new on operator part required rethrow return sealed set show static super switch sync this throw try typedef var void when while with yield", types: "int double num bool String List Map Set Future Stream Object dynamic void", constants: "true false null", extras: [(.attribute, R.atAttribute)]),
        make("scala", "Scala", ext: ["scala", "sc", "sbt"], strings: [R.tripleDQ, R.dq, R.sq], indent: 2, keywords: "abstract case catch class def do else enum export extends final finally for forSome given if implicit import lazy match new object override package private protected return sealed super then throw trait try type using val var while with yield", constants: "true false null this", extras: [(.attribute, R.atAttribute)]),
        make("groovy", "Groovy", ext: ["groovy", "gradle", "gvy"], files: ["Jenkinsfile", "build.gradle", "settings.gradle"], strings: [R.tripleDQ, R.tripleSQ, R.dq, R.sq], keywords: "abstract as assert break case catch class const continue def default do else enum extends final finally for goto if implements import in instanceof interface new package private protected public return static super switch synchronized this throw throws trait transient try var void volatile while", constants: "true false null", extras: [(.attribute, R.atAttribute)]),
        make("elixir", "Elixir", ext: ["ex", "exs", "heex", "eex"], files: ["mix.lock"], line: "#", block: nil, strings: [R.tripleDQ, R.dq, R.sq], indent: 2, keywords: "after alias and case catch cond def defdelegate defexception defguard defimpl defmacro defmodule defp defprotocol defstruct do else end fn for if import in not or quote raise receive require rescue try unless unquote use when with", constants: "true false nil", extras: [(.attribute, ":[A-Za-z_][A-Za-z0-9_?!]*"), (.attribute, "@[A-Za-z_][A-Za-z0-9_]*")]),
        make("erlang", "Erlang", ext: ["erl", "hrl"], files: ["rebar.config"], line: "%", block: nil, keywords: "after and andalso band begin bnot bor bsl bsr bxor case catch cond div end fun if let not of or orelse query receive rem try when xor", constants: "true false undefined", extras: [(.attribute, "\\?[A-Za-z_][A-Za-z0-9_]*"), (.attribute, "-[a-z_]+(?=\\()")]),
        make("haskell", "Haskell", ext: ["hs", "lhs"], line: "--", block: ("{-", "-}"), strings: [R.dq, "'(?:\\\\.|[^'\\\\\\n])'"], indent: 2, keywords: "case class data default deriving do else family forall foreign hiding if import in infix infixl infixr instance let mdo module newtype of proc qualified rec then type where", constants: "True False Nothing Just otherwise", members: false),
        make("elm", "Elm", ext: ["elm"], line: "--", block: ("{-", "-}"), strings: [R.tripleDQ, R.dq, R.sq], keywords: "alias as case else exposing if import in let module of port then type where", constants: "True False Nothing Just"),
        make("ocaml", "OCaml", ext: ["ml", "mli", "mll", "mly"], line: nil, block: ("(*", "*)"), indent: 2, keywords: "and as assert begin class constraint do done downto else end exception external for fun function functor if in include inherit initializer lazy let match method module mutable new nonrec object of open or private rec sig struct then to try type val virtual when while with", constants: "true false None Some"),
        make("fsharp", "F#", ext: ["fs", "fsi", "fsx"], block: ("(*", "*)"), keywords: "abstract and as assert base begin class default delegate do done downcast downto elif else end exception extern false finally for fun function global if in inherit inline interface internal lazy let match member module mutable namespace new not null of open or override private public rec return static struct then to true try type upcast use val void when while with yield", constants: "true false null None Some"),
        make("clojure", "Clojure", ext: ["clj", "cljs", "cljc", "edn"], line: ";", block: nil, strings: [R.dq], indent: 2, keywords: "def defn defn- defmacro defmulti defmethod defprotocol defrecord deftype fn let letfn loop recur if if-not when when-not cond condp case do doseq dotimes for ns require import use try catch finally throw quote var", constants: "true false nil", extras: [(.attribute, ":[A-Za-z0-9_\\-?!*+<>=/.]+")], capitalizedTypes: false, calls: false, members: false),
        make("scheme", "Scheme", ext: ["scm", "ss", "lisp", "lsp", "cl", "el"], files: [".emacs"], line: ";", block: ("#|", "|#"), strings: [R.dq], indent: 2, keywords: "define define-syntax lambda let let* letrec if cond case and or when unless begin do set! quote quasiquote defun defvar defparameter defmacro setq progn loop", constants: "#t #f t nil", capitalizedTypes: false, calls: false, members: false),
        make("racket", "Racket", ext: ["rkt"], line: ";", block: ("#|", "|#"), strings: [R.dq], indent: 2, keywords: "define define-values lambda λ let let* letrec if cond case and or when unless begin require provide struct module match", constants: "#t #f true false", capitalizedTypes: false, calls: false, members: false),
        make("zig", "Zig", ext: ["zig", "zon"], block: nil, keywords: "addrspace align allowzero and anyframe anytype asm async await break callconv catch comptime const continue defer else enum errdefer error export extern fn for if inline linksection noalias noinline nosuspend opaque or orelse packed pub resume return struct suspend switch test threadlocal try union unreachable usingnamespace var volatile while", types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f16 f32 f64 f128 bool void type anyerror noreturn comptime_int comptime_float", constants: "true false null undefined", extras: [(.attribute, "@[A-Za-z_][A-Za-z0-9_]*")]),
        make("nim", "Nim", ext: ["nim", "nims", "nimble"], line: "#", block: ("#[", "]#"), strings: [R.tripleDQ, R.dq, R.sq], indent: 2, keywords: "addr and as asm bind block break case cast concept const continue converter defer discard distinct div do elif else end enum except export finally for from func if import in include interface is isnot iterator let macro method mixin mod nil not notin object of or out proc ptr raise ref return shl shr static template try tuple type using var when while xor yield", constants: "true false nil"),
        make("crystal", "Crystal", ext: ["cr"], line: "#", block: nil, indent: 2, keywords: "abstract alias annotation as begin break case class def do else elsif end ensure enum extend for fun if in include lib macro module next of out private protected require rescue return select self struct super then type typeof union unless until when while with yield", constants: "true false nil", extras: [(.attribute, ":[A-Za-z_][A-Za-z0-9_?!]*"), (.attribute, "@{1,2}[A-Za-z_][A-Za-z0-9_]*")]),
        make("d", "D", ext: ["d", "di"], block: ("/+", "+/"), keywords: "abstract alias align asm assert auto body break case cast catch class const continue debug default delegate delete deprecated do else enum export extern final finally for foreach foreach_reverse function goto if immutable import in inout interface invariant is lazy mixin module new nothrow out override package pragma private protected public pure ref return scope shared static struct super switch synchronized template this throw try typeid typeof union unittest version while with", types: "bool byte ubyte short ushort int uint long ulong float double real char wchar dchar string void", constants: "true false null"),
        make("haxe", "Haxe", ext: ["hx", "hxml"], keywords: "abstract break case cast catch class continue default do dynamic else enum extends extern final for function if implements import in inline interface macro new operator overload override package private public return static switch this throw try typedef untyped using var while", constants: "true false null"),
        make("gleam", "Gleam", ext: ["gleam"], block: nil, indent: 2, keywords: "as assert case const external fn if import let opaque panic pub todo type use", constants: "True False Nil"),
        make("solidity", "Solidity", ext: ["sol"], keywords: "abstract address anonymous as assembly break calldata catch constant constructor continue contract delete do else emit enum event external fallback for function if immutable import indexed interface internal is library mapping memory modifier new override payable pragma private public pure receive return returns revert storage struct try type unchecked using view virtual while", types: "bool string bytes byte int uint int256 uint256 int8 uint8 address bytes32", constants: "true false wei gwei ether"),
        make("verilog", "Verilog", ext: ["v", "sv", "svh", "vh"], keywords: "always always_comb always_ff always_latch assign automatic begin case casex casez default else end endcase endfunction endgenerate endmodule endtask for forever function generate if initial inout input integer interface localparam logic module negedge output parameter posedge reg repeat signed task typedef unsigned while wire", constants: "", extras: [(.attribute, "`[A-Za-z_]+"), (.number, "\\d*'[sS]?[bBoOdDhH][0-9a-fA-FxXzZ_]+")]),
        make("vhdl", "VHDL", ext: ["vhd", "vhdl"], line: "--", block: nil, caseInsensitive: true, keywords: "abs access after alias all and architecture array assert attribute begin block body buffer bus case component configuration constant downto else elsif end entity exit file for function generate generic group guarded if impure in inertial inout is label library linkage literal loop map mod nand new next nor not null of on open or others out package port postponed procedure process pure range record register reject rem report return rol ror select severity signal shared sla sll sra srl subtype then to transport type unaffected units until use variable wait when while with xnor xor", types: "std_logic std_logic_vector integer natural positive boolean bit bit_vector signed unsigned", constants: "true false"),
        make("fortran", "Fortran", ext: ["f", "f90", "f95", "f03", "f08", "for"], line: "!", block: nil, caseInsensitive: true, keywords: "program end subroutine function module use implicit none integer real double precision complex logical character parameter dimension allocatable intent in out inout if then else elseif endif do enddo while call return contains type select case stop print write read format", constants: ".true. .false.", capitalizedTypes: false),
        make("pascal", "Pascal", ext: ["pas", "pp", "dpr", "lpr"], line: "//", block: ("{", "}"), strings: [R.sq], caseInsensitive: true, keywords: "and array as asm begin case class const constructor destructor div do downto else end except exports file finalization finally for function goto if implementation in inherited initialization inline interface is label library mod nil not object of or out packed procedure program property raise record repeat set shl shr string then threadvar to try type unit until uses var while with xor", constants: "true false nil"),
        make("ada", "Ada", ext: ["adb", "ads", "ada"], line: "--", block: nil, caseInsensitive: true, keywords: "abort abs abstract accept access aliased all and array at begin body case constant declare delay delta digits do else elsif end entry exception exit for function generic goto if in interface is limited loop mod new not null of or others out overriding package pragma private procedure protected raise range record rem renames requeue return reverse select separate some subtype synchronized tagged task terminate then type until use when while with xor", constants: "true false"),
        make("cobol", "COBOL", ext: ["cbl", "cob", "cpy"], line: "*>", block: nil, caseInsensitive: true, keywords: "identification division program-id environment configuration data working-storage section procedure perform until varying display accept move to add subtract multiply divide compute if else end-if evaluate when end-evaluate stop run pic picture value goback call using", constants: "zero zeros spaces", capitalizedTypes: false),
        make("asm", "Assembly", ext: ["asm", "s", "nasm", "inc"], line: ";", lineAlt: "#", block: nil, keywords: "mov movq movl lea add sub mul imul div idiv inc dec and or xor not neg shl shr sal sar cmp test jmp je jne jz jnz jg jge jl jle ja jb call ret push pop nop syscall int ldr str ldp stp adr adrp bl blr br cbz cbnz b beq bne svc", constants: "", extras: [(.attribute, "^[ \\t]*\\.[A-Za-z_]+"), (.function, "^[ \\t]*[A-Za-z_.$][A-Za-z0-9_.$]*:"), (.type, "\\b(?:[re]?[abcd]x|[re]?[sd]i|[re]?[sb]p|r\\d{1,2}[dwb]?|[xw]\\d{1,2}|sp|lr|pc|fp|xzr|wzr)\\b")], capitalizedTypes: false, calls: false, members: false),
        make("powershell", "PowerShell", ext: ["ps1", "psm1", "psd1"], line: "#", block: ("<#", "#>"), caseInsensitive: true, keywords: "begin break catch class continue data do dynamicparam else elseif end enum exit filter finally for foreach from function if in param process return switch throw trap try until using var while workflow", constants: "$true $false $null", extras: [(.attribute, "\\$[A-Za-z_][A-Za-z0-9_:]*"), (.function, "\\b[A-Z][a-z]+-[A-Z][A-Za-z]+\\b")]),
        make("batch", "Batch", ext: ["bat", "cmd"], line: "::", lineAlt: nil, block: nil, strings: [R.dq], caseInsensitive: true, keywords: "echo set if else goto call exit for in do not exist defined errorlevel setlocal endlocal pushd popd cd shift start pause", constants: "on off", extras: [(.comment, "(?i)^[ \\t]*rem\\b[^\\n]*"), (.attribute, "%[A-Za-z0-9_~]+%?|![A-Za-z0-9_]+!")], capitalizedTypes: false, members: false),
        make("makefile", "Makefile", ext: ["mk", "mak", "make"], files: ["Makefile", "makefile", "GNUmakefile"], line: "#", block: nil, indent: 4, keywords: "ifeq ifneq ifdef ifndef else endif include define endef export override .PHONY", constants: "", extras: [(.function, "^[A-Za-z0-9_.\\-/%$()]+(?=\\s*::?(?!=))"), (.attribute, "\\$[({][^)}]*[)}]|\\$[@<^?*%]")], capitalizedTypes: false, calls: false, members: false),
        make("dockerfile", "Dockerfile", ext: ["dockerfile"], files: ["Dockerfile", "Containerfile"], line: "#", block: nil, caseInsensitive: true, keywords: "FROM AS RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL", constants: "", extras: [(.attribute, "\\$\\{[^}\\n]*\\}|\\$[A-Za-z_][A-Za-z0-9_]*")], capitalizedTypes: false, calls: false, members: false),
        make("cmake", "CMake", ext: ["cmake"], files: ["CMakeLists.txt"], line: "#", block: nil, caseInsensitive: true, keywords: "if elseif else endif foreach endforeach while endwhile function endfunction macro endmacro return set unset option project cmake_minimum_required add_executable add_library target_link_libraries target_include_directories include find_package message install add_subdirectory", constants: "ON OFF TRUE FALSE", extras: [(.attribute, "\\$\\{[^}\\n]*\\}")], capitalizedTypes: false),
        make("nix", "Nix", ext: ["nix"], line: "#", strings: ["''[\\s\\S]*?(?:''|\\z)", R.dq], indent: 2, keywords: "assert builtins else if import in inherit let or rec then with", constants: "true false null"),
        make("hcl", "Terraform", ext: ["tf", "tfvars", "hcl"], lineAlt: "#", indent: 2, keywords: "resource data variable output locals module provider terraform for in if for_each count depends_on lifecycle dynamic", constants: "true false null", extras: [(.property, "^[ \\t]*[A-Za-z_][A-Za-z0-9_\\-]*(?=\\s*=)")]),
        make("graphql", "GraphQL", ext: ["graphql", "gql"], line: "#", block: nil, strings: [R.tripleDQ, R.dq], indent: 2, keywords: "query mutation subscription fragment on type input enum interface union scalar schema extend implements directive", constants: "true false null", extras: [(.attribute, "@[A-Za-z_]+"), (.attribute, "\\$[A-Za-z_][A-Za-z0-9_]*")], calls: false),
        make("protobuf", "Protocol Buffers", ext: ["proto"], indent: 2, keywords: "syntax package import option message enum service rpc returns oneof map repeated optional required reserved extend stream", types: "double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes", constants: "true false"),
        make("prisma", "Prisma", ext: ["prisma"], block: nil, indent: 2, keywords: "datasource generator model enum type view", types: "String Boolean Int BigInt Float Decimal DateTime Json Bytes", constants: "true false null", extras: [(.attribute, "@{1,2}[A-Za-z_.]+")]),
        make("shader", "Shader", ext: ["glsl", "vert", "frag", "geom", "comp", "tesc", "tese", "hlsl", "fx", "metal", "wgsl", "cu", "cuh"], keywords: "attribute uniform varying in out inout layout const struct return if else for while do break continue discard switch case default kernel vertex fragment device constant thread threadgroup using namespace fn let var override __global__ __device__ __host__ __shared__ cbuffer register", types: "void bool int uint float double half vec2 vec3 vec4 ivec2 ivec3 ivec4 mat2 mat3 mat4 sampler2D texture2d float2 float3 float4 float4x4 half4 vec2f vec3f vec4f mat4x4f", constants: "true false", extras: [(.attribute, R.preprocessor), (.attribute, "@[a-z_]+|\\[\\[[a-z_]+(?:\\([^)]*\\))?\\]\\]")]),
        make("latex", "LaTeX", ext: ["tex", "sty", "cls", "bib", "ltx"], line: "%", block: nil, strings: ["\\$\\$[\\s\\S]*?\\$\\$", "\\$[^$\\n]*\\$"], indent: 2, keywords: "", constants: "", extras: [(.keyword, "\\\\(?:begin|end|section|subsection|chapter|documentclass|usepackage|newcommand|renewcommand)\\b"), (.function, "\\\\[A-Za-z@]+"), (.attribute, "\\{[A-Za-z*]+\\}")], capitalizedTypes: false, calls: false, members: false),
        make("ini", "INI", ext: ["ini", "cfg", "conf", "properties", "editorconfig", "gitconfig", "env", "desktop", "service"], files: [".editorconfig", ".gitconfig", ".npmrc", ".env"], line: ";", lineAlt: "#", block: nil, indent: 2, keywords: "", constants: "true false yes no on off", extras: [(.heading, "^[ \\t]*\\[[^\\]\\n]+\\]"), (.property, "^[ \\t]*[A-Za-z0-9_.\\-]+(?=\\s*[=:])")], capitalizedTypes: false, calls: false, members: false),
        make("diff", "Diff", ext: ["diff", "patch"], line: nil, block: nil, strings: [], keywords: "", constants: "", extras: [(.heading, "^(?:\\+\\+\\+|---)[^\\n]*"), (.attribute, "^@@[^\\n]*"), (.string, "^\\+[^\\n]*"), (.keyword, "^-[^\\n]*"), (.comment, "^diff [^\\n]*|^index [^\\n]*")], capitalizedTypes: false, calls: false, members: false),
        make("applescript", "AppleScript", ext: ["applescript", "scpt"], line: "--", lineAlt: "#", block: ("(*", "*)"), strings: [R.dq], caseInsensitive: true, keywords: "about above after against and apart around as aside at back before beginning behind below beneath beside between but by considering contain contains continue copy div does eighth else end equal equals error every exit false fifth first for fourth from front get given global if ignoring in instead into is it its last local me middle mod my ninth not of on onto or out over prop property put ref reference repeat return returning script second set seventh since sixth some tell tenth that the then third through thru timeout times to transaction true try until where while whose with without", constants: "true false missing value", capitalizedTypes: false),
        make("awk", "Awk", ext: ["awk"], line: "#", block: nil, strings: [R.dq], keywords: "BEGIN END if else while for in do break continue next exit return delete function getline print printf", constants: "NR NF FS OFS RS ORS FILENAME", extras: [(.attribute, "\\$[0-9A-Za-z_]+"), (.string, "(?<![\\w)])/(?:\\\\.|[^/\\n])+/")], capitalizedTypes: false),
        make("tcl", "Tcl", ext: ["tcl", "tk"], line: "#", block: nil, strings: [R.dq], keywords: "proc set if elseif else while for foreach switch return break continue puts expr incr list lindex llength lappend string regexp regsub namespace package source global upvar uplevel catch error", constants: "", extras: [(.attribute, "\\$[A-Za-z_][A-Za-z0-9_:]*")], capitalizedTypes: false),
        make("vim", "Vim Script", ext: ["vim"], files: [".vimrc", "_vimrc", ".gvimrc"], line: "\"", block: nil, strings: [R.sq], indent: 2, keywords: "if else elseif endif while endwhile for endfor in function endfunction return let unlet set call execute autocmd augroup command map nmap vmap imap nnoremap vnoremap inoremap syntax highlight source", constants: "", capitalizedTypes: false),
        make("coffeescript", "CoffeeScript", ext: ["coffee", "litcoffee"], line: "#", block: ("###", "###"), strings: [R.tripleDQ, R.dq, R.sq], indent: 2, keywords: "and break by catch class continue delete do else extends finally for if in instanceof is isnt loop new not of or own return super switch then throw try typeof unless until when while yield", constants: "true false null undefined yes no on off this", extras: [(.attribute, "@[A-Za-z_][A-Za-z0-9_]*")]),
        make("mojo", "Mojo", ext: ["mojo", "🔥"], line: "#", block: nil, strings: [R.tripleDQ, R.tripleSQ, R.dq, R.sq], keywords: "alias and as async await borrowed break class continue def del elif else except fn for from if import in inout is lambda let not or owned pass raise return struct trait try var while with yield", constants: "True False None self", extras: [(.attribute, R.atAttribute)]),
        make("objc", "Objective-C", ext: [], line: "//", keywords: "auto break case char const continue default do double else enum extern float for goto if inline int long register return short signed sizeof static struct switch typedef union unsigned void volatile while self super nil Nil YES NO id instancetype nonatomic atomic strong weak copy assign readonly readwrite", constants: "YES NO nil NULL true false", extras: [(.attribute, R.preprocessor), (.keyword, "@(?:interface|implementation|end|property|synthesize|protocol|selector|class|import|autoreleasepool|try|catch|finally|throw|optional|required|dynamic)\\b"), (.string, "@" + R.dq)]),
    ]

    static let ini: Language = extended.first { $0.id == "ini" }!
}
