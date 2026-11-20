#if os(iOS)
import FentonUIKit
import UIKit
import XCTest

@MainActor
final class FixedBarTitleTests: XCTestCase {
    func testFixedWritesTheTitleOnceAndRestoreGivesThePlainTitleBack() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("the attributed bar title is iOS 26 and later") }
        let treatment = FentonFixedBarTitle()
        let item = UINavigationItem(title: "Rooms")
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        treatment.update(item: item, fallbackTitle: nil, fixed: true, traits: traits)
        XCTAssertEqual(treatment.writeCount, 1)
        for _ in 0..<3 { treatment.update(item: item, fallbackTitle: nil, fixed: true, traits: traits) }
        XCTAssertEqual(treatment.writeCount, 1, "an unchanged title is not written again")
        let attributed = try XCTUnwrap(item.attributedTitle)
        XCTAssertEqual(String(attributed.characters), "Rooms")
        let font = try XCTUnwrap(attributed.runs.first?.uiKit.font)
        XCTAssertEqual(font.pointSize, 24, accuracy: 0.5)

        treatment.restore()
        XCTAssertEqual(item.title, "Rooms")
        XCTAssertEqual(item.attributedTitle.map { String($0.characters) }, "Rooms", "UIKit reads the plain title back as attributed")
        XCTAssertNotEqual(item.attributedTitle?.runs.first?.uiKit.font?.pointSize, 24, "the fixed font is gone")
        treatment.restore()
        XCTAssertEqual(item.title, "Rooms", "restore is idempotent")
    }

    func testNotFixedWritesNothing() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("the attributed bar title is iOS 26 and later") }
        let treatment = FentonFixedBarTitle()
        let item = UINavigationItem(title: "Plain")
        treatment.update(item: item, fallbackTitle: nil, fixed: false, traits: .current)
        XCTAssertEqual(treatment.writeCount, 0)
        XCTAssertEqual(item.title, "Plain")
    }

    func testTheFallbackTitleIsUsedUntilTheItemHasOne() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("the attributed bar title is iOS 26 and later") }
        let treatment = FentonFixedBarTitle()
        let item = UINavigationItem()
        treatment.update(item: item, fallbackTitle: "From the page", fixed: true, traits: .current)
        XCTAssertEqual(item.attributedTitle.map { String($0.characters) }, "From the page")
        treatment.restore()
        XCTAssertEqual(item.title, "From the page")
    }

    func testARenamedItemIsMirroredOnTheNextTurn() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("the attributed bar title is iOS 26 and later") }
        let treatment = FentonFixedBarTitle()
        let item = UINavigationItem(title: "Old")
        treatment.update(item: item, fallbackTitle: nil, fixed: true, traits: .current)
        item.title = "New"
        XCTAssertEqual(treatment.writeCount, 1, "never inside the change")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(treatment.writeCount, 2)
        XCTAssertEqual(item.attributedTitle.map { String($0.characters) }, "New")
        treatment.restore()
    }

    func testTheFontGrowsWithDynamicTypeUpToTheMaximum() {
        let treatment = FentonFixedBarTitle(pointSize: 24, maximumPointSize: 30)
        let normal = treatment.font(compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        let huge = treatment.font(compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        XCTAssertEqual(normal.pointSize, 24, accuracy: 0.5)
        XCTAssertEqual(huge.pointSize, 30, accuracy: 0.5)
    }

    func testTheBarNeverMinimisesWhileFixed() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("bar minimization is iOS 27 and later") }
        let treatment = FentonFixedBarTitle()
        let item = UINavigationItem(title: "Rail")
        item.navigationBarMinimization.minimizationBehavior = .automatic
        treatment.update(item: item, fallbackTitle: nil, fixed: true, traits: .current)
        XCTAssertEqual(item.navigationBarMinimization.minimizationBehavior, .never)
        treatment.restore()
        XCTAssertEqual(item.navigationBarMinimization.minimizationBehavior, .automatic)
    }
}
#endif
