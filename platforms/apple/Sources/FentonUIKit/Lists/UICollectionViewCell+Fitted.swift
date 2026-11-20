#if os(iOS)
import UIKit

extension UICollectionViewCell {
    /// `layoutAttributes` with the height this cell needs at the width the layout proposes (the system's fitting, with the cell's
    /// own layout redone first so labels re-wrap at that width). Call from `preferredLayoutAttributesFitting`.
    public func fentonFitted(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes ?? layoutAttributes
        let width = layoutAttributes.size.width
        guard width > 1 else { return attributes }
        bounds.size.width = width
        contentView.setNeedsLayout()
        setNeedsLayout()
        layoutIfNeeded()
        let fitted = systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        attributes.size = CGSize(width: width, height: ceil(fitted.height))
        return attributes
    }
}
#endif
