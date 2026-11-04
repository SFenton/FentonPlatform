import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A structured measurement captured by the opt-in telemetry recorder.
public struct TelemetrySample: Codable, Sendable, Equatable {
    /// Stable measurement name.
    public let name: String
    /// Elapsed wall-clock duration in nanoseconds.
    public let elapsedNanoseconds: UInt64
    /// Whether the operation ran on the main thread.
    public let mainThread: Bool
    /// Small allowlisted dimensions useful for comparing fixtures.
    public let metadata: [String: String]

    /// Creates a structured measurement sample.
    public init(
        name: String,
        elapsedNanoseconds: UInt64,
        mainThread: Bool,
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.elapsedNanoseconds = elapsedNanoseconds
        self.mainThread = mainThread
        self.metadata = metadata
    }
}

/// A benchmark-friendly, serializable snapshot. No data is recorded unless enabled.
public struct TelemetrySnapshot: Codable, Sendable, Equatable {
    /// Time at which the recorder was created.
    public let startedAt: Date
    /// Recorded elapsed-time samples.
    public let samples: [TelemetrySample]
    /// Named benchmark counters.
    public let counters: [String: Int]
    /// Resident memory when the host exposes it.
    public let memoryBytes: UInt64?
    /// Process CPU time when the host exposes it.
    public let cpuTimeNanoseconds: UInt64?
    /// Stable fixture and build dimensions supplied by the harness.
    public let metadata: [String: String]

    /// Creates a serializable snapshot.
    public init(
        startedAt: Date,
        samples: [TelemetrySample],
        counters: [String: Int],
        memoryBytes: UInt64?,
        cpuTimeNanoseconds: UInt64? = nil,
        metadata: [String: String] = [:]
    ) {
        self.startedAt = startedAt
        self.samples = samples
        self.counters = counters
        self.memoryBytes = memoryBytes
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.metadata = metadata
    }

    /// Encodes the snapshot as stable, human-readable JSON.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }
}

/// Opt-in elapsed-time and main-thread recorder for populated harness runs.
public final class FentonTelemetry: @unchecked Sendable {
    /// Whether samples and counters are collected.
    public let isEnabled: Bool
    private let lock = NSLock()
    private let startedAt = Date()
    private var metadata: [String: String]
    private let maxSamples: Int
    private var samples: [TelemetrySample] = []
    private var counters: [String: Int] = [:]

    /// Creates an opt-in recorder. Disabled recorders execute operations unchanged.
    public init(
        enabled: Bool = false,
        metadata: [String: String] = [:],
        maxSamples: Int = 512
    ) {
        self.isEnabled = enabled
        self.metadata = metadata
        self.maxSamples = max(0, maxSamples)
    }

    /// Increments a named benchmark counter.
    public func increment(_ name: String, by amount: Int = 1) {
        guard isEnabled else { return }
        lock.lock()
        counters[name, default: 0] += amount
        lock.unlock()
    }

    /// Adds or replaces stable dimensions before a snapshot is exported.
    public func updateMetadata(_ values: [String: String]) {
        guard isEnabled else { return }
        lock.lock()
        metadata.merge(values) { _, new in new }
        lock.unlock()
    }

    /// Measures elapsed wall-clock time and records whether the call ran on the main thread.
    @discardableResult
    public func measure<T>(
        _ name: String,
        metadata: [String: String] = [:],
        _ operation: () throws -> T
    ) rethrows -> T {
        guard isEnabled else { return try operation() }
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            record(
                TelemetrySample(
                    name: name,
                    elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - start,
                    mainThread: Thread.isMainThread,
                    metadata: metadata
                )
            )
        }
        return try operation()
    }

    /// Adds an already-structured sample.
    public func record(_ sample: TelemetrySample) {
        guard isEnabled else { return }
        lock.lock()
        guard maxSamples > 0 else {
            lock.unlock()
            return
        }
        if samples.count == maxSamples {
            samples.removeFirst()
        }
        samples.append(sample)
        lock.unlock()
    }

    /// Returns a thread-safe snapshot with optional resident-memory information.
    public func snapshot() -> TelemetrySnapshot {
        lock.lock()
        let snapshot = TelemetrySnapshot(
            startedAt: startedAt,
            samples: samples,
            counters: counters,
            memoryBytes: currentMemoryBytes(),
            cpuTimeNanoseconds: currentCPUTimeNanoseconds(),
            metadata: metadata
        )
        lock.unlock()
        return snapshot
    }

    private func currentMemoryBytes() -> UInt64? {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : nil
        #else
        return nil
        #endif
    }

    private func currentCPUTimeNanoseconds() -> UInt64? {
        #if canImport(Darwin)
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let user = UInt64(usage.ru_utime.tv_sec) * 1_000_000_000
            + UInt64(usage.ru_utime.tv_usec) * 1_000
        let system = UInt64(usage.ru_stime.tv_sec) * 1_000_000_000
            + UInt64(usage.ru_stime.tv_usec) * 1_000
        return user + system
        #else
        return nil
        #endif
    }
}
