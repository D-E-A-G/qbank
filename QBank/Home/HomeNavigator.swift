import Observation
import QBankKit
import SwiftUI

/// The Home tab's navigation, so a screen deep in it can open another one or step back, as the
/// exam result does with Open Review and Back to course.
///
/// On iPhone, one stack holds the courses and every screen over them. On iPad, the course chosen in
/// the sidebar is the root of the stack beside it, which holds the screens past the course.
@Observable
final class HomeNavigator {
    /// True on iPad, where courses sit in a sidebar beside the course chosen.
    let isSplit: Bool
    var path = NavigationPath()
    /// The course open beside the sidebar on iPad.
    private(set) var course: CourseRoute?
    /// The column a narrow iPad shows: the courses, or the course chosen.
    var compactColumn: NavigationSplitViewColumn = .sidebar
    /// Counts each time the open course's counts change, so the iPad's sidebar, which stays on
    /// screen, can show them too.
    private(set) var courseRevision = 0

    init(isSplit: Bool = false) {
        self.isSplit = isSplit
    }

    func open(_ route: some Hashable) {
        if isSplit, let course = route as? CourseRoute {
            select(course)
            return
        }
        path.append(route)
        if isSplit {
            compactColumn = .detail
        }
    }

    /// On iPad: shows the course beside the sidebar, from its own page.
    func select(_ course: CourseRoute) {
        self.course = course
        path = NavigationPath()
        compactColumn = .detail
    }

    /// Shows a course in place of what Home showed, and then its pages given: over the courses on
    /// iPhone, beside them on iPad.
    func show(_ course: CourseRoute, then pages: [CoursePage] = []) {
        var path = NavigationPath()
        if isSplit {
            self.course = course
            compactColumn = .detail
        } else {
            path.append(course)
        }
        for page in pages {
            path.append(page)
        }
        self.path = path
    }

    /// A course or topic she deleted from Home: on iPad, its screen beside the sidebar goes.
    func closeDeleted(courseID: String) {
        guard course?.id == courseID else { return }
        course = nil
        path = NavigationPath()
        compactColumn = .sidebar
    }

    /// Steps back one screen, or as many as asked, never past the root.
    func back(_ screens: Int = 1) {
        path.removeLast(min(screens, path.count))
    }

    /// The open course was read again with different counts.
    func courseChanged() {
        courseRevision += 1
    }
}

/// A screen of a course past the Course screen itself: the tiles' Review, Terms, and Exam.
enum StudyRoute: Hashable {
    case review(CourseRef)
    case terms(CourseRef)
    case exam(ExamSetupRoute)
    /// Exam twins she started from Exam setup.
    case twinJob(TwinJobRoute)
}

/// The course or topic a study screen belongs to, with what its subtitle says before anything loads.
nonisolated struct CourseRef: Hashable, CourseNaming {
    let id: String
    let code: String
    let title: String
    /// Picks the words of the screens it leads to: a topic's say topic.
    var kind: CourseKind = .course
}

/// The Exam setup screen, from the Exam tile with nothing ticked, or from an exam page's Start
/// exam button with that page's folders ticked.
struct ExamSetupRoute: Hashable {
    let course: CourseRef
    /// The folders ticked when it opens.
    var folderIDs: [String] = []
    /// The exam page those folders come from, named above the folder list.
    var examName: String?
}

/// A screen of a course under its page: an exam page or a folder, by id, so a rename keeps it open,
/// or what she deleted in it.
enum CoursePage: Hashable {
    case examPage(String)
    case folder(String)
    case recentlyDeleted
}
