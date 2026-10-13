import Testing
@testable import QBank

@MainActor
struct AppModelTests {
    @Test func freshModelStartsOnWelcome() {
        #expect(AppModel().route == .welcome)
    }
}
