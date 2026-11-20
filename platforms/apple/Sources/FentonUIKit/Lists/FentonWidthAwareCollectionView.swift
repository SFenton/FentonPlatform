#if os(iOS)
import UIKit

/// A collection view for self-sizing cells that cannot be measured early. A cell sized while its list or sheet is still taking
/// its width (zero, or the width of a sheet that is still presenting) wraps its labels to nothing and reports a huge height, and
/// the layout keeps that height until something reconfigures the cell. Two parts, used together by every list or grid of
/// self-sizing cells:
/// - ``FentonWidthAwareCollectionView`` drops the layout's measured heights whenever its width changes;
/// - ``UIKit/UICollectionViewCell/fentonFitted(_:)`` measures a cell at the width the layout proposes, with its layout pass redone.
public final class FentonWidthAwareCollectionView: UICollectionView {
    private var laidOutWidth: CGFloat = 0

    /// A drag that begins on a tap control scrolls the list: a `UIControl` (a tile) otherwise keeps its touch, and at the largest
    /// accessibility sizes, where one tile fills the window, the list could not be scrolled from the tiles. The system's
    /// continuous controls keep their drags; custom sliders and dials track with pan recognizers, which this does not touch.
    public override func touchesShouldCancel(in view: UIView) -> Bool {
        if view is UISlider || view is UISwitch || view is UIStepper || view is UITextField || view is UITextView || view is UIDatePicker {
            return super.touchesShouldCancel(in: view)
        }
        return true
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width.rounded()
        guard width != laidOutWidth else { return }
        let first = laidOutWidth == 0
        laidOutWidth = width
        // The first width is the one the first measurement used; a later one means the rows were measured at another.
        if !first { collectionViewLayout.invalidateLayout() }
    }
}
#endif
