import XCTest
@testable import SDUICore

final class SDUICoreTests: XCTestCase {

    // MARK: - Decoding

    func testDecodeProductDetailExample() throws {
        let doc = try SDUIParser.decode(Fixtures.productDetail)
        XCTAssertEqual(doc.version, "0.1")
        XCTAssertEqual(doc.screen.id, "product_detail")
        XCTAssertEqual(doc.screen.content.type, "scroll")
        // Data source contract decoded.
        let source = try XCTUnwrap(doc.screen.data?.sources.first)
        XCTAssertEqual(source.id, "product")
        XCTAssertEqual(source.service, "catalog")
        XCTAssertEqual(source.policy, .cacheThenNetwork)
    }

    func testDecodeFeedListTemplate() throws {
        let doc = try SDUIParser.decode(Fixtures.feed)
        XCTAssertEqual(doc.screen.content.type, "list")
        // The list item's tap navigation lives inside modifiers.
        let template = try XCTUnwrap(doc.screen.content.prop("template")?.decode(Component.self))
        XCTAssertEqual(template.modifiers?.onTap?.action, "navigate")
        XCTAssertEqual(template.modifiers?.contextMenu?.count, 2)
    }

    func testUnknownComponentDoesNotThrow() throws {
        // Forward-compatibility: an unknown/custom type must decode, not crash.
        let json = """
        { "version": "0.1", "screen": { "id": "x", "content":
          { "type": "custom.map", "id": "m", "latitude": 55.75 } } }
        """
        let doc = try SDUIParser.decode(json)
        XCTAssertEqual(doc.screen.content.type, "custom.map")
        XCTAssertEqual(doc.screen.content.prop("latitude")?.doubleValue, 55.75)
    }

    func testMissingRequiredKeyProducesReadableError() {
        let json = #"{ "version": "0.1", "screen": { "content": { "type": "text", "value": "hi" } } }"#
        XCTAssertThrowsError(try SDUIParser.decode(json)) { error in
            XCTAssertTrue("\(error)".contains("id"), "Error should name the missing key: \(error)")
        }
    }

    // MARK: - Binding engine

    func testCyclicTokenReferenceTerminates() {
        // Two tokens referencing each other must not hang or crash: the
        // depth-limited resolver bails out and returns a bounded string.
        let cyclic = BindingContext(tokens: .object([
            "a": .string("$token.b"),
            "b": .string("$token.a"),
        ]))
        let v = BindingEngine.resolveString("$token.a", in: cyclic)
        XCTAssertLessThan(v.count, 200, "cyclic token resolution must terminate, not expand unbounded")
    }

    func testConditionNotEquals() throws {
        let cond = try JSONDecoder().decode(Condition.self, from: Data(#"{ "notEquals": ["$env.locale", "en"] }"#.utf8))
        XCTAssertTrue(cond.evaluate(in: ctx()), "locale is 'ru', so notEquals 'en' must be true")
    }

    private func ctx() -> BindingContext {
        BindingContext(
            data: ["product": .object([
                "id": .string("42"),
                "title": .string("Nike Air"),
                "price": .number(129)
            ])],
            tokens: .object([
                "spacing": .object(["md": .number(16)]),
                "color": .object(["primary": .string("#0A84FF")]),
                "button": .object(["primary": .object(["background": .string("$token.color.primary")])])
            ]),
            env: ["locale": .string("ru")],
            state: ["page": .number(1)],
            item: .object(["id": .string("99"), "title": .string("Item 99")])
        )
    }

    func testWholeBindingKeepsType() {
        let v = BindingEngine.resolve("$data.product.price", in: ctx())
        XCTAssertEqual(v.doubleValue, 129)
    }

    func testInterpolation() {
        let v = BindingEngine.resolveString("Hello, $data.product.title (#$data.product.id)", in: ctx())
        XCTAssertEqual(v, "Hello, Nike Air (#42)")
    }

    func testTokenResolution() {
        XCTAssertEqual(BindingEngine.resolve("$token.spacing.md", in: ctx()).doubleValue, 16)
    }

    func testChainedTokenReferenceIsFollowed() {
        // button.primary.background -> "$token.color.primary" -> "#0A84FF"
        let v = BindingEngine.resolveString("$token.button.primary.background", in: ctx())
        XCTAssertEqual(v, "#0A84FF")
    }

    func testItemBindingInsideTemplate() {
        XCTAssertEqual(BindingEngine.resolveString("$item.title", in: ctx()), "Item 99")
    }

    func testEnvAndState() {
        XCTAssertEqual(BindingEngine.resolveString("$env.locale", in: ctx()), "ru")
        XCTAssertEqual(BindingEngine.resolve("$state.page", in: ctx()).doubleValue, 1)
    }

    func testParamsBinding() {
        var context = ctx()
        context.params = ["productId": .string("42")]
        XCTAssertEqual(BindingEngine.resolveString("$params.productId", in: context), "42")
    }

    func testFillPathPlaceholders() {
        var context = ctx()
        context.params = ["productId": .string("42")]
        context.state["lang"] = .string("ru")
        XCTAssertEqual(
            BindingEngine.fillPlaceholders("/products/{productId}?lang={lang}", in: context),
            "/products/42?lang=ru")
    }

    func testUnmatchedPlaceholderIsKept() {
        XCTAssertEqual(BindingEngine.fillPlaceholders("/x/{missing}", in: ctx()), "/x/{missing}")
    }

    func testMissingBindingResolvesToEmpty() {
        XCTAssertEqual(BindingEngine.resolveString("$data.product.missing", in: ctx()), "")
    }

    func testLoneDollarStaysLiteral() {
        // A `$` not followed by an identifier is not a binding.
        XCTAssertEqual(BindingEngine.resolveString("Price: $ 129", in: ctx()), "Price: $ 129")
    }

    func testNonAsciiTextAroundBindingIsPreserved() {
        XCTAssertEqual(BindingEngine.resolveString("Товар: $data.product.title 🎉", in: ctx()),
                       "Товар: Nike Air 🎉")
    }

    func testAdjacentBindingsInterpolate() {
        XCTAssertEqual(BindingEngine.resolveString("$data.product.id/$data.product.title", in: ctx()),
                       "42/Nike Air")
    }

    func testWholeBindingToArrayKeepsType() {
        var context = ctx()
        context.data["feed"] = .object(["items": .array([.string("a"), .string("b")])])
        XCTAssertEqual(BindingEngine.resolve("$data.feed.items", in: context).arrayValue?.count, 2)
    }

    func testTrailingDotIsNotConsumed() {
        // "$data.product." resolves the valid prefix, keeping the trailing dot.
        XCTAssertEqual(BindingEngine.resolveString("$data.product.title.", in: ctx()), "Nike Air.")
    }

    // MARK: - Conditions

    func testConditionEquals() throws {
        let json = #"{ "equals": ["$env.locale", "ru"] }"#
        let cond = try JSONDecoder().decode(Condition.self, from: Data(json.utf8))
        XCTAssertTrue(cond.evaluate(in: ctx()))
    }

    func testConditionAndOrNot() throws {
        let json = #"{ "and": [ { "exists": "$data.product.title" }, { "not": { "equals": ["$env.locale", "en"] } } ] }"#
        let cond = try JSONDecoder().decode(Condition.self, from: Data(json.utf8))
        XCTAssertTrue(cond.evaluate(in: ctx()))
    }
}
