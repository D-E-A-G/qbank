import Observation
import SwiftUI

/// The tabs of a signed-in session.
enum AppTab: Hashable {
    case home
    case add
    case settings
}

/// Which tab is showing, and the Home tab's stack, so a screen in one tab can open a course's
/// folder in Home, as Import's "Open Unsorted" does.
@Observable
final class TabNavigator {
    var tab: AppTab = .home
    let home = HomeNavigator(isSplit: Device.isPad)

    /// Shows a folder of a course in Home, on top of the course page, in place of what Home showed.
    func openFolder(courseID: String, code: String?, folderID: String) {
        home.show(CourseRoute(id: courseID, code: code), then: [.folder(folderID)])
        tab = .home
    }

    /// Shows a course in Home, in place of what Home showed.
    func openCourse(courseID: String, code: String?) {
        home.show(CourseRoute(id: courseID, code: code))
        tab = .home
    }
}
