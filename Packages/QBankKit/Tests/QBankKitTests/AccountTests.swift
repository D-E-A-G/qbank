import Foundation
import Testing
@testable import QBankKit

@Suite("Account: color scheme")
struct AccountPaletteTests {
    private func account(palette: String?) throws -> Account {
        let field = palette.map { #","palette":"\#($0)""# } ?? ""
        let json = #"{"id":"a1","email":"student@example.com","name":"Sam Student","role":"student","mustChangePassword":false\#(field)}"#
        return try QBankJSON.decoder.decode(Account.self, from: Data(json.utf8))
    }

    @Test(arguments: [("dusk", Account.Palette.dusk), ("slate", .slate)])
    func knownPalettes(raw: String, palette: Account.Palette) throws {
        #expect(try account(palette: raw).palette == palette)
    }

    @Test("A server from before color schemes says nothing, which is Dusk")
    func absentIsDusk() throws {
        #expect(try account(palette: nil).palette == .dusk)
    }

    @Test("A scheme this version does not know shows as Dusk, as the server asks", arguments: ["fjord", "SLATE", ""])
    func unknownIsDusk(raw: String) throws {
        #expect(try account(palette: raw).palette == .dusk)
    }

    @Test("A null palette is Dusk too")
    func nullIsDusk() throws {
        let json = #"{"id":"a1","email":"student@example.com","name":"Sam Student","role":"student","mustChangePassword":false,"palette":null}"#
        #expect(try QBankJSON.decoder.decode(Account.self, from: Data(json.utf8)).palette == .dusk)
    }

    @Test("The session kept on the device keeps the scheme, and one kept before schemes reads as Dusk")
    func storedSession() throws {
        let slate = StoredSession(token: "t", account: Account(id: "a1", email: "e", name: "n", role: .student, mustChangePassword: false, palette: .slate))
        let data = try QBankJSON.encoder.encode(slate)
        #expect(try QBankJSON.decoder.decode(StoredSession.self, from: data) == slate)

        let older = #"{"token":"t","account":{"id":"a1","email":"e","name":"n","role":"student","mustChangePassword":false}}"#
        #expect(try QBankJSON.decoder.decode(StoredSession.self, from: Data(older.utf8)).account?.palette == .dusk)
    }

    @Test("The schemes an account can pick are the server's")
    func choices() {
        #expect(Account.Palette.allCases.map(\.rawValue) == ["dusk", "slate"])
    }
}
