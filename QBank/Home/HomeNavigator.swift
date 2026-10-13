import Observation
import SwiftUI

/// The Home tab's navigation stack, so a screen deep in it can open another one or step back,
/// as the exam result does with Open Review and Back to course.
@Observable
final class HomeNavigator {
    var path = NavigationPath()

    func open(_ route: some Hashable) {
        path.append(route)
    }

    /// Steps back one screen.
    func back() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
}

/// A screen of a course past the Course screen itself: the tiles' Review, Terms, and Exam.
enum StudyRoute: Hashable {
    case review(CourseRef)
    case terms(CourseRef)
    case exam(ExamSetupRoute)
}

/// The course a study screen belongs to, with what its subtitle says before anything loads.
struct CourseRef: Hashable {
    let id: String
    let code: String
    let title: String
}

/// The Exam setup screen, from the Exam tile with nothing ticked, or from an exam folder's Start
/// button with that exam's weeks ticked.
struct ExamSetupRoute: Hashable {
    let course: CourseRef
    /// The weeks ticked when it opens.
    var weeks: [String] = []
    /// The course exam those weeks come from, named above the week list.
    var examName: String?
}
