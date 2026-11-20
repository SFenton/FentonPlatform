#if os(iOS)
import ObjectiveC
import XCTest
import UIKit

/// Counts `layoutSubviews` passes of one view instance by giving it a private subclass (the way KVO does), so a test can count the
/// layout passes of a controller's own root view without that view's class being open.
final class PageLayoutCounter: @unchecked Sendable {
    private(set) var count = 0

    /// Installs a counting subclass on `view`'s class for this instance only.
    @MainActor
    static func install(on view: UIView) -> PageLayoutCounter {
        let counter = PageLayoutCounter()
        let base: AnyClass = type(of: view)
        let name = "PageLayoutCounter_\(NSStringFromClass(base))_\(UInt(bitPattern: ObjectIdentifier(view).hashValue))"
        let selector = #selector(UIView.layoutSubviews)
        guard let subclass = objc_allocateClassPair(base, name, 0),
              let original = class_getMethodImplementation(base, selector) else { return counter }
        typealias Original = @convention(c) (AnyObject, Selector) -> Void
        let block: @convention(block) (AnyObject) -> Void = { object in
            counter.count += 1
            unsafeBitCast(original, to: Original.self)(object, selector)
        }
        class_addMethod(subclass, selector, imp_implementationWithBlock(block), "v@:")
        objc_registerClassPair(subclass)
        object_setClass(view, subclass)
        return counter
    }
}

extension XCTestCase {
    /// Lets the main run loop run for `turns` stretches of `seconds` each, long enough for display refreshes, observers and queued main-queue
    /// work. (`RunLoop.run(until:)` returns at once when the loop has no source, so an inverted expectation holds it open.)
    @MainActor
    func pageTurnRunLoop(_ turns: Int = 2, seconds: TimeInterval = 0.1) {
        for _ in 0..<turns {
            let hold = XCTestExpectation(description: "run loop turn")
            hold.isInverted = true
            _ = XCTWaiter.wait(for: [hold], timeout: seconds)
        }
    }
}

/// A window of a fixed size holding `controller`, laid out once.
@MainActor
func pageTestWindow(_ controller: UIViewController, size: CGSize = CGSize(width: 390, height: 844)) -> UIWindow {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
    window.frame = CGRect(origin: .zero, size: size)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    return window
}
#endif
