import Foundation
let args = CommandLine.arguments
let engine = FillEngine.shared

func family(_ ext: String) -> String { FillEngine.family(for: URL(fileURLWithPath: "/tmp/x." + ext)) }

/// Simulates a user who only presses Tab (or Enter when nothing is offered).
func tabThrough(ext: String, seed: String, steps: Int) {
    var text = seed.replacingOccurrences(of: "\\n", with: "\n")
    var caret = text.utf16.count
    // The editor auto-pairs brackets.
    if text.hasSuffix("(") { text += ")" } else if text.hasSuffix("[") { text += "]" } else if text.hasSuffix("{") { text += "}" }
    var tabs = 0, enters = 0
    for _ in 0..<steps {
        let ns = text as NSString
        if let s = engine.suggestNow(.init(text: text, caret: caret, family: family(ext), fileURL: nil, indentUnit: ["py", "c", "cpp", "java", "swift"].contains(ext) ? 4 : 2)) {
            // Accept: replace auto-inserted closers the suggestion already contains.
            let lineEnd = ns.lineRange(for: NSRange(location: caret, length: 0))
            var restLen = NSMaxRange(lineEnd) - caret
            if restLen > 0, ns.character(at: NSMaxRange(lineEnd) - 1) == 10 { restLen -= 1 }
            let rest = ns.substring(with: NSRange(location: caret, length: restLen)).trimmingCharacters(in: .whitespaces)
            let replace = !rest.isEmpty && !s.hasPrefix("\n") && s.contains(rest) ? restLen : 0
            text = ns.replacingCharacters(in: NSRange(location: caret, length: replace), with: s)
            var advance = (s as NSString).length
            if let r = s.range(of: "\n *$", options: .regularExpression), r.lowerBound != s.startIndex { advance -= (String(s[r]) as NSString).length }
            caret += advance
            tabs += 1
        } else {
            // Enter with auto-indent.
            let line = ns.substring(with: ns.lineRange(for: NSRange(location: max(0, caret - 1), length: 0)))
            var indent = String(line.prefix { $0 == " " })
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasSuffix(":") || t.hasSuffix("{") { indent += ["py", "c", "cpp", "java", "swift"].contains(ext) ? "    " : "  " }
            let insert = "\n" + indent
            text = ns.replacingCharacters(in: NSRange(location: caret, length: 0), with: insert)
            caret += (insert as NSString).length
            enters += 1
            if enters > 3 { break }
        }
    }
    print("── \(ext): \"\(seed)\"  →  \(tabs) Tabs, \(enters) Enters")
    print(text)
    print()
}

if args[1] == "case" {
    // fillbench case <ext> <file>   — suggestion at the end of the file's text
    let text = try! String(contentsOfFile: args[3], encoding: .utf8)
    let s = engine.suggestNow(.init(text: text, caret: text.utf16.count, family: family(args[2]), fileURL: nil, indentUnit: 4))
    print("suggestion: «\(s ?? "none")»")
    exit(0)
}
if args[1] == "tab" {
    tabThrough(ext: args[2], seed: args[3], steps: Int(args.count > 4 ? args[4] : "14")!)
    exit(0)
}
// fillbench type <ext> <targetFile> : simulate typing a file in an empty project (library only)
if args[1] == "type" {
    let target = URL(fileURLWithPath: args[3])
    let goal = Array((try! String(contentsOf: target, encoding: .utf8)).utf16)
    var typed: [UInt16] = [], typedChars = 0, filled = 0, accepts = 0, shown = 0
    while typed.count < goal.count {
        if let s = engine.suggestNow(.init(text: String(utf16CodeUnits: typed, count: typed.count), caret: typed.count, family: family(args[2]), fileURL: nil, indentUnit: 4)) {
            shown += 1
            let su = Array(s.utf16)
            if typed.count + su.count <= goal.count, Array(goal[typed.count..<(typed.count + su.count)]) == su {
                typed += su; filled += su.count; accepts += 1; continue
            }
        }
        let c = goal[typed.count]; typed.append(c); typedChars += 1
        if c == 10 { while typed.count < goal.count, goal[typed.count] == 32 { typed.append(32) } }
    }
    print(String(format: "%@: Tab wrote %.1f%% | suggestion shown at %d of %d keystrokes | exact %.0f%%", target.lastPathComponent,
                 100 * Double(filled) / Double(filled + typedChars), shown, typedChars + accepts, 100 * Double(accepts) / Double(max(shown, 1))))
    exit(0)
}
