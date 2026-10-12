import Foundation

/// How to run (and, for compiled languages, build) the file in front of you.
struct RunPlan {
    var compile: [String]?            // argv, run headless so errors land in the editor
    var command: String               // shell line, run in the integrated terminal
    var program: String?              // built binary (what the debugger launches)
    var cwd: URL
}

enum RunError: LocalizedError {
    case unsupported(String)
    case missingTool(String, install: String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let lang): "Halo doesn’t know how to run \(lang) files yet."
        case .missingTool(let tool, _): "\(tool) isn’t installed."
        }
    }

    var installHint: String? {
        if case .missingTool(_, let install) = self { return install }
        return nil
    }
}

enum Tools {
    private static let searchPaths: [String] = {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin",
                "\(home)/.cargo/bin", "\(home)/go/bin", "/usr/local/go/bin", "\(home)/.local/bin",
                "\(home)/.bun/bin", "\(home)/.deno/bin", "\(home)/.pyenv/shims",
                "/Library/Frameworks/Python.framework/Versions/Current/bin", "/opt/homebrew/opt/python/libexec/bin"]
    }()

    static func find(_ name: String) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        for dir in searchPaths {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Developer tools from Xcode or the Command Line Tools, without ever
    /// triggering the "install developer tools" popup.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var xcrunCache: [String: String?] = [:]

    static func xcrun(_ tool: String) -> String? {
        lock.lock()
        if let cached = xcrunCache[tool] { lock.unlock(); return cached }
        lock.unlock()
        let found = xcrunLookup(tool)
        lock.lock(); xcrunCache[tool] = found; lock.unlock()
        return found
    }

    private static func xcrunLookup(_ tool: String) -> String? {
        guard Git.executable != nil || FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["-f", tool]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// The macOS SDK. Compilers launched by absolute path (not through
    /// `xcrun`) need it spelled out to find system headers.
    static let sdkPath: String? = {
        guard xcrun("clang") != nil else { return nil }
        let (code, out) = Shell.run(["/usr/bin/xcrun", "--show-sdk-path"])
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return code == 0 && !path.isEmpty ? path : nil
    }()

    static func python(root: URL?) -> String {
        if let root {
            for venv in [".venv", "venv", "env"] {
                let py = root.appendingPathComponent("\(venv)/bin/python").path
                if FileManager.default.isExecutableFile(atPath: py) { return py }
            }
        }
        return find("python3") ?? "python3"
    }
}

enum Runner {
    static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static var buildDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Halo/build")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func plan(for url: URL, language: Language, root: URL?) -> Result<RunPlan, RunError> {
        let dir = url.deletingLastPathComponent()
        let file = q(url.path)
        let cd = "cd \(q(dir.path)) && "
        let base = url.deletingPathExtension().lastPathComponent
        let out = buildDirectory.appendingPathComponent(base + "-" + String(UInt32(truncatingIfNeeded: url.path.hashValue), radix: 36)).path

        func terminal(_ line: String, cwd: URL = dir) -> Result<RunPlan, RunError> { .success(RunPlan(command: line, cwd: cwd)) }

        switch language.id {
        case "python":
            return terminal(cd + "\(q(Tools.python(root: root))) -u \(file)")
        case "c", "cpp":
            guard let clang = Tools.xcrun(language.id == "c" ? "clang" : "clang++") else {
                return .failure(.missingTool("A C compiler (clang)", install: "xcode-select --install"))
            }
            let isObjC = ["m", "mm"].contains(url.pathExtension.lowercased())
            var args = [clang, "-g", "-O0", "-Wall", "-Wextra", "-fno-color-diagnostics", "-fdiagnostics-absolute-paths"]
            if let sdk = Tools.sdkPath { args += ["-isysroot", sdk] }
            if language.id == "c" && !isObjC { args.append("-std=c17") }
            if language.id == "cpp" && !isObjC { args.append("-std=c++20") }
            if isObjC { args += ["-fobjc-arc", "-framework", "Foundation"] }
            args += companionSources(for: url)
            args += ["-o", out]
            if language.id == "c" { args.append("-lm") }
            return .success(RunPlan(compile: args, command: cd + q(out), program: out, cwd: dir))
        case "swift":
            if let root, FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
                return terminal("cd \(q(root.path)) && swift run", cwd: root)
            }
            guard let swiftc = Tools.xcrun("swiftc") else { return .failure(.missingTool("Swift", install: "xcode-select --install")) }
            var args = [swiftc, "-g", "-Onone"]
            if let sdk = Tools.sdkPath { args += ["-sdk", sdk] }
            return .success(RunPlan(compile: args + [url.path, "-o", out], command: cd + q(out), program: out, cwd: dir))
        case "rust":
            if let root, FileManager.default.fileExists(atPath: root.appendingPathComponent("Cargo.toml").path) {
                return terminal("cd \(q(root.path)) && cargo run", cwd: root)
            }
            guard let rustc = Tools.find("rustc") else {
                return .failure(.missingTool("Rust", install: "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"))
            }
            return .success(RunPlan(compile: [rustc, "-g", "--error-format=short", url.path, "-o", out], command: cd + q(out), program: out, cwd: dir))
        case "go":
            if let root, FileManager.default.fileExists(atPath: root.appendingPathComponent("go.mod").path), dir.path.hasPrefix(root.path) {
                return terminal(cd + "go run .")
            }
            return terminal(cd + "go run \(file)")
        case "javascript":
            return terminal(cd + "node \(file)")
        case "typescript":
            if Tools.find("bun") != nil { return terminal(cd + "bun run \(file)") }
            if Tools.find("deno") != nil { return terminal(cd + "deno run --allow-all \(file)") }
            return terminal(cd + "npx --yes tsx \(file)")
        case "java": return terminal(cd + "java \(file)")
        case "kotlin":
            if url.pathExtension == "kts" { return terminal(cd + "kotlinc -script \(file)") }
            return terminal(cd + "kotlinc \(file) -include-runtime -d \(q(out + ".jar")) && java -jar \(q(out + ".jar"))")
        case "ruby": return terminal(cd + "ruby \(file)")
        case "php": return terminal(cd + "php \(file)")
        case "perl": return terminal(cd + "perl \(file)")
        case "lua": return terminal(cd + "lua \(file)")
        case "r": return terminal(cd + "Rscript \(file)")
        case "julia": return terminal(cd + "julia \(file)")
        case "dart": return terminal(cd + "dart run \(file)")
        case "elixir": return terminal(cd + "elixir \(file)")
        case "haskell": return terminal(cd + "runghc \(file)")
        case "scala": return terminal(cd + "scala-cli run \(file)")
        case "csharp": return terminal(cd + "dotnet run")
        case "zig": return terminal(cd + "zig run \(file)")
        case "nim": return terminal(cd + "nim c -r --hints:off \(file)")
        case "crystal": return terminal(cd + "crystal run \(file)")
        case "ocaml": return terminal(cd + "ocaml \(file)")
        case "fsharp": return terminal(cd + "dotnet fsi \(file)")
        case "clojure": return terminal(cd + "clojure -M \(file)")
        case "racket", "scheme": return terminal(cd + "racket \(file)")
        case "erlang": return terminal(cd + "escript \(file)")
        case "fortran": return terminal(cd + "gfortran \(file) -o \(q(out)) && \(q(out))")
        case "pascal": return terminal(cd + "fpc \(file) -o\(q(out)) && \(q(out))")
        case "applescript": return terminal(cd + "osascript \(file)")
        case "powershell": return terminal(cd + "pwsh \(file)")
        case "shell":
            switch url.pathExtension.lowercased() {
            case "zsh": return terminal(cd + "zsh \(file)")
            case "fish": return terminal(cd + "fish \(file)")
            default:
                if url.lastPathComponent == "Makefile" { return terminal(cd + "make") }
                if url.lastPathComponent == "Dockerfile" { return terminal(cd + "docker build .") }
                return terminal(cd + "bash \(file)")
            }
        case "makefile": return terminal(cd + "make")
        case "dockerfile": return terminal(cd + "docker build .")
        case "html", "markdown":
            return terminal("open \(file)")
        default:
            return .failure(.unsupported(language.name))
        }
    }

    /// Other .c/.cpp files in the same folder that don't define main —
    /// so small multi-file programs just build.
    static func companionSources(for url: URL) -> [String] {
        let ext = url.pathExtension.lowercased()
        let family: Set<String> = ["c"].contains(ext) ? ["c"] : ["cpp", "cc", "cxx", "m", "mm", "c"].contains(ext) ? ["cpp", "cc", "cxx"] : [ext]
        let dir = url.deletingLastPathComponent()
        var sources = [url.path]
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return sources }
        for item in items where item.standardizedFileURL != url.standardizedFileURL && family.contains(item.pathExtension.lowercased()) {
            guard let text = try? String(contentsOf: item, encoding: .utf8) else { continue }
            if text.range(of: #"\bint\s+main\s*\("#, options: .regularExpression) == nil { sources.append(item.path) }
        }
        return sources
    }

    struct BuildResult { let ok: Bool; let output: String; let diagnostics: [Diagnostic] }

    static func build(_ argv: [String], cwd: URL) async -> BuildResult {
        await Task.detached(priority: .userInitiated) {
            let (status, output) = Shell.run(argv, cwd: cwd)
            return BuildResult(ok: status == 0, output: output, diagnostics: parseDiagnostics(output, cwd: cwd, source: URL(fileURLWithPath: argv[0]).lastPathComponent))
        }.value
    }

    /// Parses `path:line:col: error: message` (clang, gcc, swiftc, rustc --error-format=short, go, gofmt).
    static func parseDiagnostics(_ output: String, cwd: URL, source: String, stdinPath: String? = nil) -> [Diagnostic] {
        let pattern = #"^(.+?):(\d+):(?:(\d+):)?\s*(fatal error|error|warning|note)(?:\[[^\]]*\])?:\s*(.+)$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let ns = output as NSString
        var out: [Diagnostic] = []
        for m in re.matches(in: output, range: NSRange(location: 0, length: ns.length)) {
            var path = ns.substring(with: m.range(at: 1))
            if let stdinPath, path == "<stdin>" || path == "-" || path == "<standard input>" { path = stdinPath }
            if !path.hasPrefix("/") { path = cwd.appendingPathComponent(path).standardizedFileURL.path }
            let line = Int(ns.substring(with: m.range(at: 2))) ?? 1
            let column = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3))) : nil
            let kind = ns.substring(with: m.range(at: 4))
            let severity: Diagnostic.Severity = kind.contains("error") ? .error : kind == "warning" ? .warning : .note
            out.append(Diagnostic(path: path, line: line, column: column, severity: severity, message: ns.substring(with: m.range(at: 5)), source: source))
        }
        return out
    }
}

/// Live error checking on unsaved buffers, piped through the real tools.
enum Linter {
    static func supports(_ language: Language) -> Bool {
        ["c", "cpp", "python", "go", "json", "swift"].contains(language.id)
    }

    static func lint(text: String, url: URL, language: Language, root: URL?) async -> [Diagnostic] {
        await Task.detached(priority: .utility) { lintSync(text: text, url: url, language: language, root: root) }.value
    }

    private static func lintSync(text: String, url: URL, language: Language, root: URL?) -> [Diagnostic] {
        let dir = url.deletingLastPathComponent()
        let path = url.standardizedFileURL.path
        switch language.id {
        case "c", "cpp":
            let ext = url.pathExtension.lowercased()
            let isHeader = ["h", "hpp", "hh", "hxx"].contains(ext)
            guard let clang = Tools.xcrun("clang") else { return [] }
            let lang: String = switch ext {
            case "m": "objective-c"
            case "mm": "objective-c++"
            case "c": "c"
            case "h": "c-header"
            default: isHeader ? "c++-header" : "c++"
            }
            var args = [clang, "-fsyntax-only", "-fno-color-diagnostics", "-Wall", "-x", lang, "-I", dir.path]
            if let sdk = Tools.sdkPath { args += ["-isysroot", sdk] }
            if let root { args += ["-I", root.path, "-I", root.appendingPathComponent("include").path] }
            if lang == "c" { args.append("-std=c17") } else if lang.hasPrefix("c++") { args.append("-std=c++20") }
            if lang.hasPrefix("objective") { args.append("-fobjc-arc") }
            args.append("-")
            let (_, output) = Shell.run(args, cwd: dir, stdin: text)
            return Runner.parseDiagnostics(output, cwd: dir, source: "clang", stdinPath: path).filter { $0.path == path }
        case "python":
            let script = """
            import ast, sys
            src = sys.stdin.read()
            try:
                ast.parse(src)
            except SyntaxError as e:
                print(f"{e.lineno or 1}:{e.offset or 0}:{e.msg}")
            """
            let (_, output) = Shell.run([Tools.python(root: root), "-c", script], cwd: dir, stdin: text)
            let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", maxSplits: 2)
            guard parts.count == 3, let line = Int(parts[0]) else { return [] }
            let col = Int(parts[1]).flatMap { $0 > 0 ? $0 : nil }
            return [Diagnostic(path: path, line: line, column: col, severity: .error, message: String(parts[2]), source: "python")]
        case "go":
            guard let gofmt = Tools.find("gofmt") else { return [] }
            let (_, output) = Shell.run([gofmt, "-e"], cwd: dir, stdin: text, captureStdout: false)
            var found: [Diagnostic] = []
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 3)
                guard parts.count == 4, parts[0] == "<standard input>", let l = Int(parts[1]) else { continue }
                found.append(Diagnostic(path: path, line: l, column: Int(parts[2]), severity: .error,
                                        message: parts[3].trimmingCharacters(in: .whitespaces), source: "gofmt"))
            }
            return found
        case "swift":
            if let root, FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { return [] }
            guard let swiftc = Tools.xcrun("swiftc") else { return [] }
            let (_, output) = Shell.run([swiftc, "-parse", "-"], cwd: dir, stdin: text)
            return Runner.parseDiagnostics(output, cwd: dir, source: "swiftc", stdinPath: path).filter { $0.path == path }
        case "json":
            guard let data = text.data(using: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            do {
                _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed, .json5Allowed])
                return []
            } catch {
                let message = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
                var line = 1
                if let m = message.range(of: #"line (\d+)"#, options: .regularExpression),
                   let n = Int(message[m].dropFirst(5)) { line = n }
                return [Diagnostic(path: path, line: line, column: nil, severity: .error, message: message, source: "json")]
            }
        default:
            return []
        }
    }
}

enum Shell {
    /// Runs a process to completion; returns (status, stdout+stderr).
    @discardableResult
    static func run(_ argv: [String], cwd: URL? = nil, stdin: String? = nil, captureStdout: Bool = true,
                    environment extra: [String: String] = [:], timeout: TimeInterval = 60) -> (Int32, String) {
        guard let first = argv.first else { return (-1, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: first)
        p.arguments = Array(argv.dropFirst())
        if let cwd { p.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env.merge(extra) { $1 }
        p.environment = env
        let out = Pipe()
        p.standardOutput = captureStdout ? out : FileHandle.nullDevice
        p.standardError = out
        let input = Pipe()
        p.standardInput = stdin == nil ? FileHandle.nullDevice : input
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        if let stdin {
            let handle = input.fileHandleForWriting
            DispatchQueue.global().async {
                handle.write(Data(stdin.utf8))
                try? handle.close()
            }
        }
        var data = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut { p.terminate() }
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
