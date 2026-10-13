import Foundation

/// The 4-point spacing scale and the semantic gaps built on it. Points equal CSS px.
public enum QBankSpacing {
    public static let space0: CGFloat = 0
    public static let space1: CGFloat = 2
    public static let space2: CGFloat = 4
    public static let space3: CGFloat = 8
    public static let space4: CGFloat = 12
    public static let space5: CGFloat = 16
    public static let space6: CGFloat = 20
    public static let space7: CGFloat = 24
    public static let space8: CGFloat = 32
    public static let space9: CGFloat = 40
    public static let space10: CGFloat = 48
    public static let space11: CGFloat = 64

    /// Screen side margin on iPhone.
    public static let gutterPhone: CGFloat = 16
    /// Content side margin on iPad and Mac.
    public static let gutterTablet: CGFloat = 24
    /// Between stacked cards or answer options.
    public static let gapStack: CGFloat = 12
    /// Between sections.
    public static let gapSection: CGFloat = 32
    /// The minimum hit target.
    public static let rowMin: CGFloat = 44
    public static let rowPaddingVertical: CGFloat = 12
    public static let rowPaddingHorizontal: CGFloat = 16
}

/// Corner radii. Use them with `.continuous` corners.
public enum QBankRadius {
    /// Checkboxes, the inside of chips.
    public static let xs: CGFloat = 6
    /// Buttons, inputs, answer options.
    public static let sm: CGFloat = 10
    /// Cards, tiles, grouped lists.
    public static let md: CGFloat = 14
    /// Sheet tops.
    public static let lg: CGFloat = 20
    // Pills (chips, timer, tinted labels) use `Capsule`.
}

public enum QBankBorder {
    /// Card and list outlines, separators.
    public static let hairline: CGFloat = 0.5
    public static let regular: CGFloat = 1
    /// Selected and revealed answer options.
    public static let emphasis: CGFloat = 1.5
}

/// Layout constants for iPhone, iPad and Mac.
public enum QBankLayout {
    public static let sidebarWidth: CGFloat = 280
    /// The runner's reading column.
    public static let contentMax: CGFloat = 720
    /// Grids such as Home on Mac.
    public static let contentMaxWide: CGFloat = 1040
    public static let tabBarHeight: CGFloat = 49
    public static let navBarHeight: CGFloat = 44
}
