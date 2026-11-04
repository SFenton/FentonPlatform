#if canImport(UIKit)
import XCTest
import UIKit
import FentonUIKit

@MainActor
final class UIKitHostTests: XCTestCase {
    func testPageHostEmbedsControllerAndRegistersScrollView() {
        let page = FentonPageContainerViewController()
        let child = UIViewController()
        page.loadViewIfNeeded()
        page.embed(child)
        let scroll = UIScrollView()
        page.registerMainScrollView(scroll)
        XCTAssertTrue(child.parent === page)
        XCTAssertEqual(scroll.contentInsetAdjustmentBehavior, .never)
    }

    func testReplacingPageContentRestoresRetainedOldScrollView() {
        let page = FentonPageContainerViewController()
        let first = UIViewController()
        let firstScroll = UIScrollView()
        firstScroll.contentInsetAdjustmentBehavior = .automatic
        firstScroll.contentInset.bottom = 17
        firstScroll.scrollIndicatorInsets.bottom = 19
        page.loadViewIfNeeded()
        page.embed(first, mainScrollView: firstScroll)
        page.embed(UIViewController())

        XCTAssertEqual(firstScroll.contentInsetAdjustmentBehavior, .automatic)
        XCTAssertEqual(firstScroll.contentInset.bottom, 17, accuracy: 0.01)
        XCTAssertEqual(firstScroll.scrollIndicatorInsets.bottom, 19, accuracy: 0.01)
    }

    func testContentContainmentViewCanBeComposedIntoAnExistingBase() {
        let containment = FentonContentContainmentView(frame: .zero)
        let content = UIView()
        let scroll = UIScrollView()
        containment.installContentView(content)
        containment.registerMainScrollView(scroll)
        containment.layoutIfNeeded()
        XCTAssertTrue(content.superview === containment.contentView)
        XCTAssertEqual(scroll.contentInsetAdjustmentBehavior, .never)
    }

    func testContainmentPreservesAndRestoresExistingScrollInsets() {
        let containment = FentonContentContainmentView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let first = UIScrollView()
        first.contentInsetAdjustmentBehavior = .automatic
        first.contentInset = UIEdgeInsets(top: 1, left: 2, bottom: 9, right: 4)
        first.scrollIndicatorInsets = UIEdgeInsets(top: 3, left: 4, bottom: 7, right: 5)
        containment.registerMainScrollView(first)

        let accessory = UIView()
        containment.registerAccessoryView(accessory, clearance: 6)
        let height = accessory.heightAnchor.constraint(equalToConstant: 24)
        height.isActive = true
        containment.layoutIfNeeded()
        XCTAssertEqual(first.contentInset.bottom, 39, accuracy: 0.01)
        XCTAssertEqual(first.scrollIndicatorInsets.bottom, 37, accuracy: 0.01)
        let expectedContentBottom = first.contentInset.bottom
        let expectedIndicatorBottom = first.scrollIndicatorInsets.bottom
        containment.layoutIfNeeded()
        XCTAssertEqual(first.contentInset.bottom, expectedContentBottom, accuracy: 0.01)
        XCTAssertEqual(first.scrollIndicatorInsets.bottom, expectedIndicatorBottom, accuracy: 0.01)

        let second = UIScrollView()
        second.contentInsetAdjustmentBehavior = .scrollableAxes
        second.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 11, right: 0)
        second.scrollIndicatorInsets = UIEdgeInsets(top: 4, left: 0, bottom: 13, right: 0)
        containment.registerMainScrollView(second)
        XCTAssertEqual(first.contentInsetAdjustmentBehavior, .automatic)
        XCTAssertEqual(first.contentInset.bottom, 9, accuracy: 0.01)
        XCTAssertEqual(second.contentInsetAdjustmentBehavior, .never)
        XCTAssertEqual(second.contentInset.bottom, 41, accuracy: 0.01)
        XCTAssertEqual(second.scrollIndicatorInsets.bottom, 43, accuracy: 0.01)

        containment.clearAccessoryView()
        XCTAssertEqual(second.contentInset, UIEdgeInsets(top: 2, left: 0, bottom: 11, right: 0))
        XCTAssertEqual(second.scrollIndicatorInsets, UIEdgeInsets(top: 4, left: 0, bottom: 13, right: 0))
        containment.unregisterMainScrollView()
        XCTAssertEqual(second.contentInsetAdjustmentBehavior, .scrollableAxes)
        XCTAssertEqual(second.contentInset.bottom, 11, accuracy: 0.01)
        XCTAssertEqual(second.scrollIndicatorInsets.bottom, 13, accuracy: 0.01)
    }

    func testContentInsetsOverrideSupportsZeroAsymmetricAndSystemReset() {
        let containment = FentonContentContainmentView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        containment.layoutIfNeeded()
        let systemFrame = containment.contentView.frame

        containment.contentInsetsOverride = .zero
        containment.layoutIfNeeded()
        XCTAssertEqual(containment.contentView.frame, containment.bounds)

        containment.contentInsetsOverride = UIEdgeInsets(top: 10, left: 21, bottom: 32, right: 43)
        containment.layoutIfNeeded()
        let expected = CGRect(
            x: 21,
            y: 10,
            width: containment.bounds.width - 21 - 43,
            height: containment.bounds.height - 10 - 32
        )
        XCTAssertEqual(containment.contentView.frame, expected)
        containment.layoutIfNeeded()
        XCTAssertEqual(containment.contentView.frame, expected)

        containment.contentInsetsOverride = nil
        containment.layoutIfNeeded()
        XCTAssertEqual(containment.contentView.frame, systemFrame)
    }

    func testSheetConfigurationUsesNativeDetents() {
        let controller = UIViewController()
        controller.loadViewIfNeeded()
        FentonSheetPresenter.configure(controller)
        XCTAssertEqual(controller.modalPresentationStyle, .pageSheet)
    }
}
#endif
