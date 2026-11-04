import XCTest
@testable import FentonAppleCore

final class SplitPolicyTests: XCTestCase {
    func testPrimaryLengthHonorsMinimumsAndPreferredFraction() {
        let policy = SplitPolicy(minimumPrimary: 240, minimumSecondary: 320, preferredPrimaryFraction: 0.34)
        XCTAssertEqual(policy.primaryLength(for: 1000), 340, accuracy: 0.01)
        XCTAssertEqual(policy.primaryLength(for: 500), 240, accuracy: 0.01)
        XCTAssertEqual(policy.primaryLength(for: 200), 200, accuracy: 0.01)
        XCTAssertEqual(policy.primaryLength(for: 0), 0, accuracy: 0.01)
        XCTAssertEqual(policy.primaryLength(for: -20), 0, accuracy: 0.01)
        XCTAssertEqual(policy.primaryLength(for: 100), 100, accuracy: 0.01)
    }
}
