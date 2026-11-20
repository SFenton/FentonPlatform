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

    func testLegacySampleJSONDecodesWithoutNewFields() throws {
        let data = Data(#"{"name":"legacy","elapsedNanoseconds":4,"mainThread":true,"metadata":{}}"#.utf8)
        let sample = try JSONDecoder().decode(TelemetrySample.self, from: data)
        XCTAssertTrue(sample.mainThread)
        XCTAssertNil(sample.mainThreadCPUNanoseconds)
    }

    func testSampleRetentionIsBounded() {
        let telemetry = FentonTelemetry(enabled: true, maxSamples: 2)
        telemetry.record(TelemetrySample(name: "one", elapsedNanoseconds: 1))
        telemetry.record(TelemetrySample(name: "two", elapsedNanoseconds: 2))
        telemetry.record(TelemetrySample(name: "three", elapsedNanoseconds: 3))

        XCTAssertEqual(telemetry.snapshot().samples.map(\.name), ["two", "three"])
    }

    func testMeasureCapturesRealCPUTimeWhenAvailable() {
        let telemetry = FentonTelemetry(enabled: true)
        telemetry.measure("cpu-work") {
            var value = 0
            for number in 0..<2_000_000 {
                value = (value &* 31) ^ number
            }
            XCTAssertNotEqual(value, Int.min)
        }

        let sample = telemetry.snapshot().samples[0]
        #if canImport(Darwin)
        XCTAssertGreaterThan(sample.threadCPUNanoseconds ?? 0, 0)
        XCTAssertGreaterThan(sample.mainThreadCPUNanoseconds ?? 0, 0)
        #else
        XCTAssertNil(sample.threadCPUNanoseconds)
        #endif
    }

    func testAsyncIntervalCancellationRejectsStaleCompletion() {
        let telemetry = FentonTelemetry(enabled: true)
        let interval = try! XCTUnwrap(telemetry.beginInterval())
        XCTAssertTrue(telemetry.cancelInterval(interval))
        XCTAssertFalse(telemetry.endInterval(interval, named: "cancelled"))
        XCTAssertTrue(telemetry.snapshot().samples.isEmpty)
    }

    func testAbandonedIntervalsHaveBoundedAdmission() throws {
        let telemetry = FentonTelemetry(enabled: true, maxSamples: 2)
        XCTAssertNotNil(telemetry.beginInterval())
        XCTAssertNotNil(telemetry.beginInterval())
        XCTAssertNil(telemetry.beginInterval())
        XCTAssertEqual(telemetry.snapshot().counters["intervals.dropped.capacity"], 1)
    }

    func testIntervalCannotBeEndedByAnotherRecorderOrTwice() {
        let first = FentonTelemetry(enabled: true)
        let second = FentonTelemetry(enabled: true)
        let interval = try! XCTUnwrap(first.beginInterval())
        XCTAssertFalse(second.endInterval(interval, named: "wrong-recorder"))
        XCTAssertTrue(first.endInterval(interval, named: "once"))
        XCTAssertFalse(first.endInterval(interval, named: "twice"))
    }

    func testOffMainRecorderTeardownDoesNotWaitForMainThread() {
        XCTAssertTrue(Thread.isMainThread)
        let retained = Unmanaged.passRetained(FentonTelemetry(enabled: true))
        let released = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            retained.release()
            released.signal()
        }
        XCTAssertEqual(released.wait(timeout: .now() + 1), .success)
    }

    func testBackgroundRecorderDoesNotFabricateMainRunLoopActivity() {
        let finished = expectation(description: "background sample")
        DispatchQueue.global(qos: .userInitiated).async {
            let telemetry = FentonTelemetry(enabled: true)
            telemetry.measure("background") {}
            let sample = telemetry.snapshot().samples[0]
            XCTAssertFalse(sample.mainThread)
            XCTAssertNil(sample.mainThreadCPUNanoseconds)
            XCTAssertNil(sample.runLoopActiveNanoseconds)
            XCTAssertNil(sample.runLoopIdleNanoseconds)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
    }

    func testRecorderTeardownReleasesItsRunLoopMonitor() {
        weak var released: FentonTelemetry?
        do {
            let telemetry = FentonTelemetry(enabled: true)
            released = telemetry
        }
        XCTAssertNil(released)
    }

    func testIntervalRetainsActiveAndIdleFieldsWithoutUnboundedState() {
        let telemetry = FentonTelemetry(enabled: true, maxSamples: 1)
        for _ in 0..<4 {
            if let interval = telemetry.beginInterval() {
                _ = telemetry.endInterval(interval, named: "bounded")
            }
        }
        XCTAssertEqual(telemetry.snapshot().samples.count, 1)
    }
}
