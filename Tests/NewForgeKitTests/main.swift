import Foundation
@testable import NewForgeKit

// Tiny hand-rolled test harness: Command Line Tools ship without the
// XCTest bundle layout xcodebuild normally provides, so we assert and
// report manually. Each test is a small function; `check` records failures.

var failures: [String] = []
var currentTest = ""

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    if !condition() {
        failures.append("[\(currentTest)] \(message) (\(file):\(line))")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #fileID, line: Int = #line) {
    if a != b {
        failures.append("[\(currentTest)] \(message) - got \(a), expected \(b) (\(file):\(line))")
    }
}

func expectThrows(_ body: () throws -> Void, _ message: String, file: String = #fileID, line: Int = #line) {
    do {
        try body()
        failures.append("[\(currentTest)] \(message) - expected throw (\(file):\(line))")
    } catch {}
}

func test(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    do {
        try body()
        print("PASS  \(name)")
    } catch {
        failures.append("[\(name)] threw: \(error)")
        print("FAIL  \(name)")
    }
}

// Fixed clock: 2026-10-17 09:05 local time.
let now = Calendar(identifier: .gregorian).date(from: DateComponents(
    year: 2026, month: 10, day: 17, hour: 9, minute: 5))!

func ctx(_ filename: String = "report") -> RenderContext {
    RenderContext(filename: filename, dirname: "mydir", now: now)
}

// MARK: - renderer

try test("renderer substitutes all variables") {
    let out = TemplateRenderer.render(
        "{{filename}}|{{date}}|{{time}}|{{datetime}}|{{year}}|{{month}}|{{day}}|{{dirname}}",
        context: ctx())
    expectEqual(out, "report|2026-10-17|09-05|2026-10-17 09:05|2026|10|17|mydir")
}

try test("renderer handles datetime before date") {
    expectEqual(TemplateRenderer.render("{{datetime}}", context: ctx()), "2026-10-17 09:05")
}

try test("renderer leaves unknown placeholders alone") {
    expectEqual(TemplateRenderer.render("{{unknown}} {{date}}", context: ctx()),
                "{{unknown}} 2026-10-17")
}

// MARK: - file name handling

try test("sanitize trims and validates") {
    expectEqual(try FileCreator.sanitizeFileName("  hello  "), "hello")
    expectThrows({ _ = try FileCreator.sanitizeFileName("") }, "empty should throw")
    expectThrows({ _ = try FileCreator.sanitizeFileName("a/b") }, "slash should throw")
    expectThrows({ _ = try FileCreator.sanitizeFileName("a:b") }, "colon should throw")
    expectThrows({ _ = try FileCreator.sanitizeFileName(".") }, "dot should throw")
    expectThrows({ _ = try FileCreator.sanitizeFileName(String(repeating: "x", count: 300)) },
                 "long name should throw")
}

try test("uniquify appends counters") {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("newforge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let first = FileCreator.uniquifiedURL(for: "note", ext: "md", in: tmp)
    expectEqual(first.lastPathComponent, "note.md")
    FileManager.default.createFile(atPath: first.path, contents: Data())
    let second = FileCreator.uniquifiedURL(for: "note", ext: "md", in: tmp)
    expectEqual(second.lastPathComponent, "note 2.md")
}

test("dotfile template does not get a duplicate extension") {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("newforge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // The gitignore template has defaultName ".gitignore" and fileExtension
    // "gitignore". The creator must not produce ".gitignore.gitignore".
    let url = FileCreator.uniquifiedURL(for: ".gitignore", ext: "gitignore", in: tmp)
    expectEqual(url.lastPathComponent, ".gitignore")

    // A second invocation should still uniquify without doubling the ext.
    FileManager.default.createFile(atPath: url.path, contents: Data())
    let second = FileCreator.uniquifiedURL(for: ".gitignore", ext: "gitignore", in: tmp)
    expectEqual(second.lastPathComponent, ".gitignore 2")
}

// MARK: - smart naming derivation

func makeTemplate(_ base: URL, _ rel: String, defaultName: [String: String], content: String, kind: String = "text") throws -> Template {
    let dir = base.appendingPathComponent(rel, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json: [String: Any] = [
        "id": rel.replacingOccurrences(of: "/", with: "."),
        "name": ["en": rel],
        "fileExtension": "txt",
        "group": "dev",
        "defaultName": defaultName,
        "prompt": false,
        "openAfterCreate": false,
        "kind": kind,
    ]
    let jsonData = try JSONSerialization.data(withJSONObject: json)
    try jsonData.write(to: dir.appendingPathComponent("template.json"))
    try content.write(to: dir.appendingPathComponent("content.txt"), atomically: true, encoding: .utf8)
    let store = TemplateStore(builtinRoot: base, userRoot: base.appendingPathComponent("empty"))
    return store.load().templates.first!
}

try test("smart naming asks when filename is in defaultName") {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("newforge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let t = try makeTemplate(tmp, "dev/usesname",
                             defaultName: ["en": "{{filename}}-note"],
                             content: "static")
    check(t.usesFilenameAsData, "defaultName references filename")
}

try test("smart naming asks when filename is in content") {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("newforge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let t = try makeTemplate(tmp, "dev/incontent",
                             defaultName: ["en": "script"],
                             content: "# {{filename}} by {{user}}")
    check(t.usesFilenameAsData, "content references filename")
}

try test("smart naming silent for generic document") {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("newforge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let t = try makeTemplate(tmp, "office/plain",
                             defaultName: ["en": "Untitled"],
                             content: "just plain content")
    check(!t.usesFilenameAsData, "no filename reference anywhere")
}

try test("settings load reads explicit file") {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("newforge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let url = tmp.appendingPathComponent("settings.json")
    let json = """
    {"alwaysPrompt":true,"neverPrompt":false,"autoOpen":false,"disabledIDs":["dev.python"]}
    """
    try json.write(to: url, atomically: true, encoding: .utf8)

    let settings = SettingsStore.load(from: url)
    check(settings.namingPolicy == .prompt, "alwaysPrompt should resolve to prompt")
    check(!settings.autoOpen, "autoOpen should decode")
    check(settings.disabledIDs == ["dev.python"], "disabledIDs should decode")

    try "not-json".write(to: url, atomically: true, encoding: .utf8)
    expectEqual(SettingsStore.load(from: url).namingPolicy, .smart,
                "invalid settings should fall back to smart")
}

// MARK: - store + creator end to end

func makeTemplateDir(_ base: URL, _ rel: String, _ json: String, _ content: String, _ contentName: String) throws {
    let dir = base.appendingPathComponent(rel, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try json.write(to: dir.appendingPathComponent("template.json"), atomically: true, encoding: .utf8)
    try content.write(to: dir.appendingPathComponent(contentName), atomically: true, encoding: .utf8)
}

try test("text template renders end to end") {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("newforge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    try makeTemplateDir(tmp, "builtin/dev/python",
        """
        {"id":"dev.python","name":{"en":"Python","zh-Hans":"脚本"},
         "fileExtension":"py","group":"dev","defaultName":{"en":"script"},
         "prompt":true,"openAfterCreate":true,"kind":"text"}
        """,
        "# {{filename}} by {{user}} on {{date}}\n", "content.py")

    let store = TemplateStore(builtinRoot: tmp.appendingPathComponent("builtin"),
                              userRoot: tmp.appendingPathComponent("empty"))
    let result = store.load()
    expectEqual(result.templates.count, 1, "one template")
    check(result.errors.isEmpty, "no errors")

    let out = tmp.appendingPathComponent("out", isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let url = try FileCreator.create(from: result.templates[0], baseName: "hello", in: out)
    expectEqual(url.lastPathComponent, "hello.py")
    let text = try String(contentsOf: url, encoding: .utf8)
    check(text.hasPrefix("# hello by "), "renders filename and user, got: \(text)")
}

try test("user template shadows builtin with same id") {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("newforge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    for root in ["builtin", "user"] {
        try makeTemplateDir(tmp, "\(root)/dev/x",
            """
            {"id":"dev.x","name":{"en":"\(root) name"},
             "fileExtension":"txt","group":"dev","defaultName":{"en":"u"},
             "prompt":false,"openAfterCreate":false,"kind":"text"}
            """,
            "x", "content.txt")
    }
    let store = TemplateStore(builtinRoot: tmp.appendingPathComponent("builtin"),
                              userRoot: tmp.appendingPathComponent("user"))
    let result = store.load()
    expectEqual(result.templates.count, 1, "shadowing keeps one entry")
    expectEqual(result.templates.first?.localizedName(locale: Locale(identifier: "en")), "user name")
    expectEqual(result.templates.first?.origin, "user")
}

test("broken template is collected, not fatal") {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("newforge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let dir = tmp.appendingPathComponent("builtin/dev/broken", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "{ not json".write(to: dir.appendingPathComponent("template.json"),
                           atomically: true, encoding: .utf8)
    let store = TemplateStore(builtinRoot: tmp.appendingPathComponent("builtin"),
                              userRoot: tmp.appendingPathComponent("user"))
    let result = store.load()
    expectEqual(result.templates.count, 0)
    expectEqual(result.errors.count, 1)
}

// MARK: - summary

print("")
if failures.isEmpty {
    print("All tests passed.")
} else {
    print("\(failures.count) failure(s):")
    for f in failures { print("  - \(f)") }
    exit(1)
}
