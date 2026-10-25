import Foundation
import Observation
import QBankKit
import SwiftUI

/// The tabs of a signed-in session.
enum AppTab: Hashable {
    case home
    case add
    case settings
}

/// Make questions, asked for from a course's +: the Add tab opens Your material with that course
/// picked. `status` is what the course page read from the server.
struct MakeRequest: Equatable {
    let id = UUID()
    let courseID: String
    let status: QuestionMakerStatus?
}

/// Which tab is showing, and the Home tab's stack, so a screen in one tab can open a course's
/// folder in Home, as Import's "Open Unsorted" does, or a course can make questions in Add.
@Observable
final class TabNavigator {
    var tab: AppTab = .home
    let home = HomeNavigator(isSplit: Device.isPad)
    /// Make questions a course asked for, until the Add tab takes it.
    var makeRequest: MakeRequest?

    /// Opens Make questions on the Add tab, at Your material, with the course picked. Its steps
    /// take the whole screen there, and the set shows under In progress.
    func makeQuestions(courseID: String, status: QuestionMakerStatus?) {
        makeRequest = MakeRequest(courseID: courseID, status: status)
        tab = .add
    }

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
