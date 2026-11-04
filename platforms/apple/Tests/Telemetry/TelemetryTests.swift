import XCTest
@testable import FentonAppleTelemetry

final class TelemetryTests: XCTestCase {
    func testDisabledRecorderDoesNotEmitSamples() {
        let telemetry = FentonTelemetry()
        telemetry.measure("ignored") {}
        XCTAssertTrue(telemetry.snapshot().samples.isEmpty)
    }

    func testEnabledRecorderProducesStructuredSampleAndCounter() throws {
        let telemetry = FentonTelemetry(enabled: true)
        telemetry.increment("rows", by: 25)
        telemetry.measure("first-content", metadata: ["fixture": "populated"]) {
            _ = (0..<1_000).reduce(0, +)
        }
        let snapshot = telemetry.snapshot()
        XCTAssertEqual(snapshot.counters["rows"], 25)
        XCTAssertEqual(snapshot.samples.first?.name, "first-content")
        XCTAssertEqual(snapshot.metadata, [:])
        XCTAssertFalse(try snapshot.jsonData().isEmpty)
    }

    func testSampleRetentionIsBounded() {
        let telemetry = FentonTelemetry(enabled: true, maxSamples: 2)
        telemetry.record(TelemetrySample(name: "one", elapsedNanoseconds: 1, mainThread: false))
        telemetry.record(TelemetrySample(name: "two", elapsedNanoseconds: 2, mainThread: false))
        telemetry.record(TelemetrySample(name: "three", elapsedNanoseconds: 3, mainThread: false))

        XCTAssertEqual(telemetry.snapshot().samples.map(\.name), ["two", "three"])
    }
}
