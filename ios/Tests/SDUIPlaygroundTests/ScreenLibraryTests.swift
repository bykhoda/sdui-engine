import XCTest
@testable import SDUIPlayground

/// Verifies the sandbox's resource pipeline: bundled screens load from
/// `Resources/screens/*.json`, are structurally valid, and tokens resolve.
final class ScreenLibraryTests: XCTestCase {

    func testBundledScreensLoad() {
        let examples = ScreenLibrary.bundledExamples()
        XCTAssertGreaterThanOrEqual(examples.count, 2, "Expected the bundled starter screens to load.")
        XCTAssertTrue(examples.allSatisfy { !$0.name.isEmpty })
        XCTAssertTrue(examples.allSatisfy { !$0.json.isEmpty })
    }

    func testCatalogGroupsScreensIntoCategories() {
        let catalog = ScreenLibrary.catalog()
        XCTAssertGreaterThanOrEqual(catalog.count, 5, "Expected several feature categories.")
        XCTAssertTrue(catalog.allSatisfy { !$0.examples.isEmpty }, "Every category should resolve at least one screen.")
        // The catalog references screens by id — a typo would drop the screen.
        let named = catalog.flatMap(\.examples).count
        XCTAssertGreaterThanOrEqual(named, 10, "Expected the full showcase to resolve.")
    }

    func testNavigationScreensResolveById() {
        XCTAssertNotNil(ScreenLibrary.document(withId: "nav_home"))
        XCTAssertNotNil(ScreenLibrary.document(withId: "discover"))
    }

    func testTokensLoad() {
        let tokens = ScreenLibrary.tokens()
        XCTAssertNotNil(tokens["spacing"]?["md"]?.doubleValue,
                        "Expected spacing tokens to be present in the bundled token set.")
    }
}
