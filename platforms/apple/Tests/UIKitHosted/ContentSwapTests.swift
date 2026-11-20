#if os(iOS)
import FentonUIKit
import UIKit
import XCTest

@MainActor
final class ContentSwapTests: XCTestCase {
    private enum Tab: Equatable { case one, two, three }

    private var window: UIWindow?
    private var made: [Tab] = []
    private var swapped: [Tab] = []
    private var containerAlphaAtSwap: [CGFloat] = []

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func makeSwap(reduceMotion: Bool, initial: Tab = .one) throws -> FentonContentSwapView<Tab> {
        made = []
        swapped = []
        containerAlphaAtSwap = []
        let swap = FentonContentSwapView<Tab>(initial: initial, reduceMotion: { reduceMotion }) { [unowned self] tab in
            made.append(tab)
            let view = UIView()
            view.accessibilityIdentifier = "\(tab)"
            return view
        }
        let root = UIViewController()
        window = try LaneBHost.window(showing: root)
        swap.frame = root.view.bounds
        root.view.addSubview(swap)
        swap.timing.fadeOut = 0.02
        swap.timing.fadeIn = 0.02
        swap.timing.layout = 0.02
        swap.didSwap = { [unowned swap, unowned self] key in
            swapped.append(key)
            containerAlphaAtSwap.append(swap.subviews.first?.alpha ?? -1)
        }
        return swap
    }

    private func shownIdentifier(_ swap: FentonContentSwapView<Tab>) -> String? {
        swap.subviews.first?.subviews.first?.accessibilityIdentifier
    }

    func testStartsOnTheInitialKeyWithItsContent() throws {
        let swap = try makeSwap(reduceMotion: false)
        XCTAssertEqual(swap.displayed, .one)
        XCTAssertEqual(swap.target, .one)
        XCTAssertEqual(shownIdentifier(swap), "one")
        XCTAssertFalse(swap.isTransitioning)
        XCTAssertEqual(FentonContentSwapView<Tab>.Timing(), FentonContentSwapView<Tab>.Timing())
        XCTAssertEqual(FentonContentSwapView<Tab>.Timing().fadeOut, 0.13)
        XCTAssertEqual(FentonContentSwapView<Tab>.Timing().fadeIn, 0.17)
        XCTAssertEqual(FentonContentSwapView<Tab>.Timing().layout, 0.28)
    }

    func testReduceMotionSwapsAtOnceWithoutATransition() throws {
        let swap = try makeSwap(reduceMotion: true)
        swap.show(.two)
        XCTAssertEqual(swap.displayed, .two)
        XCTAssertFalse(swap.isTransitioning)
        XCTAssertEqual(shownIdentifier(swap), "two")
        XCTAssertEqual(swapped, [.two])
        XCTAssertEqual(containerAlphaAtSwap, [1])

        swap.show(.two)
        XCTAssertEqual(swapped, [.two], "the same key swaps nothing")
    }

    func testTheSwapHappensWhileTheContentIsHidden() throws {
        let swap = try makeSwap(reduceMotion: false)
        swap.show(.two)
        XCTAssertTrue(swap.isTransitioning)
        XCTAssertEqual(swap.displayed, .one, "the old content stays until it has faded out")
        XCTAssertTrue(LaneBHost.spin(until: { !swap.isTransitioning }))
        XCTAssertEqual(swap.displayed, .two)
        XCTAssertEqual(swapped, [.two])
        XCTAssertEqual(containerAlphaAtSwap, [0], "didSwap runs while hidden")
        XCTAssertEqual(swap.subviews.first?.alpha, 1)
        XCTAssertEqual(shownIdentifier(swap), "two")
    }

    func testRapidKeysSettleOnTheLastOne() throws {
        let swap = try makeSwap(reduceMotion: false)
        swap.show(.two)
        swap.show(.three)
        swap.show(.two)
        swap.show(.three)
        XCTAssertEqual(swap.target, .three)
        XCTAssertTrue(LaneBHost.spin(until: { !swap.isTransitioning }))
        XCTAssertEqual(swap.displayed, .three)
        XCTAssertEqual(shownIdentifier(swap), "three")
        XCTAssertEqual(swap.subviews.first?.alpha, 1)
        XCTAssertEqual(swapped.last, .three)
        XCTAssertFalse(swapped.contains(.two), "a key replaced mid-transition is never built")
    }

    func testAKeyAskedForDuringTheFadeInIsPickedUpAfterwards() throws {
        let swap = try makeSwap(reduceMotion: false)
        swap.timing.fadeIn = 0.15
        swap.show(.two)
        XCTAssertTrue(LaneBHost.spin(until: { swap.displayed == .two }))
        swap.show(.three)
        XCTAssertTrue(LaneBHost.spin(until: { swap.displayed == .three && !swap.isTransitioning }))
        XCTAssertEqual(swapped, [.two, .three])
    }

    func testAnimatedLayoutSwapCallsDidSwapAfterTheLayoutAnimation() throws {
        let swap = try makeSwap(reduceMotion: false)
        swap.animatesLayout = { from, to in from == .one && to == .two }
        swap.show(.two)
        XCTAssertTrue(LaneBHost.spin(until: { !swap.isTransitioning }))
        XCTAssertEqual(swap.displayed, .two)
        XCTAssertEqual(swapped, [.two])
        XCTAssertEqual(containerAlphaAtSwap, [0])
    }

    func testReduceMotionDuringATransitionCancelsItAndShowsTheKey() throws {
        var reduce = false
        made = []
        let swap = FentonContentSwapView<Tab>(initial: .one, reduceMotion: { reduce }) { tab in
            let view = UIView()
            view.accessibilityIdentifier = "\(tab)"
            return view
        }
        let root = UIViewController()
        window = try LaneBHost.window(showing: root)
        swap.frame = root.view.bounds
        root.view.addSubview(swap)
        swap.show(.two)
        XCTAssertTrue(swap.isTransitioning)
        reduce = true
        swap.show(.three)
        XCTAssertFalse(swap.isTransitioning)
        XCTAssertEqual(swap.displayed, .three)
        XCTAssertEqual(swap.subviews.first?.alpha, 1)
    }
}
#endif
