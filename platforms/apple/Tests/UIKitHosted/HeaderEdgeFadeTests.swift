#if os(iOS)
import FentonAppleCore
import FentonUIKit
import UIKit
import XCTest

@MainActor
final class HeaderEdgeFadeTests: XCTestCase {
    private func makeContent() -> (UIWindow, UIView, UIScrollView) {
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let content = UIView(frame: controller.view.bounds)
        controller.view.addSubview(content)
        let scroll = UIScrollView(frame: content.bounds)
        scroll.contentSize = CGSize(width: 390, height: 4000)
        content.addSubview(scroll)
        window.layoutIfNeeded()
        return (window, content, scroll)
    }

    // MARK: - The mask (before iOS 26, or with the era flag off)

    func testTheMaskIsClearAtRestAndFadesAsTheContentScrolls() throws {
        let (window, content, scroll) = makeContent()
        let fade = FentonHeaderEdgeFade(masking: content, rampHeight: 40, usesSystemEffect: false)
        fade.follow(scroll)
        fade.layoutChanged()
        XCTAssertTrue(content.layer.mask is CAGradientLayer)
        var stops = try XCTUnwrap(fade.maskStops)
        XCTAssertEqual(stops.alphas[2], 1, accuracy: 0.01, "at rest nothing is dimmed")
        scroll.contentOffset.y = 20 - scroll.adjustedContentInset.top
        stops = try XCTUnwrap(fade.maskStops)
        XCTAssertEqual(stops.alphas[2], 0.5, accuracy: 0.01)
        scroll.contentOffset.y = 100
        stops = try XCTUnwrap(fade.maskStops)
        XCTAssertEqual(stops.alphas[2], 0, accuracy: 0.01, "transparent once scrolled a ramp's length")
        XCTAssertEqual(stops.alphas[0], 0, "always clear over the header")
        withExtendedLifetime(window) {}
    }

    func testTheMaskIsWrittenOnlyWhenAWholePointInsideTheRampChanges() {
        let (window, content, scroll) = makeContent()
        let fade = FentonHeaderEdgeFade(masking: content, rampHeight: 40, usesSystemEffect: false)
        fade.follow(scroll)
        fade.layoutChanged()
        // The scroll view sits under the status bar, so its resting offset is minus the system's inset.
        let rest = -scroll.adjustedContentInset.top
        scroll.contentOffset.y = rest
        let base = fade.maskWriteCount
        scroll.contentOffset.y = rest + 10.2
        XCTAssertEqual(fade.maskWriteCount, base + 1)
        scroll.contentOffset.y = rest + 10.1
        scroll.contentOffset.y = rest + 9.9
        XCTAssertEqual(fade.maskWriteCount, base + 1, "sub-point movement that rounds to the same whole point writes nothing")
        scroll.contentOffset.y = rest + 400
        let atRamp = fade.maskWriteCount
        XCTAssertGreaterThan(atRamp, base + 1)
        for y in stride(from: rest + 401.0, through: rest + 900.0, by: 7.3) { scroll.contentOffset.y = y }
        XCTAssertEqual(fade.maskWriteCount, atRamp, "clamped to the ramp: scrolling on writes nothing")
        fade.layoutChanged()
        fade.layoutChanged()
        XCTAssertEqual(fade.maskWriteCount, atRamp, "an identical layout writes nothing")
        withExtendedLifetime(window) {}
    }

    func testReduceTransparencyAndIncreaseContrastMakeAHardEdge() throws {
        let (window, content, scroll) = makeContent()
        let fade = FentonHeaderEdgeFade(masking: content, rampHeight: 40, usesSystemEffect: false)
        fade.follow(scroll)
        fade.layoutChanged()
        let soft = try XCTUnwrap(fade.maskStops)
        XCTAssertGreaterThan(soft.locations[3], soft.locations[2], "a ramp")
        fade.reduceTransparency = true
        let hard = try XCTUnwrap(fade.maskStops)
        XCTAssertEqual(hard.locations[3], hard.locations[2], accuracy: 0.0001, "no ramp")
        fade.reduceTransparency = false
        fade.increaseContrast = true
        XCTAssertEqual(try XCTUnwrap(fade.maskStops).locations[3], hard.locations[2], accuracy: 0.0001)
        withExtendedLifetime(window) {}
    }

    func testTheCapKeepsALargeTitleOutOfTheClearBand() throws {
        let (window, content, scroll) = makeContent()
        let fade = FentonHeaderEdgeFade(masking: content, rampHeight: 40, usesSystemEffect: false)
        fade.follow(scroll)
        fade.cap = 100
        let stops = try XCTUnwrap(fade.maskStops)
        XCTAssertLessThanOrEqual(stops.locations[1], 100.0 / 844.0 + 0.0001)
        withExtendedLifetime(window) {}
    }

    // MARK: - The system effect (iOS 26 and later)

    func testTheSystemEffectInstallsNoMaskAndObservesNothing() {
        let (window, content, scroll) = makeContent()
        let fade = FentonHeaderEdgeFade(masking: content, rampHeight: 40, usesSystemEffect: true)
        fade.follow(scroll)
        fade.layoutChanged()
        scroll.contentOffset.y = 30
        XCTAssertNil(content.layer.mask)
        XCTAssertEqual(fade.maskWriteCount, 0)
        XCTAssertNil(fade.maskStops)
        withExtendedLifetime(window) {}
    }

    func testTheEraFlagFollowsTheRunningSystemByDefault() throws {
        let (window, content, scroll) = makeContent()
        let fade = FentonHeaderEdgeFade(masking: content)
        XCTAssertEqual(fade.usesSystemEffect, FentonHeaderEdgeFade.systemDrawsEdge)
        if #available(iOS 26.0, *) {
            XCTAssertTrue(FentonHeaderEdgeFade.systemDrawsEdge)
            FentonHeaderEdgeFade.applySystemEffect(to: scroll)
            XCTAssertFalse(scroll.topEdgeEffect.isHidden)
            XCTAssertEqual(scroll.topEdgeEffect.style, .soft)
            FentonHeaderEdgeFade.applySystemEffect(to: scroll, usesSystemEffect: false)
            XCTAssertTrue(scroll.topEdgeEffect.isHidden, "the mask draws the edge instead")
        } else {
            XCTAssertNotNil(content.layer.mask)
        }
        withExtendedLifetime(window) {}
    }
}
#endif
