import Foundation

/// The course page as she left it on this phone: which folders she opened or closed by hand, and
/// whether she looks at it by week or by exam. Like the web's, it stays on the device, per course,
/// and through sign-out. Folders she never touched keep following the defaults as her progress moves.
final class CourseMemory {
    /// How the course page groups its sets.
    enum View: String, CaseIterable {
        case weeks
        case exams
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The view she last chose for the course, or nil before she chose one.
    func view(course: String) -> View? {
        defaults.string(forKey: Self.viewKey(course)).flatMap(View.init(rawValue:))
    }

    func setView(_ view: View, course: String) {
        defaults.set(view.rawValue, forKey: Self.viewKey(course))
    }

    /// Week folders she opened (true) or closed (false) by hand, by week label.
    func weeks(course: String) -> [String: Bool] {
        flags(Self.weeksKey(course))
    }

    func setWeek(_ label: String, open: Bool, course: String) {
        var weeks = weeks(course: course)
        weeks[label] = open
        defaults.set(weeks, forKey: Self.weeksKey(course))
    }

    /// Exam folders she opened or closed by hand, by course exam id.
    func exams(course: String) -> [String: Bool] {
        flags(Self.examsKey(course))
    }

    func setExam(_ id: String, open: Bool, course: String) {
        var exams = exams(course: course)
        exams[id] = open
        defaults.set(exams, forKey: Self.examsKey(course))
    }

    /// The open or closed flags under a key, ignoring anything this did not write.
    private func flags(_ key: String) -> [String: Bool] {
        (defaults.dictionary(forKey: key) ?? [:]).compactMapValues { $0 as? Bool }
    }

    // The web keeps open weeks under `qbank.course-weeks.<course id>` in localStorage.
    static func viewKey(_ course: String) -> String { "qbank.course-view.\(course)" }
    static func weeksKey(_ course: String) -> String { "qbank.course-weeks.\(course)" }
    static func examsKey(_ course: String) -> String { "qbank.course-exams.\(course)" }
}
