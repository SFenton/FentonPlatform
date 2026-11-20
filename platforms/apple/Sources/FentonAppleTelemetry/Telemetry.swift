import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A structured measurement captured by the opt-in telemetry recorder.
public struct TelemetrySample: Codable, Sendable, Equatable {
    public let name: String
    public let elapsedNanoseconds: UInt64
    /// Preserved compatibility indicator for existing consumers.
    public let mainThread: Bool
    public let threadCPUNanoseconds: UInt64?
    public let mainThreadCPUNanoseconds: UInt64?
    public let runLoopActiveNanoseconds: UInt64?
    public let runLoopIdleNanoseconds: UInt64?
    public let metadata: [String: String]

    private enum CodingKeys: String, CodingKey {
        case name, elapsedNanoseconds, mainThread, threadCPUNanoseconds
        case mainThreadCPUNanoseconds, runLoopActiveNanoseconds, runLoopIdleNanoseconds, metadata
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        elapsedNanoseconds = try values.decode(UInt64.self, forKey: .elapsedNanoseconds)
        mainThread = try values.decodeIfPresent(Bool.self, forKey: .mainThread) ?? false
        threadCPUNanoseconds = try values.decodeIfPresent(UInt64.self, forKey: .threadCPUNanoseconds)
        mainThreadCPUNanoseconds = try values.decodeIfPresent(UInt64.self, forKey: .mainThreadCPUNanoseconds)
        runLoopActiveNanoseconds = try values.decodeIfPresent(UInt64.self, forKey: .runLoopActiveNanoseconds)
        runLoopIdleNanoseconds = try values.decodeIfPresent(UInt64.self, forKey: .runLoopIdleNanoseconds)
        metadata = try values.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    public init(
        name: String,
        elapsedNanoseconds: UInt64,
        mainThread: Bool = false,
        threadCPUNanoseconds: UInt64? = nil,
        mainThreadCPUNanoseconds: UInt64? = nil,
        runLoopActiveNanoseconds: UInt64? = nil,
        runLoopIdleNanoseconds: UInt64? = nil,
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.elapsedNanoseconds = elapsedNanoseconds
        self.mainThread = mainThread
        self.threadCPUNanoseconds = threadCPUNanoseconds
        self.mainThreadCPUNanoseconds = mainThreadCPUNanoseconds
        self.runLoopActiveNanoseconds = runLoopActiveNanoseconds
        self.runLoopIdleNanoseconds = runLoopIdleNanoseconds
        self.metadata = metadata
    }
}

public struct TelemetrySnapshot: Codable, Sendable, Equatable {
    public let startedAt: Date
    public let samples: [TelemetrySample]
    public let counters: [String: Int]
    public let memoryBytes: UInt64?
    public let cpuTimeNanoseconds: UInt64?
    public let metadata: [String: String]

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

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }
}

/// Opt-in elapsed, CPU, and run-loop recorder for populated harness runs.
public final class FentonTelemetry: @unchecked Sendable {
    public let isEnabled: Bool
    private let lock = NSLock()
    private let startedAt = Date()
    private let recorderID = UUID()
    private var metadata: [String: String]
    private let maxSamples: Int
    private let runLoopMonitor: MainRunLoopActivityMonitor?
    private var samples: [TelemetrySample] = []
    private var counters: [String: Int] = [:]
    private var activeIntervals: Set<UUID> = []
    private let maxActiveIntervals: Int

    public init(enabled: Bool = false, metadata: [String: String] = [:], maxSamples: Int = 512) {
        self.isEnabled = enabled
        self.metadata = metadata
        self.maxSamples = max(0, maxSamples)
        self.maxActiveIntervals = max(1, maxSamples)
        self.runLoopMonitor = enabled && Thread.isMainThread ? MainRunLoopActivityMonitor() : nil
    }

    deinit {
        runLoopMonitor?.invalidate()
    }

    public func increment(_ name: String, by amount: Int = 1) {
        guard isEnabled else { return }
        lock.lock(); counters[name, default: 0] += amount; lock.unlock()
    }

    public func updateMetadata(_ values: [String: String]) {
        guard isEnabled else { return }
        lock.lock(); metadata.merge(values) { _, new in new }; lock.unlock()
    }

    @discardableResult
    public func measure<T>(_ name: String, metadata: [String: String] = [:], _ operation: () throws -> T) rethrows -> T {
        guard isEnabled else { return try operation() }
        let start = DispatchTime.now().uptimeNanoseconds
        let cpuStart = currentThreadCPUNanoseconds()
        let threadID = currentThreadID()
        let activityStart = runLoopMonitor?.snapshot()
        defer {
            let cpu = threadID == currentThreadID() ? difference(currentThreadCPUNanoseconds(), cpuStart) : nil
            let isMain = Thread.isMainThread
            let activity = runLoopMonitor?.difference(from: activityStart)
            record(TelemetrySample(
                name: name,
                elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - start,
                mainThread: isMain,
                threadCPUNanoseconds: cpu,
                mainThreadCPUNanoseconds: isMain ? cpu : nil,
                runLoopActiveNanoseconds: activity?.active,
                runLoopIdleNanoseconds: activity?.idle,
                metadata: metadata
            ))
        }
        return try operation()
    }

    public func beginInterval() -> TelemetryInterval? {
        guard isEnabled else { return nil }
        let token = UUID()
        lock.lock()
        guard activeIntervals.count < maxActiveIntervals else {
            counters["intervals.dropped.capacity", default: 0] += 1
            lock.unlock()
            return nil
        }
        activeIntervals.insert(token)
        lock.unlock()
        return TelemetryInterval(
            token: token,
            recorderID: recorderID,
            startedAt: DispatchTime.now().uptimeNanoseconds,
            threadID: currentThreadID(),
            threadCPUStartedAt: currentThreadCPUNanoseconds(),
            activityStartedAt: runLoopMonitor?.snapshot()
        )
    }

    @discardableResult
    public func endInterval(_ interval: TelemetryInterval, named name: String, metadata: [String: String] = [:]) -> Bool {
        guard isEnabled, interval.recorderID == recorderID else { return false }
        lock.lock()
        guard activeIntervals.remove(interval.token) != nil else { lock.unlock(); return false }
        lock.unlock()
        guard interval.threadID == currentThreadID() else { return false }
        let isMain = Thread.isMainThread
        let cpu = difference(currentThreadCPUNanoseconds(), interval.threadCPUStartedAt)
        let activity = runLoopMonitor?.difference(from: interval.activityStartedAt)
        record(TelemetrySample(
            name: name,
            elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - interval.startedAt,
            mainThread: isMain,
            threadCPUNanoseconds: cpu,
            mainThreadCPUNanoseconds: isMain ? cpu : nil,
            runLoopActiveNanoseconds: activity?.active,
            runLoopIdleNanoseconds: activity?.idle,
            metadata: metadata
        ))
        return true
    }

    @discardableResult
    public func cancelInterval(_ interval: TelemetryInterval) -> Bool {
        guard interval.recorderID == recorderID else { return false }
        lock.lock(); defer { lock.unlock() }
        return activeIntervals.remove(interval.token) != nil
    }

    public func record(_ sample: TelemetrySample) {
        guard isEnabled else { return }
        lock.lock(); defer { lock.unlock() }
        guard maxSamples > 0 else { return }
        if samples.count == maxSamples { samples.removeFirst() }
        samples.append(sample)
    }

    public func snapshot() -> TelemetrySnapshot {
        lock.lock()
        let snapshot = TelemetrySnapshot(
            startedAt: startedAt,
            samples: samples,
            counters: counters,
            memoryBytes: currentMemoryBytes(),
            cpuTimeNanoseconds: currentProcessCPUTimeNanoseconds(),
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

    private func currentProcessCPUTimeNanoseconds() -> UInt64? {
        #if canImport(Darwin)
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return UInt64(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000_000_000
            + UInt64(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) * 1_000
        #else
        return nil
        #endif
    }

    private func currentThreadCPUNanoseconds() -> UInt64? {
        #if canImport(Darwin)
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.user_time.seconds + info.system_time.seconds) * 1_000_000_000
            + UInt64(info.user_time.microseconds + info.system_time.microseconds) * 1_000
        #else
        return nil
        #endif
    }

    private func currentThreadID() -> UInt64 {
        #if canImport(Darwin)
        return UInt64(pthread_mach_thread_np(pthread_self()))
        #else
        return 0
        #endif
    }

    private func difference(_ end: UInt64?, _ start: UInt64?) -> UInt64? {
        guard let end, let start else { return nil }
        return end >= start ? end - start : 0
    }
}

public struct TelemetryInterval: Sendable {
    fileprivate let token: UUID
    fileprivate let recorderID: UUID
    fileprivate let startedAt: UInt64
    fileprivate let threadID: UInt64
    fileprivate let threadCPUStartedAt: UInt64?
    fileprivate let activityStartedAt: MainRunLoopActivityMonitor.Snapshot?
}

fileprivate final class MainRunLoopActivityMonitor: @unchecked Sendable {
    fileprivate struct Snapshot { let active: UInt64; let idle: UInt64 }
    private let lock = NSLock()
    private var active: UInt64 = 0
    private var idle: UInt64 = 0
    private var lastTransition = DispatchTime.now().uptimeNanoseconds
    private var isIdle = false
    private var observer: CFRunLoopObserver?

    init() {
        #if canImport(Darwin)
        if Thread.isMainThread { install() }
        #endif
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        #if canImport(Darwin)
        guard let observer else { return }
        self.observer = nil
        // Core Foundation removal is thread-safe and must not wait on main.
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        #endif
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        update(to: DispatchTime.now().uptimeNanoseconds)
        return Snapshot(active: active, idle: idle)
    }

    func difference(from start: Snapshot?) -> (active: UInt64, idle: UInt64)? {
        guard let start else { return nil }
        let end = snapshot()
        return (max(0, end.active - start.active), max(0, end.idle - start.idle))
    }

    private func install() {
        let activities = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.afterWaiting.rawValue
        observer = CFRunLoopObserverCreateWithHandler(nil, CFOptionFlags(activities), true, 0) { [weak self] _, activity in
            self?.transition(to: activity == .beforeWaiting)
        }
        if let observer { CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes) }
    }

    private func transition(to idle: Bool) {
        lock.lock(); defer { lock.unlock() }
        update(to: DispatchTime.now().uptimeNanoseconds)
        isIdle = idle
    }

    private func update(to now: UInt64) {
        let delta = now >= lastTransition ? now - lastTransition : 0
        if isIdle { idle += delta } else { active += delta }
        lastTransition = now
    }
}
