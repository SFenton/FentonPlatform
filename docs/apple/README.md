# Apple foundation lane

The Apple products use Swift 6 and target iOS 17. The root `Package.swift` is
the remote SwiftPM entry point; source remains under `platforms/apple`.

## Products

- **FentonAppleCore** — `ObservationBinding`, `ObservationBag`, and pure split
  geometry/policy.
- **FentonAppleTelemetry** — opt-in elapsed, calling-thread CPU, main-thread
  CPU, bounded run-loop active/idle samples, counters, resident-memory
  snapshots where the platform exposes them, and JSON export.
- **FentonUIKit** — page containment, explicit scroll/accessory registration,
  the reusable ``FentonContentContainmentView`` composition helper, embeddable
  controller hosting, native split containment, and adaptive sheets.
- **FentonUIKitTestHostSupport** — debug fixture hosting in the app process.
- **FentonXCUITestSupport** — runner-side waits and visibility assertions.

The two test-support products are deliberately separate. No listener, reset
channel, benchmark controller, or test dependency is part of the shipping
UIKit products; the runtime product graph is `FentonUIKit` → Core/Telemetry
only. Test bundles may link the support products, but application targets must
not.

## Harness

`platforms/apple/Harness/project.yml` describes a neutral Xcode harness with
ocean and sunset themes. It uses a populated 250-row page and a native sheet,
with accessibility identifiers and a launch-time `--benchmark` opt-in. The
benchmark flag emits samples through the in-process telemetry API and writes
`fenton-harness-benchmark.json` to the app Documents directory. The artifact
reports a populated display-link observation after `viewDidAppear`, an
idle main-turn observation, an animated populated-list scroll, calling-thread
and main-thread CPU time, run-loop active/idle deltas, process CPU time,
resident memory, fixture/build metadata, and window/visible-row metadata when
available. It carries a run identity and rejects stale completion generations;
reload is named separately and is not treated as first content. It does not
assert a budget or claim a performance win. Choose matched simulator/device
runs when comparing results. The legacy `first-presented-content` sample name
means the first observed populated display-link tick after `viewDidAppear`,
not initial app launch, GPU completion or physical-display timing. That
observation completes before the benchmark starts scrolling.

Run-loop observation is available only when an enabled recorder is constructed
on the main thread. A background-created recorder still measures calling-thread
CPU, but reports unavailable main-run-loop values as `nil`, not inferred activity.
Observer teardown uses Core Foundation's thread-safe run-loop API, without a
synchronous main-thread dispatch or cross-thread `NSRunLoop` mutation. See
[Apple's thread-safety distinction](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html).
Telemetry sample retention is bounded by the recorder's `maxSamples` capacity
(512 by default). Active intervals have bounded admission; abandoned tokens
cannot grow recorder state without limit, and capacity drops have a counter.
Callers must use fixed counter and metadata vocabularies rather than domain IDs.

For matched harness-only comparisons, add `--baseline-containment` to use
direct legacy child containment instead of `FentonPageContainerViewController`.
Both arms use the same populated rows, telemetry, scroll driver, theme, and
normal animation configuration; the artifact identifies the arm as
`baseline-direct-containment` or `shared-containment`. This flag is a benchmark
arm selector, not production behavior or a performance claim.

Generate the harness on a Mac with
`/opt/homebrew/bin/xcodegen generate --spec platforms/apple/Harness/project.yml`.
The generated project has an explicit `FentonAppleHarness` scheme with a
simulator-hosted unit-test target covering Core, Telemetry, and the canonical
`Tests/UIKitHosted/UIKitHostTests.swift` regressions, plus the runner-side
UI-test target. Those hosted UIKit tests are distinct from the empty-on-Mac
conditional SwiftPM UIKit bundle. The app uses generated launch-screen and scene
manifest settings for its `UIWindowSceneDelegate`; it does not rely on legacy
compatibility frames. The generated scene manifest enables scene handling;
`AppDelegate` returns a native `UISceneConfiguration` with the explicit
`SceneDelegate` class for connecting sessions. The fixture root is
wrapped in a native navigation controller so the bar and sheet action are
present in UI journeys. SwiftPM host tests establish pure logic and telemetry
behavior only; UIKit behavior requires the hosted simulator target.

## Adoption boundary

Consumers provide their own route types, services, session, colors, typography
decisions, and domain models. These APIs intentionally do not export a HASS
context or either consumer's design tokens.

Existing page bases can add `FentonContentContainmentView` as a subview and
install their own content view without replacing their controller hierarchy.
`FentonPageContainerViewController` uses the same helper for consumers that want
a clean page host.

Typical composition keeps the app-owned controller and chrome intact:

```swift
let containment = FentonContentContainmentView()
addChild(featureController)
containment.installContentView(featureController.view)
view.addSubview(containment)
featureController.didMove(toParent: self)
containment.registerMainScrollView(featureScrollView)
```

The app remains responsible for the constraints that place the containment
view among its rails or headers; the helper owns only its inner safe-area
content and registered accessory/scroll clearance.

Set `contentInsetsOverride` when an existing page base already computed the
content rectangle (for example, folded-rail geometry). `nil` uses the helper's
system safe area; `.zero` and asymmetric values explicitly place content inside
the helper bounds without adding another safe-area padding pass.

Scroll registration is explicit: the helper snapshots the scroll view's
`contentInsetAdjustmentBehavior`, `contentInset`, and `scrollIndicatorInsets`,
then temporarily takes inset ownership (`.never`) while registered. Accessory
clearance is always computed from that snapshot, never from the previous
mutated value. Re-registering another scroller restores the first one;
unregistering or removing the accessory restores the original values.

Observation closures should use weak ownership. `ObservationBag.observe(owner:apply:)`
provides a weak-owner form for controller/view lifetimes; the existing closure
overload remains available for consumer code that already uses `[weak self]`.
The legacy mainThread sample field and initializer remain source-compatible; CPU and run-loop deltas are the measurement fields for benchmark interpretation. Asynchronous intervals are bound to their creating recorder and thread, reject repeated or cross-recorder completion, and can be cancelled during lifecycle teardown.
The first-content clock is the CADisplayLink callback after viewDidAppear; it is not initial app launch, physical-display presentation, or GPU-completion timing.
