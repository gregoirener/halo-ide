import Foundation
var bad = 0
for lang in Language.all {
    let pattern = lang.grammar.rules.map { "(" + $0.1 + ")" }.joined(separator: "|")
    if pattern.isEmpty { continue }
    do { _ = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) }
    catch { bad += 1; print("BROKEN:", lang.id, error.localizedDescription) }
}
print("languages:", Language.all.count, "broken:", bad)
for name in ["a.cs", "x.php", "y.lua", "Makefile", "Dockerfile", "CMakeLists.txt", "q.zig", "m.ex", "z.hs", "s.asm", "k.tf", "w.proto", "f.f90", "a.glsl", "b.metal", "n.nix", "p.ps1", "r.R", "j.jl", "c.clj", "readme.txt", "weird.qqq", ".env", "x.m", "x.v", "x.dart", "x.kt", "x.sol"] {
    print(name, "→", Language.detect(url: URL(fileURLWithPath: "/tmp/" + name)).name, terminator: " | ")
}
print()
