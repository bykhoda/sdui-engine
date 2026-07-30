import XCTest
import Foundation
@testable import SDUICore
@testable import SDUIRuntime

/// Runs the SHARED conformance corpus (spec/conformance/fixtures) through the native
/// engine, proving the Swift BindingEngine / Condition / ActionInterpreter agree with
/// the JS reference (spec/conformance/check.mjs). Same fixtures, two languages → the
/// "identical on every platform" gate. See docs/blueprint/09-conformance-fixtures.md.
final class ConformanceTests: XCTestCase {

    // MARK: - Fixture loading

    /// Repo root, derived from this file's path (…/ios/Tests/SDUIConformanceTests/…).
    private static let fixturesDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SDUIConformanceTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // ios/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("spec/conformance/fixtures")
    }()

    private static let defaultTokens: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spec/schema/tokens.example.json")
    }()

    private struct Fixture {
        let id: String
        let dir: URL
        let expect: JSONValue
        var stateURL: URL { dir.appendingPathComponent("state.json") }
        var actionURL: URL { dir.appendingPathComponent("action.json") }
        var tokensURL: URL { dir.appendingPathComponent("tokens.json") }
    }

    private func fixtures() throws -> [Fixture] {
        let fm = FileManager.default
        let dirs = try fm.contentsOfDirectory(at: Self.fixturesDir, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try dirs.map { dir in
            let expect = try loadJSON(dir.appendingPathComponent("expect.json"))
            return Fixture(id: dir.lastPathComponent, dir: dir, expect: expect)
        }
    }

    private func loadJSON(_ url: URL) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func loadJSONIfExists(_ url: URL) -> JSONValue? {
        FileManager.default.fileExists(atPath: url.path) ? try? loadJSON(url) : nil
    }
    private func objDict(_ v: JSONValue?) -> [String: JSONValue] {
        if case .object(let d)? = v { return d }; return [:]
    }

    private func context(for f: Fixture) throws -> BindingContext {
        let tokens = try loadJSON(FileManager.default.fileExists(atPath: f.tokensURL.path) ? f.tokensURL : Self.defaultTokens)
        let s = objDict(loadJSONIfExists(f.stateURL))
        return BindingContext(data: objDict(s["data"]), tokens: tokens, env: objDict(s["env"]),
                              state: objDict(s["state"]), params: objDict(s["params"]), item: s["item"])
    }

    // MARK: - Aspect: bindings

    func testBindings() throws {
        for f in try fixtures() {
            guard case .object(let binds)? = f.expect["bindings"] else { continue }
            let ctx = try context(for: f)
            for (input, want) in binds {
                let got = BindingEngine.resolveString(input, in: ctx)
                XCTAssertEqual(got, want.stringValue, "[\(f.id)] binding \"\(input)\"")
            }
        }
    }

    // MARK: - Aspect: conditions

    func testConditions() throws {
        for f in try fixtures() {
            guard case .array(let conds)? = f.expect["conditions"] else { continue }
            let ctx = try context(for: f)
            for (i, entry) in conds.enumerated() {
                guard let cond = entry["expr"]?.decode(Condition.self), let want = entry["value"]?.boolValue else {
                    XCTFail("[\(f.id)] condition[\(i)] malformed"); continue
                }
                XCTAssertEqual(cond.evaluate(in: ctx), want, "[\(f.id)] condition[\(i)]")
            }
        }
    }

    // MARK: - Aspect: effects

    @MainActor
    func testEffects() async throws {
        for f in try fixtures() {
            guard case .array(let want)? = f.expect["effects"] else { continue }
            let action = try JSONDecoder().decode(Action.self, from: Data(contentsOf: f.actionURL))
            let host = RecordingHost()
            await ActionInterpreter(host: host).run(action, ctx: try context(for: f))

            XCTAssertEqual(host.effects.count, want.count, "[\(f.id)] effect count — got \(host.effects)")
            guard host.effects.count == want.count else { continue }
            for (i, exp) in want.enumerated() {
                XCTAssertTrue(subset(exp, host.effects[i]), "[\(f.id)] effect[\(i)] = \(host.effects[i]), expected ⊇ \(exp)")
            }
        }
    }

    /// The `request` action runs onSuccess on a successful load, onError otherwise.
    @MainActor
    func testRequestBranches() async throws {
        let json = """
        {"action":"request","source":{"id":"cart","service":"api","path":"/cart"},
         "onSuccess":{"action":"showToast","message":"ok"},
         "onError":{"action":"showToast","message":"err"}}
        """
        let action = try JSONDecoder().decode(Action.self, from: Data(json.utf8))
        let ok = RecordingHost(); ok.requestSucceeds = true
        await ActionInterpreter(host: ok).run(action, ctx: BindingContext())
        XCTAssertTrue(ok.effects.contains { subset(.object(["type": .string("showToast"), "message": .string("ok")]), $0) },
                      "request success must run onSuccess; got \(ok.effects)")
        let err = RecordingHost(); err.requestSucceeds = false
        await ActionInterpreter(host: err).run(action, ctx: BindingContext())
        XCTAssertTrue(err.effects.contains { subset(.object(["type": .string("showToast"), "message": .string("err")]), $0) },
                      "request failure must run onError; got \(err.effects)")
    }

    /// `expected` (a JSONValue object) is an ordered subset of `actual` (extra keys allowed).
    private func subset(_ expected: JSONValue, _ actual: JSONValue) -> Bool {
        if case .object(let e) = expected {
            guard case .object(let a) = actual else { return false }
            return e.allSatisfy { k, v in a[k].map { subset(v, $0) } ?? false }
        }
        return expected == actual
    }
}

/// An `ActionHost` that records each side effect as a JSONValue, so the interpreter's
/// output can be diffed against the fixture's `expect.effects`. Mirrors the shapes the
/// JS reference (action.mjs) records.
@MainActor
final class RecordingHost: ActionHost {
    var effects: [JSONValue] = []
    private func push(_ type: String, _ extra: [String: JSONValue] = [:]) {
        var o: [String: JSONValue] = ["type": .string(type)]; for (k, v) in extra { o[k] = v }
        effects.append(.object(o))
    }
    func track(_ tag: AnalyticsTag) async { push("analytics", ["event": .string(tag.event ?? "")]) }
    func navigate(to screen: String, params: [String: JSONValue], transition: String) async {
        push("navigate", ["to": .string(screen), "transition": .string(transition)])
    }
    func dismiss() async { push("dismiss") }
    func dismissRoot() async { push("dismissRoot") }
    func openURL(_ url: String) async { push("openURL", ["url": .string(url)]) }
    func setState(key: String, value: JSONValue) async { push("setState", ["key": .string(key), "value": value]) }
    func refresh(sources: [String]) async { push("refresh", ["sources": .array(sources.map { .string($0) })]) }
    func showToast(message: String, style: String?) async {
        push("showToast", style.map { ["message": .string(message), "style": .string($0)] } ?? ["message": .string(message)])
    }
    func scrollTo(id: String) async { push("scrollTo", ["target": .string(id)]) }
    func haptic(_ style: String?) async { push("haptic", style.map { ["style": .string($0)] } ?? [:]) }
    func share(text: String?, url: String?) async {
        var e: [String: JSONValue] = [:]; if let t = text { e["text"] = .string(t) }; if let u = url { e["url"] = .string(u) }
        push("share", e)
    }
    func preview(urls: [String], index: Int) async { push("preview", ["urls": .array(urls.map { .string($0) }), "index": .number(Double(index))]) }
    func log(_ message: String) async { push("log", ["message": .string(message)]) }
    func custom(name: String, payload: JSONValue?) async {
        push("custom", payload.map { ["name": .string(name), "payload": $0] } ?? ["name": .string(name)])
    }
    /// Configurable outcome so a test can drive the request onSuccess/onError branch.
    var requestSucceeds = true
    func request(source: DataSource) async -> Bool {
        push("request", ["source": .string(source.id)])
        return requestSucceeds
    }
}
