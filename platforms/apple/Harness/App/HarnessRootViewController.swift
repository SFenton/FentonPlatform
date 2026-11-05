import UIKit
import FentonAppleTelemetry
import FentonUIKit

private enum HarnessTheme {
    case ocean
    case sunset

    var accent: UIColor {
        switch self {
        case .ocean: return .systemBlue
        case .sunset: return .systemOrange
        }
    }

    var background: UIColor {
        switch self {
        case .ocean: return .systemGroupedBackground
        case .sunset: return UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        }
    }
}

final class HarnessRootViewController: UIViewController {
    private let theme: HarnessTheme = ProcessInfo.processInfo.arguments.contains("--sunset") ? .sunset : .ocean
    private let isBaselineContainment = ProcessInfo.processInfo.arguments.contains("--baseline-containment")
    private lazy var telemetry = FentonTelemetry(
        enabled: ProcessInfo.processInfo.arguments.contains("--benchmark"),
        metadata: [
            "arm": isBaselineContainment ? "baseline-direct-containment" : "shared-containment",
            "fixture": theme == .ocean ? "ocean" : "sunset",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "os": UIDevice.current.systemVersion,
            "device": UIDevice.current.model,
            "runtime": "iOS-\(UIDevice.current.systemVersion)",
            "configuration": "250-rows-normal-animation"
        ]
    )
    private var populatedPage: PopulatedPageViewController?
    private var hasStartedBenchmark = false
    private let benchmarkRunID = UUID().uuidString

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        title = theme == .ocean ? "Ocean fixture" : "Sunset fixture"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Open sheet",
            style: .plain,
            target: self,
            action: #selector(openSheet)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "open-sheet"

        let content = PopulatedPageViewController(theme: theme, telemetry: telemetry)
        populatedPage = content
        if isBaselineContainment {
            addChild(content)
            content.view.translatesAutoresizingMaskIntoConstraints = false
            content.scrollView.contentInsetAdjustmentBehavior = .never
            view.addSubview(content.view)
            NSLayoutConstraint.activate([
                content.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                content.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                content.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                content.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
            content.didMove(toParent: self)
        } else {
            let page = FentonPageContainerViewController(telemetry: telemetry)
            page.embed(content, mainScrollView: content.scrollView)
            addChild(page)
            page.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(page.view)
            NSLayoutConstraint.activate([
                page.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                page.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                page.view.topAnchor.constraint(equalTo: view.topAnchor),
                page.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            page.didMove(toParent: self)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard telemetry.isEnabled, !hasStartedBenchmark else { return }
        hasStartedBenchmark = true
        telemetry.updateMetadata([
            "benchmarkRunID": benchmarkRunID,
            "windowWidth": String(format: "%.1f", view.bounds.width),
            "windowHeight": String(format: "%.1f", view.bounds.height),
            "scale": String(format: "%.1f", view.window?.screen.scale ?? UIScreen.main.scale)
        ])
        populatedPage?.beginBenchmark { [weak self] in
            self?.writeBenchmarkArtifact()
        }
    }

    @objc private func openSheet() {
        let sheet = HarnessSheetViewController(theme: theme)
        FentonSheetPresenter.present(sheet, from: self)
    }

    private func writeBenchmarkArtifact() {
        guard let data = try? telemetry.snapshot().jsonData() else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fenton-harness-benchmark.json")
        try? data.write(to: url, options: .atomic)
    }
}

private final class PopulatedPageViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let theme: HarnessTheme
    private let telemetry: FentonTelemetry
    let scrollView = UITableView(frame: .zero, style: .insetGrouped)
    private var scrollStartedAt: UInt64?
    private var scrollInterval: TelemetryInterval?
    private var idleInterval: TelemetryInterval?
    private var benchmarkCompletion: (() -> Void)?
    private var benchmarkGeneration = 0
    private var didRecordFirstPresentation = false
    private var didDisplayFirstContent = false
    private var pendingBenchmarkGeneration: Int?
    private var firstDisplayLink: CADisplayLink?
    private var firstPresentationInterval: TelemetryInterval?

    init(theme: HarnessTheme, telemetry: FentonTelemetry) {
        self.theme = theme
        self.telemetry = telemetry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.accessibilityIdentifier = "populated-page"
        scrollView.dataSource = self
        scrollView.delegate = self
        scrollView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        scrollView.rowHeight = UITableView.automaticDimension
        scrollView.estimatedRowHeight = 56
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        telemetry.measure("reload-invocation") { scrollView.reloadData() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didRecordFirstPresentation else { return }
        didRecordFirstPresentation = true
        firstPresentationInterval = telemetry.beginInterval()
        firstDisplayLink = CADisplayLink(target: self, selector: #selector(recordFirstDisplayedContent))
        firstDisplayLink?.add(to: .main, forMode: .common)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        firstDisplayLink?.invalidate()
        firstDisplayLink = nil
        cancelBenchmark()
    }

    @objc private func recordFirstDisplayedContent() {
        firstDisplayLink?.invalidate()
        firstDisplayLink = nil
        let visibleRows = scrollView.indexPathsForVisibleRows?.count ?? 0
        if let firstPresentationInterval {
            telemetry.endInterval(
                firstPresentationInterval,
                named: "first-presented-content",
                metadata: windowMetadata(visibleRows: visibleRows).merging([
                    "contentState": "first-displayed-frame",
                    "clockSemantics": "CADisplayLink-tick-after-viewDidAppear"
                ]) { _, new in new }
            )
        }
        firstPresentationInterval = nil
        didDisplayFirstContent = true
        if let generation = pendingBenchmarkGeneration {
            pendingBenchmarkGeneration = nil
            scheduleBenchmarkStart(generation: generation)
        }
    }

    func beginBenchmark(completion: @escaping () -> Void) {
        cancelScrollBenchmark()
        benchmarkGeneration += 1
        let generation = benchmarkGeneration
        benchmarkCompletion = completion
        guard didDisplayFirstContent else {
            pendingBenchmarkGeneration = generation
            return
        }
        scheduleBenchmarkStart(generation: generation)
    }

    private func scheduleBenchmarkStart(generation: Int) {
        idleInterval = telemetry.beginInterval()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.benchmarkGeneration == generation else { return }
            if let idleInterval = self.idleInterval {
                self.telemetry.endInterval(
                    idleInterval,
                    named: "idle-main-turn",
                    metadata: self.windowMetadata(visibleRows: self.scrollView.indexPathsForVisibleRows?.count ?? 0)
                        .merging(["contentState": "idle-main-turn"]) { _, new in new }
                )
            }
            self.idleInterval = nil
            self.scrollStartedAt = DispatchTime.now().uptimeNanoseconds
            self.scrollInterval = self.telemetry.beginInterval()
            let bottom = max(0, self.scrollView.contentSize.height - self.scrollView.bounds.height)
            self.scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: true)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollStartedAt != nil, benchmarkCompletion != nil else { return }
        self.scrollStartedAt = nil
        if let scrollInterval {
            telemetry.endInterval(
                scrollInterval,
                named: "populated-scroll",
                metadata: windowMetadata(visibleRows: self.scrollView.indexPathsForVisibleRows?.count ?? 0)
                    .merging(["contentState": "animated-populated-scroll"]) { _, new in new }
            )
        }
        self.scrollInterval = nil
        let completion = benchmarkCompletion
        benchmarkCompletion = nil
        completion?()
    }

    private func cancelScrollBenchmark() {
        benchmarkGeneration += 1
        pendingBenchmarkGeneration = nil
        if let idleInterval { telemetry.cancelInterval(idleInterval) }
        if let scrollInterval { telemetry.cancelInterval(scrollInterval) }
        idleInterval = nil
        scrollInterval = nil
        scrollStartedAt = nil
        benchmarkCompletion = nil
    }

    private func cancelBenchmark() {
        cancelScrollBenchmark()
        firstDisplayLink?.invalidate()
        firstDisplayLink = nil
        if let firstPresentationInterval { telemetry.cancelInterval(firstPresentationInterval) }
        firstPresentationInterval = nil
        didDisplayFirstContent = false
    }

    private func windowMetadata(visibleRows: Int) -> [String: String] {
        [
            "windowWidth": String(format: "%.1f", view.bounds.width),
            "windowHeight": String(format: "%.1f", view.bounds.height),
            "scale": String(format: "%.1f", view.window?.screen.scale ?? UIScreen.main.scale),
            "visibleRows": String(visibleRows),
            "rowCount": "250",
            "contentWidth": String(format: "%.1f", scrollView.bounds.width),
            "contentHeight": String(format: "%.1f", scrollView.bounds.height),
            "contentInsetTop": String(format: "%.1f", scrollView.contentInset.top),
            "contentInsetBottom": String(format: "%.1f", scrollView.contentInset.bottom),
            "indicatorInsetBottom": String(format: "%.1f", scrollView.scrollIndicatorInsets.bottom),
            "insetAdjustment": String(describing: scrollView.contentInsetAdjustmentBehavior)
        ]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 250 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = "Fixture row \(indexPath.row + 1)"
        content.secondaryText = "Populated content for \(theme == .ocean ? "ocean" : "sunset")"
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        cell.contentConfiguration = content
        cell.accessibilityIdentifier = "fixture-row-\(indexPath.row)"
        return cell
    }
}

private final class HarnessSheetViewController: UIViewController {
    private let theme: HarnessTheme

    init(theme: HarnessTheme) {
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        let label = UILabel()
        label.text = "Adaptive sheet"
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = theme.accent
        label.accessibilityIdentifier = "sheet-title"
        label.translatesAutoresizingMaskIntoConstraints = false
        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.titleLabel?.font = .preferredFont(forTextStyle: .body)
        close.titleLabel?.adjustsFontForContentSizeCategory = true
        close.accessibilityIdentifier = "sheet-close"
        close.addTarget(self, action: #selector(closeSheet), for: .primaryActionTriggered)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        view.addSubview(close)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            close.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            close.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24),
            close.bottomAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.bottomAnchor),
            close.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    @objc private func closeSheet() {
        dismiss(animated: true)
    }
}
