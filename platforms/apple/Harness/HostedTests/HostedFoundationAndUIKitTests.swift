import XCTest
import UIKit
import FentonAppleCore
import FentonAppleTelemetry
import FentonUIKit

@MainActor
final class HostedFoundationAndUIKitTests: XCTestCase {
    func testCorePolicyAndTelemetryRunInTheSimulatorHost() throws {
        let policy = FentonSplitPolicy()
        XCTAssertTrue(policy.allowsSplit(size: CGSize(width: 868, height: 400), isRegularWidth: true))

        let telemetry = FentonTelemetry(enabled: true)
        telemetry.measure("simulator-hosted") {
            _ = policy.allowsSplit(size: CGSize(width: 868, height: 400), isRegularWidth: true)
        }
        XCTAssertEqual(telemetry.snapshot().samples.first?.name, "simulator-hosted")
    }

    func testUIKitPageAndNativeSheetMechanicsRunInTheSimulatorHost() {
        let page = FentonPageContainerViewController()
        let content = UIViewController()
        let scroll = UIScrollView()
        page.loadViewIfNeeded()
        page.embed(content, mainScrollView: scroll)
        XCTAssertTrue(content.parent === page)
        XCTAssertEqual(scroll.contentInsetAdjustmentBehavior, .never)

        let sheet = UIViewController()
        FentonSheetPresenter.configure(sheet)
        XCTAssertEqual(sheet.modalPresentationStyle, .pageSheet)
    }
}
