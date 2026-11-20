#if os(iOS)
import FentonUIKit
import UIKit
import XCTest

@MainActor
final class SelfSizingTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private final class CountingLayout: UICollectionViewFlowLayout {
        var invalidations = 0
        override func invalidateLayout() {
            invalidations += 1
            super.invalidateLayout()
        }
    }

    private final class TextCell: UICollectionViewCell {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.numberOfLines = 0
            label.text = String(repeating: "A long line of text that wraps. ", count: 6)
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: contentView.topAnchor), label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
    }

    // MARK: Width

    func testTheLayoutIsInvalidatedWhenTheWidthChangesAndOnlyThen() throws {
        let layout = CountingLayout()
        let list = FentonWidthAwareCollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 400), collectionViewLayout: layout)
        let root = UIViewController()
        window = try LaneBHost.window(showing: root)
        root.view.addSubview(list)
        list.layoutIfNeeded()
        let first = layout.invalidations

        list.setNeedsLayout()
        list.layoutIfNeeded()
        XCTAssertEqual(layout.invalidations, first, "the first width is the one the first measurement used")

        list.frame.size.height = 500
        list.layoutIfNeeded()
        XCTAssertEqual(layout.invalidations, first, "a height change does not drop measured heights")

        list.frame.size.width = 340
        list.layoutIfNeeded()
        XCTAssertEqual(layout.invalidations, first + 1, "a new width drops them once")

        list.layoutIfNeeded()
        XCTAssertEqual(layout.invalidations, first + 1)
    }

    func testControlsKeepTheirTouchUnlessTheyTrackADrag() {
        let list = FentonWidthAwareCollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        XCTAssertTrue(list.touchesShouldCancel(in: UIButton()), "a tile scrolls the list")
        XCTAssertTrue(list.touchesShouldCancel(in: UIView()))
        for control in [UISlider(), UISwitch(), UIStepper()] as [UIView] {
            XCTAssertFalse(list.touchesShouldCancel(in: control), "\(type(of: control)) keeps its drag")
        }
        XCTAssertFalse(list.touchesShouldCancel(in: UITextField()))
    }

    // MARK: Fitting

    func testAFittedCellTakesTheProposedWidthAndTheHeightItNeedsThere() {
        let cell = TextCell(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let narrow = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        narrow.size = CGSize(width: 120, height: 44)
        let wide = narrow.copy() as? UICollectionViewLayoutAttributes ?? narrow
        wide.size = CGSize(width: 600, height: 44)

        let fittedNarrow = cell.fentonFitted(narrow)
        let fittedWide = cell.fentonFitted(wide)
        XCTAssertEqual(fittedNarrow.size.width, 120)
        XCTAssertEqual(fittedWide.size.width, 600)
        XCTAssertGreaterThan(fittedNarrow.size.height, fittedWide.size.height, "the labels re-wrap at each width")
        XCTAssertEqual(fittedNarrow.size.height, ceil(fittedNarrow.size.height), "whole points")
        XCTAssertEqual(narrow.size, CGSize(width: 120, height: 44), "the layout's own attributes are not changed")
    }

    func testAnUnmeasuredWidthIsLeftAlone() {
        let cell = TextCell(frame: .zero)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.size = CGSize(width: 0, height: 44)
        XCTAssertEqual(cell.fentonFitted(attributes).size, CGSize(width: 0, height: 44), "a width of zero would wrap to nothing")
    }
}
#endif
