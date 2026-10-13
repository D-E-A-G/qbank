import Foundation

/// Calm motion with no bounce and nothing celebratory. Respect Reduce Motion.
public enum QBankMotion {
    /// Press feedback.
    public static let instant: TimeInterval = 0.1
    /// A state change: select, check.
    public static let quick: TimeInterval = 0.18
    /// The feedback reveal, a push.
    public static let standard: TimeInterval = 0.26
    /// Presenting a sheet.
    public static let sheet: TimeInterval = 0.42

    /// A cubic Bézier timing curve, as in CSS `cubic-bezier(x1, y1, x2, y2)`.
    public struct Curve: Hashable, Sendable {
        public let x1, y1, x2, y2: Double
    }

    public static let easeStandard = Curve(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    public static let easeOut = Curve(x1: 0.2, y1: 0.8, x2: 0.2, y2: 1)
    /// iOS-like sheet presentation.
    public static let easeSheet = Curve(x1: 0.32, y1: 0.72, x2: 0, y2: 1)
}
