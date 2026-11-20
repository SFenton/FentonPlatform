#if os(iOS)
import UIKit

/// A fixed inline bar title, for a bar that never minimises: the vertical bar's title.
///
/// Where the system draws a vertical bar (the folded outer display in both rotations, the unfolded inner display in landscape, the
/// partial Book landscape) the page keeps a semibold inline title (24 pt by default, Dynamic Type, capped at 30 pt) in a bar that
/// never minimises, so the title is not taken away when the page scrolls. Every other window keeps the system's title: with
/// `fixed` false this writes nothing.
///
/// The system still places and truncates the title and VoiceOver reads one header, because the text goes through
/// `UINavigationItem.attributedTitle` (iOS 26). On iOS 26 and later clearing `attributedTitle` also erases `title`, so ``restore()``
/// clears it only when it is still the string and font this wrote and then writes the plain title back. Before iOS 26 the treatment
/// is not available and nothing is written.
@MainActor
public final class FentonFixedBarTitle {
    // MARK: - State

    private let pointSize: CGFloat
    private let maximumPointSize: CGFloat
    private weak var item: UINavigationItem?
    private var observation: NSKeyValueObservation?
    private var installedString: String?
    private var installedFont: UIFont?
    private var minimizationWasSet = false
    private var traits = UITraitCollection.current
    /// The page's `title`: a navigation item reads nil until it is set on the item itself.
    private var fallbackTitle: String?

    /// How many times the attributed title was written; tests assert it is one for an unchanged title.
    public private(set) var writeCount = 0

    // MARK: - Lifecycle

    /// Creates a title treatment.
    /// - Parameters:
    ///   - pointSize: The title's point size at the default text size.
    ///   - maximumPointSize: The largest size Dynamic Type grows it to.
    public init(pointSize: CGFloat = 24, maximumPointSize: CGFloat = 30) {
        self.pointSize = pointSize
        self.maximumPointSize = maximumPointSize
    }

    /// The title font at `traits`' Dynamic Type size.
    public func font(compatibleWith traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: pointSize, weight: .semibold),
            maximumPointSize: maximumPointSize, compatibleWith: traits)
    }

    // MARK: - Applying

    /// Applies or removes the treatment for `item`. Idempotent; call whenever the window, the title or the text size may have
    /// changed.
    /// - Parameters:
    ///   - item: The page's navigation item.
    ///   - fallbackTitle: The page's `title`, used while `item.title` is nil.
    ///   - fixed: Whether the treatment applies; false restores the plain title.
    ///   - traits: The page's traits, for the Dynamic Type size.
    public func update(item: UINavigationItem, fallbackTitle: String?, fixed: Bool, traits: UITraitCollection) {
        guard fixed else { restore(); return }
        self.traits = traits
        self.fallbackTitle = fallbackTitle
        if self.item !== item {
            restore()
            self.item = item
            // A new title (the page renamed itself) is mirrored on the next turn, never inside the change.
            observation = item.observe(\.title, options: [.new]) { [weak self, weak item] _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { if let self, let item { self.mirror(item, traits: self.traits) } }
                }
            }
        }
        mirror(item, traits: traits)
        if #available(iOS 27.0, *), item.navigationBarMinimization.minimizationBehavior != .never {
            item.navigationBarMinimization.minimizationBehavior = .never
            minimizationWasSet = true
        }
    }

    private func mirror(_ item: UINavigationItem, traits: UITraitCollection) {
        guard #available(iOS 26.0, *), let title = item.title ?? fallbackTitle, !title.isEmpty else { return }
        let font = font(compatibleWith: traits)
        // UIKit reads a plain title back as an attributed one, so "has an attributed title" is not "still has ours".
        if installedString == title, installedFont == font, holdsOwnTitle(item) { return }
        installedString = title
        installedFont = font
        writeCount += 1
        item.attributedTitle = AttributedString(NSAttributedString(string: title, attributes: [.font: font]))
    }

    /// Gives the plain title and the automatic bar back. Idempotent; touches nothing this did not write.
    public func restore() {
        defer { installedString = nil; installedFont = nil; observation = nil; item = nil; minimizationWasSet = false }
        guard let item else { return }
        observation = nil
        if #available(iOS 27.0, *), minimizationWasSet { item.navigationBarMinimization.minimizationBehavior = .automatic }
        guard #available(iOS 26.0, *), let string = installedString, holdsOwnTitle(item) else { return }
        let plain = item.title ?? fallbackTitle ?? string
        item.attributedTitle = nil
        item.title = plain
    }

    @available(iOS 26.0, *)
    private func holdsOwnTitle(_ item: UINavigationItem) -> Bool {
        guard let string = installedString, let font = installedFont, let current = item.attributedTitle else { return false }
        return String(current.characters) == string && current.runs.first?.uiKit.font == font
    }
}
#endif
