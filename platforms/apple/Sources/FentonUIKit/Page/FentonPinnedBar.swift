#if os(iOS)
import UIKit

/// A bar pinned to one edge of a ``FentonPageViewController``: the bar sits in the page's `view` on the safe area's edge, outside the
/// header-fade mask, and its height joins the page's `additionalSafeAreaInsets` so the content's last row scrolls clear of it. A
/// bottom bar rides above the keyboard.
///
/// With a `scrollView` the bar gets the iOS 26 scroll edge interaction and the scroll view a soft edge under it (HIG: Scroll views,
/// Scroll edge effects). Before iOS 26, `barMaterial` puts the bar material behind a full-width bar; `alwaysMaterial` does it on
/// every system (what ``accessory(_:insets:)`` uses). A page installs its ``FentonPageViewController/bottomAccessory`` through
/// this; a page that needs a top bar or its own bar calls ``install(in:)`` itself:
///
/// ```swift
/// private var pinnedBar: FentonPinnedBar?
/// override func viewDidLoad() { super.viewDidLoad(); pinnedBar?.install(in: self) }
/// override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); pinnedBar?.layoutChanged() }
/// ```
@MainActor
public final class FentonPinnedBar {
    // MARK: - Types

    /// The edge a bar is pinned to.
    public enum Edge: Sendable { case top, bottom }

    // MARK: - State

    /// The bar's view; its height comes from its own layout.
    public let bar: UIView
    private let edge: Edge
    private let spacing: CGFloat
    private var scrollView: UIScrollView?
    private var edgeInteraction: Any?
    private let material: UIVisualEffectView?
    private weak var page: FentonPageViewController?
    private var lastHeight: CGFloat = -1
    private var boundsObservation: NSKeyValueObservation?
    /// The bar's bottom edge: the system's bottom safe area, kept apart from the inset this page adds for the bar (the keyboard guide
    /// and the safe area guide both include `additionalSafeAreaInsets`, so a bar pinned to either would chase its own inset).
    private var restingBottom = NSLayoutConstraint()

    // MARK: - Lifecycle

    /// Creates a pinned bar.
    /// - Parameters:
    ///   - bar: The bar.
    ///   - edge: The edge to pin to.
    ///   - spacing: Space between the page's content and the bar.
    ///   - scrollView: The page's scroll view, for the scroll edge interaction.
    ///   - barMaterial: Whether before iOS 26 the bar sits on the bar material.
    ///   - alwaysMaterial: Whether the bar sits on the bar material on every system.
    public init(bar: UIView, edge: Edge = .bottom, spacing: CGFloat = 0, scrollView: UIScrollView? = nil,
                barMaterial: Bool = false, alwaysMaterial: Bool = false) {
        self.bar = bar
        self.edge = edge
        self.spacing = spacing
        self.scrollView = scrollView
        if alwaysMaterial {
            material = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        } else if barMaterial, #unavailable(iOS 26) {
            material = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        } else {
            material = nil
        }
    }

    /// A bar for a page's bottom accessory (a status strip): `accessory` inside `insets` on the bar material, pinned to the bottom
    /// safe area. The page's inset for it is the bar's height, added to the safe area once.
    public static func accessory(_ accessory: UIView, insets: UIEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)) -> FentonPinnedBar {
        let holder = UIView()
        accessory.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(accessory)
        NSLayoutConstraint.activate([
            accessory.topAnchor.constraint(equalTo: holder.topAnchor, constant: insets.top),
            accessory.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -insets.bottom),
            accessory.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: insets.left),
            accessory.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -insets.right),
        ])
        return FentonPinnedBar(bar: holder, alwaysMaterial: true)
    }

    // MARK: - Installing

    /// Adds the bar to the page's view; call from `viewDidLoad` after `super`.
    public func install(in page: FentonPageViewController) {
        self.page = page
        let view: UIView = page.view
        if let material {
            view.addSubview(material)
            material.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                material.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                material.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
        view.addSubview(bar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        let guide = view.safeAreaLayoutGuide
        let keyboard = view.keyboardLayoutGuide
        keyboard.usesBottomSafeArea = false
        if edge == .bottom {
            // Above the keyboard while one is up (the guide's top is the view's bottom otherwise), else on the system's safe area.
            restingBottom = bar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            restingBottom.priority = .defaultHigh
            NSLayoutConstraint.activate([bar.bottomAnchor.constraint(lessThanOrEqualTo: keyboard.topAnchor), restingBottom])
        } else {
            bar.topAnchor.constraint(equalTo: guide.topAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
        ])
        if let material {
            let bottomEdge = edge == .bottom
            NSLayoutConstraint.activate([
                bottomEdge ? material.bottomAnchor.constraint(equalTo: view.bottomAnchor) : material.topAnchor.constraint(equalTo: view.topAnchor),
                bottomEdge ? material.topAnchor.constraint(equalTo: bar.topAnchor) : material.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            ])
        }
        // A bar that changes height on its own (a section swap, a text size) asks for the inset again one turn later, never from a
        // layout pass.
        boundsObservation = bar.observe(\.bounds, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue?.height != change.newValue?.height else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layoutChanged() } }
        }
        follow(scrollView)
    }

    /// Takes the bar out of the page and gives back the inset it added.
    public func uninstall() {
        boundsObservation = nil
        bar.removeFromSuperview()
        material?.removeFromSuperview()
        guard let page else { return }
        var insets = page.additionalSafeAreaInsets
        if edge == .bottom { insets.bottom = 0 } else { insets.top = 0 }
        if insets != page.additionalSafeAreaInsets { page.additionalSafeAreaInsets = insets }
        lastHeight = -1
        self.page = nil
    }

    /// The scroll view whose content passes under the bar (the iOS 26 scroll edge interaction and the soft edge under the bar). A
    /// page whose scroller changes hands the new one here.
    public func follow(_ next: UIScrollView?) {
        if #available(iOS 26, *) {
            if let old = edgeInteraction as? UIScrollEdgeElementContainerInteraction {
                bar.removeInteraction(old)
                edgeInteraction = nil
            }
            if let next {
                let interaction = UIScrollEdgeElementContainerInteraction()
                interaction.scrollView = next
                interaction.edge = edge == .bottom ? .bottom : .top
                bar.addInteraction(interaction)
                edgeInteraction = interaction
                if edge == .bottom { next.bottomEdgeEffect.style = .soft }
            }
        }
        scrollView = next
    }

    // MARK: - Layout

    /// Call from the page's `viewDidLayoutSubviews`: adds the bar's height to the page's safe area, only when it changed.
    public func layoutChanged() {
        guard let page else { return }
        let view: UIView = page.view
        let system = max(0, view.safeAreaInsets.bottom - (edge == .bottom ? page.additionalSafeAreaInsets.bottom : 0))
        if edge == .bottom, abs(restingBottom.constant + system) > 0.5 { restingBottom.constant = -system }
        let lift = edge == .bottom ? max(0, view.bounds.height - view.keyboardLayoutGuide.layoutFrame.minY - system) : 0
        // The height the bar will have, asked of its constraints: its own `bounds` still hold the last pass's height when a section
        // swap or a text size change resized it in this one.
        let fitting = bar.systemLayoutSizeFitting(
            CGSize(width: max(0, view.safeAreaLayoutGuide.layoutFrame.width), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let barHeight = fitting > 0 ? ceil(fitting) : bar.bounds.height
        let height = (bar.isHidden ? 0 : barHeight + spacing) + lift
        guard height != lastHeight else { return }
        lastHeight = height
        var insets = page.additionalSafeAreaInsets
        if edge == .bottom { insets.bottom = height } else { insets.top = height }
        page.additionalSafeAreaInsets = insets
    }
}
#endif
