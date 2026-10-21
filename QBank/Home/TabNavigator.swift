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

    /// Shows a folder of a course or topic in Home, on top of its page, in place of what Home showed.
    /// `name` titles the page until it loads.
    func openFolder(courseID: String, name: String?, folderID: String) {
        home.show(CourseRoute(id: courseID, name: name), then: [.folder(folderID)])
        tab = .home
    }

    /// Shows a course or topic in Home, in place of what Home showed.
    func openCourse(courseID: String, name: String?) {
        home.show(CourseRoute(id: courseID, name: name))
        tab = .home
    }
}
