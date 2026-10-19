import Foundation
import QBankDesign
import QBankKit
import Testing
@testable import QBank

/// Color in Settings: the account's color scheme, Dusk or Slate, saved to the account.
@MainActor
struct PaletteTests {
    @Test func theScreensFollowTheAccountsScheme() {
        let (dusk, _) = TestApp.make(StubServer(), account: .student())
        #expect(dusk.palette == .dusk)
        let (slate, _) = TestApp.make(StubServer(), account: .student(palette: .slate))
        #expect(slate.palette == .slate)
        let (signedOut, _) = TestApp.make(StubServer())
        #expect(signedOut.palette == .dusk)
    }

    @Test func eachSchemeDrawsInItsOwnPalette() {
        #expect(Account.Palette.dusk.design == .dusk)
        #expect(Account.Palette.slate.design == .slate)
        #expect(Account.Palette.allCases.map(\.label) == ["Dusk", "Slate"])
    }

    @Test func aPickShowsAtOnceAndIsSavedToTheAccount() async throws {
        let server = StubServer(["PUT /api/me/palette": .ok(Bodies.account(palette: "slate"))])
        server.hold("PUT /api/me/palette")
        let (app, store) = TestApp.make(server, account: .student())
        let saving = Task { await app.pickPalette(.slate) }
        try await waitUntil { server.calls == ["PUT /api/me/palette"] }
        #expect(app.palette == .slate)
        #expect(app.account?.palette == .dusk)
        server.release("PUT /api/me/palette")
        await saving.value
        #expect(app.palette == .slate)
        #expect(app.account?.palette == .slate)
        #expect(app.route == .signedIn(.student(palette: .slate)))
        #expect(app.paletteProblem == nil)
        // The next launch opens in Slate before it asks the server.
        #expect(try store.load()?.account?.palette == .slate)
        let body = try #require(server.requests.last?.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == #"{"palette":"slate"}"#)
    }

    @Test func pickingTheSchemeShownSendsNothing() async {
        let server = StubServer()
        let (app, _) = TestApp.make(server, account: .student())
        await app.pickPalette(.dusk)
        #expect(server.requests.isEmpty)
    }

    @Test func withoutSignalThePickGoesBackAndSaysWhy() async {
        let server = StubServer(["PUT /api/me/palette": .offline])
        let (app, _) = TestApp.make(server, account: .student())
        await app.pickPalette(.slate)
        #expect(app.palette == .dusk)
        #expect(app.paletteProblem == "No connection. Check Wi-Fi or cellular data and try again.")
        #expect(app.route == .signedIn(.student()))
    }

    @Test func aRefusedPickSaysTheServersWords() async {
        let server = StubServer(["PUT /api/me/palette": .error(400, "invalid_request", "Check the fields and try again.")])
        let (app, _) = TestApp.make(server, account: .student())
        await app.pickPalette(.slate)
        #expect(app.palette == .dusk)
        #expect(app.paletteProblem == "Check the fields and try again.")
    }

    @Test func theNextPickClearsTheProblem() async {
        let server = StubServer()
        server.script("PUT /api/me/palette", [.offline, .ok(Bodies.account(palette: "slate"))])
        let (app, _) = TestApp.make(server, account: .student())
        await app.pickPalette(.slate)
        #expect(app.paletteProblem != nil)
        await app.pickPalette(.slate)
        #expect(app.paletteProblem == nil)
        #expect(app.palette == .slate)
    }

    @Test func anEndedSessionSignsOutToDusk() async {
        let server = StubServer(["PUT /api/me/palette": .error(401, "unauthenticated", "Sign in to continue.")])
        let (app, _) = TestApp.make(server, account: .student())
        await app.pickPalette(.slate)
        #expect(app.route == .signedOut)
        #expect(app.palette == .dusk)
        #expect(app.paletteProblem == nil)
    }

    @Test func theLatestPickWinsWhenAnswersCrossEachOther() async throws {
        let server = StubServer()
        server.script("PUT /api/me/palette", [.ok(Bodies.account(palette: "slate")), .ok(Bodies.account(palette: "dusk"))])
        server.hold("PUT /api/me/palette")
        let (app, _) = TestApp.make(server, account: .student())
        let first = Task { await app.pickPalette(.slate) }
        try await waitUntil { server.calls.count == 1 }
        await app.pickPalette(.dusk)
        #expect(app.palette == .dusk)
        server.release("PUT /api/me/palette")
        await first.value
        #expect(app.palette == .dusk)
        #expect(app.account?.palette == .dusk)
    }

    @Test func aPickOnAnotherDeviceArrivesWithTheSessionCheck() async {
        let server = StubServer(["GET /api/session": .ok(Bodies.session(palette: "slate"))])
        let (app, _) = TestApp.make(server, account: .student())
        await app.refreshSession()
        #expect(app.palette == .slate)
    }

    @Test func signingOutGoesBackToDusk() async {
        let server = StubServer(["POST /api/sign-out": .ok(#"{"status":"ok"}"#)])
        let (app, _) = TestApp.make(server, account: .student(palette: .slate))
        await app.signOut()
        #expect(app.palette == .dusk)
    }
}
