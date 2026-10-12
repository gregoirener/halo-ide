import Foundation

// fixbench — checks Halo's mistake fixer.
//
//   swiftc -O Sources/Halo/Editor/FixEngine.swift tools/fixbench/main.swift -o /tmp/fixbench
//   /tmp/fixbench cases                       typed-in-order cases must come out fixed
//   /tmp/fixbench scan <family> <dir> <ext>   false alarms on real code
let engine = FixEngine.shared
let args = CommandLine.arguments

/// Types `source` one character at a time; after each character that ends a
/// word, applies the auto-fix Halo would make, like the editor does.
func typeOut(_ source: String, family: String) -> String {
    var text = ""
    for ch in source {
        text.append(ch)
        let boundary = (text as NSString).length - (String(ch) as NSString).length
        guard FixEngine.isBoundary((text as NSString).character(at: boundary)) else { continue }
        for fix in engine.justTyped(in: text, family: family, boundary: boundary, lineFinished: ch == "\n").reversed() {
            text = (text as NSString).replacingCharacters(in: fix.range, with: fix.replacement)
        }
    }
    return text
}

func suggestions(_ text: String, family: String) -> [String] {
    engine.fixes(in: text, family: family).map { "\($0.original) → \($0.label)\($0.auto ? "" : " (suggest)")" }
}

struct Case { let family: String; let typed: String; let expect: String }
struct Suggestion { let family: String; let code: String; let expect: String }

let cases: [Case] = [
    // Python
    Case(family: "python", typed: "import time\ntime.wait(2)\n", expect: "import time\ntime.sleep(2)\n"),
    Case(family: "python", typed: "import time\ntime.slep(1)\n", expect: "import time\ntime.sleep(1)\n"),
    Case(family: "python", typed: "prnit(\"hi\")\n", expect: "print(\"hi\")\n"),
    Case(family: "python", typed: "x = [1, 2]\nx.push(3)\n", expect: "x = [1, 2]\nx.append(3)\n"),
    Case(family: "python", typed: "a = 1\nb = 2\nif a == 1 && b == 2:\n    pass\n", expect: "a = 1\nb = 2\nif a == 1 and b == 2:\n    pass\n"),
    Case(family: "python", typed: "x = 4\nif x = 5:\n    pass\n", expect: "x = 4\nif x == 5:\n    pass\n"),
    Case(family: "python", typed: "def f():\n    retrun 5\n", expect: "def f():\n    return 5\n"),
    Case(family: "python", typed: "import json\ndata = json.parse(\"{}\")\n", expect: "import json\ndata = json.loads(\"{}\")\n"),
    Case(family: "python", typed: "import random\nn = random.randInt(1, 6)\n", expect: "import random\nn = random.randint(1, 6)\n"),
    Case(family: "python", typed: "import math\nr = math.squareRoot(9)\n", expect: "import math\nr = math.sqrt(9)\n"),
    Case(family: "python", typed: "while true:\n    break\n", expect: "while True:\n    break\n"),
    Case(family: "python", typed: "name = \"Ada\"\nif name.length > 3:\n    pass\n", expect: "name = \"Ada\"\nif len(name) > 3:\n    pass\n"),
    Case(family: "python", typed: "s = \"abc\"\nprint(s.toUpperCase())\n", expect: "s = \"abc\"\nprint(s.upper())\n"),
    Case(family: "python", typed: "import datetime\nnow = datetime.now()\n", expect: "import datetime\nnow = datetime.datetime.now()\n"),
    Case(family: "python", typed: "console.log(\"x\")\n", expect: "print(\"x\")\n"),
    Case(family: "python", typed: "print \"hello\"\n", expect: "print(\"hello\")\n"),
    Case(family: "python", typed: "x = None\nif x == null:\n    pass\n", expect: "x = None\nif x == None:\n    pass\n"),
    Case(family: "python", typed: "items = [3, 1]\nn = items.size()\n", expect: "items = [3, 1]\nn = len(items)\n"),
    Case(family: "python", typed: "x = 1\nif x:\n    pass\nelse if x > 2:\n    pass\n", expect: "x = 1\nif x:\n    pass\nelif x > 2:\n    pass\n"),
    Case(family: "python", typed: "words = [\"a\", \"b\"]\ns = words.join(\", \")\n", expect: "words = [\"a\", \"b\"]\ns = \", \".join(words)\n"),
    Case(family: "python", typed: "# time.wait(1) in a comment stays\ns = \"time.wait(1)\"\n", expect: "# time.wait(1) in a comment stays\ns = \"time.wait(1)\"\n"),
    Case(family: "python", typed: "def push(x):\n    pass\nq = []\nq.push(1)\n", expect: "def push(x):\n    pass\nq = []\nq.push(1)\n"),
    Case(family: "python", typed: "improt os\n", expect: "import os\n"),
    Case(family: "python", typed: "form os import path\n", expect: "from os import path\n"),
    Case(family: "python", typed: "def area(r):\n    retunr 3.14 * r * r\n", expect: "def area(r):\n    return 3.14 * r * r\n"),
    Case(family: "python", typed: "class A:\n    def __init__(slef):\n        slef.x = 1\n", expect: "class A:\n    def __init__(self):\n        self.x = 1\n"),
    Case(family: "python", typed: "whiel True:\n    break\n", expect: "while True:\n    break\n"),
    Case(family: "python", typed: "fro i in range(3):\n    pass\n", expect: "for i in range(3):\n    pass\n"),
    Case(family: "python", typed: "x = 1\nif x:\n    pass\nesle:\n    pass\n", expect: "x = 1\nif x:\n    pass\nelse:\n    pass\n"),
    Case(family: "python", typed: "name = inptu(\"Name? \")\n", expect: "name = input(\"Name? \")\n"),
    Case(family: "python", typed: "done = Ture\n", expect: "done = True\n"),
    Case(family: "python", typed: "x = [1]\nprint(lenght(x))\n", expect: "x = [1]\nprint(len(x))\n"),
    Case(family: "python", typed: "items = [1]\nitems.apend(2)\n", expect: "items = [1]\nitems.append(2)\n"),
    Case(family: "javascript", typed: "fucntion add(a, b) {\n}\n", expect: "function add(a, b) {\n}\n"),
    Case(family: "javascript", typed: "cosnt x = 5;\n", expect: "const x = 5;\n"),
    Case(family: "javascript", typed: "function f() {\n  retrun 1;\n}\n", expect: "function f() {\n  return 1;\n}\n"),
    Case(family: "javascript", typed: "consloe.log(\"x\");\n", expect: "console.log(\"x\");\n"),
    Case(family: "javascript", typed: "documnet.title = \"x\";\n", expect: "document.title = \"x\";\n"),
    Case(family: "c", typed: "int main(void) {\n    retrun 0;\n}\n", expect: "int main(void) {\n    return 0;\n}\n"),
    Case(family: "c", typed: "itn x = 5;\n", expect: "int x = 5;\n"),
    Case(family: "c", typed: "int x = 1;\nwhiel (x) {\n}\n", expect: "int x = 1;\nwhile (x) {\n}\n"),
    Case(family: "swift", typed: "fucn greet() {\n}\n", expect: "func greet() {\n}\n"),
    Case(family: "go", typed: "fucn main() {\n}\n", expect: "func main() {\n}\n"),
    Case(family: "java", typed: "pubilc class A {\n}\n", expect: "public class A {\n}\n"),
    Case(family: "java", typed: "Sytem.out.println(\"x\");\n", expect: "System.out.println(\"x\");\n"),
    // JavaScript
    Case(family: "javascript", typed: "console.print(\"x\");\n", expect: "console.log(\"x\");\n"),
    Case(family: "javascript", typed: "const items = [];\nconst n = items.lenght;\n", expect: "const items = [];\nconst n = items.length;\n"),
    Case(family: "javascript", typed: "let x = 1;\nif (x == True) {\n}\n", expect: "let x = 1;\nif (x == true) {\n}\n"),
    Case(family: "javascript", typed: "document.getElementByID(\"a\");\n", expect: "document.getElementById(\"a\");\n"),
    Case(family: "javascript", typed: "let s = \"a\";\ns.upper();\n", expect: "let s = \"a\";\ns.toUpperCase();\n"),
    Case(family: "javascript", typed: "if (a) {\n} elif (b) {\n}\n", expect: "if (a) {\n} else if (b) {\n}\n"),
    Case(family: "javascript", typed: "print(\"hi\");\n", expect: "console.log(\"hi\");\n"),
    Case(family: "javascript", typed: "JSON.stringfy(x);\n", expect: "JSON.stringify(x);\n"),
    Case(family: "javascript", typed: "Math.squareRoot(4);\n", expect: "Math.sqrt(4);\n"),
    Case(family: "javascript", typed: "el.addEventListener(\"onclick\", go);\n", expect: "el.addEventListener(\"click\", go);\n"),
    // C and C++
    Case(family: "c", typed: "#include <stdio>\n", expect: "#include <stdio.h>\n"),
    Case(family: "c", typed: "#include <stdio.h>\nint main(void) {\n    pritnf(\"hi\");\n}\n", expect: "#include <stdio.h>\nint main(void) {\n    printf(\"hi\");\n}\n"),
    Case(family: "c", typed: "void main() {\n}\n", expect: "int main() {\n}\n"),
    Case(family: "c", typed: "#incldue <stdlib.h>\n", expect: "#include <stdlib.h>\n"),
    Case(family: "c", typed: "char name = \"Bob\";\n", expect: "char name[] = \"Bob\";\n"),
    Case(family: "c", typed: "int a[] = [1, 2, 3];\n", expect: "int a[] = {1, 2, 3};\n"),
    Case(family: "c", typed: "int main() {\n    print(\"x\");\n}\n", expect: "int main() {\n    printf(\"x\");\n}\n"),
    Case(family: "cpp", typed: "#include <bits/stdc++.h>\n", expect: "#include <iostream>\n#include <vector>\n#include <string>\n#include <algorithm>\n#include <map>\n#include <set>\n#include <cmath>\n"),
    Case(family: "cpp", typed: "std::cout >> x;\n", expect: "std::cout << x;\n"),
    // Java, Go, Rust, Swift
    Case(family: "java", typed: "System.out.printn(\"x\");\n", expect: "System.out.println(\"x\");\n"),
    Case(family: "java", typed: "string name = \"a\";\n", expect: "String name = \"a\";\n"),
    Case(family: "java", typed: "double r = Math.Sqrt(4);\n", expect: "double r = Math.sqrt(4);\n"),
    Case(family: "go", typed: "import \"fmt\"\nfunc main() {\n\tfmt.println(\"x\")\n}\n", expect: "import \"fmt\"\nfunc main() {\n\tfmt.Println(\"x\")\n}\n"),
    Case(family: "go", typed: "import \"time\"\nfunc main() {\n\ttime.sleep(1)\n}\n", expect: "import \"time\"\nfunc main() {\n\ttime.Sleep(1)\n}\n"),
    Case(family: "rust", typed: "fn main() {\n    println(\"x\");\n}\n", expect: "fn main() {\n    println!(\"x\");\n}\n"),
    Case(family: "swift", typed: "let arr = [1]\nlet n = arr.length\n", expect: "let arr = [1]\nlet n = arr.count\n"),
]

let suggestionCases: [Suggestion] = [
    Suggestion(family: "python", code: "age = input(\"Age? \")\nif age > 18:\n    print(\"adult\")\n", expect: "int(input"),
    Suggestion(family: "python", code: "time.sleep(1)\n", expect: "import time"),
    Suggestion(family: "python", code: "x = randint(1, 6)\n", expect: "from random import randint"),
    Suggestion(family: "python", code: "class P:\n    def __init__(self):\n        self.name = 1\n        self.name += 1\n    def show(self):\n        return self.nmae\n", expect: "nmae → name"),
    Suggestion(family: "javascript", code: "const n = 1;\nn = 2;\n", expect: "const → let"),
    Suggestion(family: "c", code: "int main() {\n    printf(\"x\");\n}\n", expect: "#include <stdio.h>"),
    Suggestion(family: "java", code: "class A { void f() { Scanner s = new Scanner(System.in); } }\n", expect: "import java.util.Scanner;"),
]

switch args.dropFirst().first {
case "cases":
    var failed = 0
    let start = Date()
    for c in cases {
        let got = typeOut(c.typed, family: c.family)
        if got == c.expect { print("  ok    \(c.family): \(c.typed.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "}" }) ?? "")") }
        else {
            failed += 1
            print("  FAIL  \(c.family): typed\n\(c.typed)  got\n\(got)  expected\n\(c.expect)  suggestions: \(suggestions(c.typed, family: c.family))")
        }
    }
    for s in suggestionCases {
        let list = suggestions(s.code, family: s.family)
        if list.contains(where: { $0.contains(s.expect) }) { print("  ok    \(s.family) suggests \(s.expect)") }
        else { failed += 1; print("  FAIL  \(s.family) should suggest \(s.expect); got \(list)") }
    }
    print("\n\(cases.count + suggestionCases.count - failed)/\(cases.count + suggestionCases.count) passed in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    exit(failed == 0 ? 0 : 1)

case "scan":
    guard args.count >= 5 else { print("scan <family> <dir> <ext>"); exit(2) }
    let family = args[2], dir = args[3], ext = args[4]
    let files = (FileManager.default.enumerator(atPath: dir)?.compactMap { $0 as? String } ?? [])
        .filter { $0.hasSuffix("." + ext) && !$0.contains("test") && !$0.contains("/.") }.sorted()
    var lines = 0, total = 0, autos = 0
    var byRule: [String: [String]] = [:]
    let start = Date()
    for file in files {
        guard let text = try? String(contentsOfFile: dir + "/" + file, encoding: .utf8) else { continue }
        lines += text.split(separator: "\n", omittingEmptySubsequences: false).count
        let ns = text as NSString
        for fix in engine.fixes(in: text, family: family) {
            total += 1
            if fix.auto { autos += 1 }
            let lineText = ns.substring(with: ns.lineRange(for: fix.anchor)).trimmingCharacters(in: .whitespacesAndNewlines)
            byRule[fix.rule + (fix.auto ? " [auto]" : ""), default: []].append("\(file): \(fix.original) → \(fix.label)   | \(lineText.prefix(90))")
        }
    }
    print("\(files.count) files, \(lines) lines, \(Int(Date().timeIntervalSince(start) * 1000)) ms — \(total) fixes (\(autos) auto) = \(String(format: "%.2f", Double(total) * 1000 / Double(max(lines, 1)))) per 1k lines")
    for (rule, hits) in byRule.sorted(by: { $0.value.count > $1.value.count }) {
        print("\n[\(rule)] \(hits.count)")
        hits.prefix(Int(args.count > 5 ? args[5] : "6") ?? 6).forEach { print("   " + $0) }
    }

case "time": break
default:
    print("usage: fixbench cases | scan <family> <dir> <ext> | time <family> <file>")
}

// Timing: `fixbench time <family> <file>` — a full scan and a keystroke check at the end.
if args.dropFirst().first == "time", args.count >= 4, let text = try? String(contentsOfFile: args[3], encoding: .utf8) {
    let family = args[2]
    var t = Date()
    let all = engine.fixes(in: text, family: family)
    print("full scan: \(Int(Date().timeIntervalSince(t) * 1000)) ms, \(all.count) fixes, \((text as NSString).length / 1000) KB")
    let typed = text + "\nimport time\ntime.wait("
    t = Date()
    for _ in 0..<5 { _ = engine.justTyped(in: typed, family: family, boundary: (typed as NSString).length - 1) }
    print("keystroke check: \(Int(Date().timeIntervalSince(t) * 200)) ms each → \(engine.justTyped(in: typed, family: family, boundary: (typed as NSString).length - 1).first?.label ?? "none")")
}
