/// Pure detent policy. UIKit maps these values to native detents.
public enum FentonSheetHeightPolicy: Sendable, Equatable {
    /// The medium detent only.
    case medium
    /// The large detent only.
    case large
    /// Both the medium and the large detent.
    case mediumAndLarge
}
