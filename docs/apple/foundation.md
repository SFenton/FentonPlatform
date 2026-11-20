# UIKit foundation

What the Apple foundation is, where its pieces live, what an app writes on top of it, and what stays out. Source: `platforms/apple`.
The harness fixture under `Harness/App/Foundation` is the working example of everything below.

## What it is

A set of value types, closures and `open` classes for an iPhone, Duo and iPad app that hardcodes its own pages. The foundation owns
the window facts (fold, hinge, vertical bar, Reduce Motion), the geometric split rule, the page base, columns, stack navigation
and the sheet, flyout and scene plumbing. The app owns pages, routes, tokens, copy and state. There are no registries, no
data-driven layout and no route storage: the app passes pages and tags, the foundation moves them.

## Requirements

| Need | Value |
|---|---|
| Language | Swift 6 language mode |
| Deployment target | iOS 17 |
| SDK to build | iOS 27.1 or later (Xcode 27.1+). `UIHingeInteraction`, `reservedRegions(kind:)` and `verticalBarEdge` sit behind plain `#available(iOS 27.1, *)`; there is no compile flag and no consumer setting. An older system reports no hinge and no vertical bar, as a phone without one does. |
| macOS | Not a target. `.macOS` in `Package.swift` exists only so `swift test` runs the pure logic on the Mac host. |

## Module map

| Product | Holds | Imports UIKit |
|---|---|---|
| `FentonAppleCore` | `FentonSplitPolicy`, `FentonSplitGeometry`, `FentonWindowFold`, `FentonHingeState`, `FentonHingeAvoidance`, `FentonSheetPolicy`, `FentonSheetHeightPolicy`, `FentonHingePresence`, `FentonOrientationPolicy`, `FentonSupportedOrientations`, `FentonScrollEdgeFade`, `FentonAccessibilityFocusChoice`, `FentonMotion`, `FentonWindowEnvironment`, `FentonObservation`, `FentonObservationBag` | no |
| `FentonAppleTelemetry` | `FentonTelemetry` (opt-in timings and counters) | no |
| `FentonUIKit` / Environment | `FentonWindowSignals`, `FentonWindowSensors`, `FentonReflow`, `FentonAnimations`, `FentonHingeAvoidingView`, `FentonHingeClearingView` | yes |
| `FentonUIKit` / Root | `FentonWindowSceneDelegate`, `FentonRootViewController`, `FentonOrientationSupport`, `FentonSceneEvent`, `FentonSceneUpgrade` | yes |
| `FentonUIKit` / Page | `FentonPageViewController`, `FentonPageHost`, `FentonPageConfiguration`, `FentonBarItems`, `FentonTitleStyle`, `FentonFixedBarTitle`, `FentonHeaderEdgeFade`, `FentonScrollFit`, `FentonScrollLocator`, `FentonPinnedBar` | yes |
| `FentonUIKit` / Navigation | `FentonNavigationController`, `FentonStackMotion`, `FentonEmbedding` | yes |
| `FentonUIKit` / Columns | `FentonColumnsViewController`, `FentonColumnEntry`, `FentonColumnsAppearance`, `FentonColumnPopGuarding`, `FentonColumnExitRequesting`, `FentonColumnBarHosting`, `FentonColumnTitleHeader`, `FentonDiscardConfirmation` | yes |
| `FentonUIKit` / Presentation | `FentonSheetPresenter`, `FentonSheetConfiguration`, `FentonSheetPlacement` | yes |
| `FentonUIKit` / other | `FentonFlyoutView` and `FentonFlyoutDestination`, `FentonContentSwapView`, `FentonWidthAwareCollectionView`, `FentonAnnouncer` | yes |
| Test support | `FentonUIKitTestHostSupport` (in-process window host), `FentonXCUITestSupport` (waits, rotate, edge swipe, clipping checks) | test bundles only |

`FentonPageContainerViewController`, `FentonContentContainmentView`, `FentonPaneContainerViewController` and
`FentonViewControllerHost` still compile unchanged; see the follow-ups.

## The seams an app fills

| Seam | Where | The app supplies |
|---|---|---|
| First content | `FentonWindowSceneDelegate.makeContentViewController(for:)` | its root pages |
| Root | `FentonWindowSceneDelegate.makeRootViewController(for:)` | a `FentonRootViewController` subclass: phases, sign-in, probes |
| Pages | `FentonPageViewController` or `FentonPageHost` subclass, `barItems()` | its own chrome; `chromeChanged()` when it changes |
| Page look | `FentonPageConfiguration`, `FentonMotion`, `FentonColumnsAppearance`, `FentonContentSwapView.Timing` | its tokens |
| When to split | `FentonSplitPolicy.allowsSplit(size:isRegularWidth:)` then `FentonColumnsViewController.setWide(_:)` | the call, on every layout |
| Empty column | `FentonColumnsViewController(makePlaceholder:)` | the empty state page |
| Column bar | `FentonColumnBarHosting.setColumnItems(_:)` on the section page | where Back or Close go |
| Navigation truth | `tag`, `reconcile(tags:make:animated:)`, `onUserPop` | its own route state |
| Holding a page open | `FentonColumnPopGuarding`, `FentonColumnExitRequesting` | save and discard rules |
| Admitting a pop | `FentonNavigationController.requestPop` | the confirmation |
| Stack motion | `FentonStackMotion(navigation:reduceMotion:)` | installing it (opt-in) |
| Hinge in tests | `FentonWindowSensors` | a stand-in Duo |

### A scene delegate and a page, from the harness fixture

```swift
final class FoundationSceneDelegate: FentonWindowSceneDelegate {
    private var root: FoundationRootViewController?

    override func makeRootViewController(for scene: UIWindowScene) -> FentonRootViewController {
        let root = FoundationRootViewController()
        self.root = root
        return root
    }

    override func makeContentViewController(for scene: UIWindowScene) -> UIViewController? {
        root?.makeContent()
    }
}

// In the root: the list is the columns' root, the shell page hosts the columns and owns the bar.
let list = FoundationListViewController()
let columns = FentonColumnsViewController(root: list, environment: environment) { FoundationEmptyPage() }
let shell = FoundationShellPage(environment: environment, list: list, columns: columns, onMenu: { … }, onSheet: { … })
let navigation = FentonNavigationController(rootViewController: shell)
// The navigation controller's delegate is weak: keep the motion in a property of the root.
let motion = FentonStackMotion(navigation: navigation, reduceMotion: { environment.reduceMotion },
                               isEnabled: { !columns.isWide })
navigation.delegate = motion
self.stackMotion = motion

// In the root's viewDidLayoutSubviews: the one rule, by geometry, never by device.
columns.setWide(policy.allowsSplit(size: view.bounds.size, isRegularWidth: traitCollection.horizontalSizeClass == .regular))

// A detail page is a FentonPageViewController. A row opens it with the standard UIKit call; the columns or the stack takes it.
final class FoundationDetailPage: FentonPageViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        install(scrollView: scroll)          // the page never sets contentInset; the system insets for bar and large title
    }
}
show(FoundationDetailPage(item: item, environment: environment), sender: self)
```

### How the pieces behave

| Rule | Behaviour |
|---|---|
| Split | Only wide landscape, each half at least 360 pt; never portrait, never a folded Duo. Hinge band while partly folded, midpoint plus a 1 pt gutter when flat or on an iPad. |
| Columns | Miller model, two visible: `[root] + entries`. Entries are moved by frame and never reparented. `show(_:sender:)` cuts the stack back to the sender's column, then appends. |
| Narrow | `setWide(false)` hands open local pages to the enclosing navigation stack; `setWide(true)` takes them off it and opens them as columns again. Tagged pages are the owner's to re-open (`reconcile`). |
| Back and Close | A bar item from the columns (Close on the first page, Back on later ones) plus a leading-edge pan. A page can block or confirm. |
| Swipe on a stack | UIKit's own swipes never call `popViewController`, so `FentonNavigationController` keeps them off while `requestPop` is set. `FentonStackMotion`'s edge pan pops through it and is admitted. |
| Page scroll | The page never writes `contentInset`; the scroll view is `.automatic` and named to the bar with `setContentScrollView(_, for: .top)`. |
| Orientation | `FentonRootViewController.supportedInterfaceOrientations` answers `FentonOrientationSupport.mask(for:presence:info:)`: the Info.plist set for the idiom, every orientation once a hinge has been seen. The first hinge asks each window's root to re-read it. |
| Reduce Motion | Slides become cross-fades; the edge pans still work. |

## What stays in apps

| Stays in the app | Why |
|---|---|
| Routes, navigators, session phases, sign-in | FentonPlatform never stores or reads a route. |
| Tokens: colours, fonts, spacing, motion values | The foundation takes them as values (`FentonMotion`, `FentonColumnsAppearance`, `FentonPageConfiguration`). |
| Copy, including the discard words and Back and Close labels | FentonPlatform ships no localisation resources. The defaults (`FentonColumnsAppearance.backLabel`/`closeLabel`, `FentonDiscardCopy`, `FentonFlyoutView.title`/`closeLabel`) are developer English in public, overridable values; apps pass localised copy. |
| Server UI, tiles, glass, modal chrome, dials | Not generic. |
| Layout census, `layoutSubviews` swizzles, Darwin rotation probes | Diagnostics of one app; counters go through `FentonTelemetry.increment`. |
| Reconnecting overlay, scroll-rate gate, list updater | Read app services. |

## native-home to FentonPlatform

| native-home | FentonPlatform | How |
|---|---|---|
| `HassUI.SplitPolicy` | `FentonSplitPolicy` | A wrapper with `minimumPaneWidth` 360; call sites unchanged. |
| `WindowFold`, `HingeAvoidance`, `DuoSheetPolicy`, `HeaderEdgeFade` | `FentonWindowFold`, `FentonHingeAvoidance`, `FentonSheetPolicy`, `FentonScrollEdgeFade` | Typealiases. `DuoSheetPolicy.deviceHasHinge` becomes `FentonHingePresence`. |
| `UKObservation`, `UKObservationBag` | `FentonObservation`, `FentonObservationBag` | A thin wrapper: HassUI's `UKObservation.around` keeps stored state, so it wraps `FentonObservation` rather than aliasing it; the logic tally stays in HassUI. |
| `UKShellEnvironment` | `FentonWindowEnvironment` | NH's class composes it; style, chrome, arrival, attention, offline stay NH. |
| `UKDeviceSignals`, `UKReflow`, `UKHinge` | `FentonWindowSignals`, `FentonReflow`, `FentonHingeAvoidingView` | The `UKHinge` global becomes `environment.band`; the two static overrides become `FentonWindowSensors`. |
| `UKPageViewController`, `UKPageHost` | `FentonPageViewController`, `FentonPageHost` | `FentonPageHost` is `open`: NH subclasses it, overrides `barItems()` (Quick Links, Profile, `HassSheetWidth`) and `syncChrome()`, forwards its sheet-fitting protocol by reading `child`, and passes the subclass to `FentonPageHost.wrapped(_:environment:make:)`. |
| `UKColumnsViewController`, `UKColumnEntry` | `FentonColumnsViewController`, `FentonColumnEntry` | NH passes `makePlaceholder`; tags are `ShellRoute`. The `shell` argument is the window environment; there is no `reflow` argument (the window signals animate a posture change) and a `motion` value replaces `UKMotion`. |
| `UKColumnPopGuarding`, `UKColumnExitRequesting`, `UKColumnBarHosting`, `UKColumnBar` | `FentonColumnPopGuarding`, `FentonColumnExitRequesting`, `FentonColumnBarHosting` | The columns now build the Back or Close item and hand `[UIBarButtonItem]` to the host; the host places it. |
| `UKColumnTitleHeader` | `FentonColumnTitleHeader` | Side inset and spacing are arguments; the page attaches it while it is a child of the columns. |
| `UKDiscardGuard.confirm` | `FentonDiscardConfirmation.present` | Words from `FentonDiscardCopy`. The sheet-level `apply` and `leave` helpers read `DiscardGuard` and stay in HassUI. |
| `UKNativeExitNavigationController`, `UKStackMotion` | `FentonNavigationController`, `FentonStackMotion` | Direct. The motion takes `FentonMotion`, a Reduce Motion closure and an announce closure. |
| `UKSheetPlacement` | `FentonSheetPlacement` | `UKHassModal` stays and calls `place`. |
| `UKRootViewController`, `UKSceneUpgrade` | `FentonRootViewController`, `FentonSceneUpgrade` | NH keeps phases, sign-in, arrival, probes. |
| `UKSmoothContentSwapView`, `UKWidthAwareCollectionView`, `UKNavigationFlyoutView` | `FentonContentSwapView`, `FentonWidthAwareCollectionView`, `FentonFlyoutView` | Direct. |

## FestivalNativeApps notes

| Point | Note |
|---|---|
| Today | A SwiftUI app with no UIKit foundation; its UIKit sits in six files. Adopting this means writing UIKit pages for the surfaces it chooses. |
| Share first | The pure types in `FentonAppleCore`: hinge state and presence, orientation policy, the 360 pt split rule, the accessibility focus chooser. Festival's two copies can be deleted once it adopts them. Core imports no UIKit, so Festival's macOS app can use it. |
| Columns | Miller columns, root always visible. Festival's "list first, 50/50 on selection, profile covers the list" is a **cover** split and is not built. Ask before adding a seam. |
| SDK | Festival already uses plain `#available(iOS 27.1, *)`, so it matches the SDK requirement. |
| Stack motion, flyout, content swap | S+H design decisions with web-parity timings; Festival has its own SwiftUI drawer. Use only if wanted. |

## Corrections to the research note

| Note said | Measured |
|---|---|
| `FentonPageContainerViewController.viewDidLayoutSubviews` probably runs a per-frame layout loop. | Lane C counted `layoutSubviews` over two 0.25 s run-loop turns: the old container idles at 0 passes and one requested layout costs 1, the same as `FentonPageViewController`. There is no loop. The old container is superseded for its scroll-inset model, not for a loop. |
| `FentonColumnsViewController.init` takes `reflow:`. | It takes `motion:`. A posture change already animates through `FentonWindowSignals` and `FentonReflow`, and the columns write no layout input. |
| `FentonColumnBarHosting` is `setColumnItems(_:)` with one item. | The host gets the open page's own items followed by the columns' Back or Close item; an empty array removes the group. |

## Tests and journeys

| Where | What |
|---|---|
| `Tests/Core` | Pure logic, run with `swift test` on the Mac host. |
| `Tests/UIKitHosted`, `Harness/HostedTests` | UIKit behaviour in the simulator, inside the harness app. A hosted test drives the window through `FentonWindowSignals` with a stand-in `FentonWindowSensors` (`FakeDuo`), never through the environment's setters. |
| `Harness/UITests/FoundationJourneys.swift` | Five journeys, launched with `--foundation`: push and edge-swipe back with the list's scroll kept; iPad landscape split, rotate to portrait (pushed, nothing lost) and back; the sheet is a page sheet; AX XXXL text does not clip; the flyout opens and closes. |
| Duo postures | **Not in this harness.** A folding device is needed; check partly folded, flat and folded with the shared pose tool. The hosted tests cover the fold maths and the columns on a hinge band with a stand-in sensor. |
| VoiceOver | The modal flag is read in a hosted test; the XCUI runner cannot read it. |

## Known follow-ups

| Item | Owner |
|---|---|
| Cleanup after the owner's uncommitted harness work lands: remove `FentonPageContainerViewController`, `FentonContentContainmentView`, `FentonPaneContainerViewController`, `FentonViewControllerHost`; move `HarnessRootViewController` to the new page base and retire its `--baseline-containment` arm; link this page from `docs/apple/README.md`. | Lane E |
| Rename `TelemetrySample` and `TelemetrySnapshot` to the `Fenton` prefix. | Lane E |
| `Harness/project.yml` takes two lines from the owner's work (`info.path` and `GENERATE_INFOPLIST_FILE` on the UI tests) so the committed spec generates with xcodegen 2.45.4. The generated `Harness/App/Info.plist` is not committed. | Merge with the owner's work |
| Festival's "cover" split. | Only when Festival asks |
| Duo pose evidence for columns, sheets and the flyout. | Verifier, with the pose tool |
