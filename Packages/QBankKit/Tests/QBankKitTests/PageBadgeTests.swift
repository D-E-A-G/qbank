import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import QBankKit

/// A page's badge: what it is for, Exam, Concept or Study, or none. The server sends it as `badge`
/// on every page and takes it on the page's update; a page from a server before badges has none.
@Suite("Page badges")
struct PageBadgeTests {
    static func page(badge: JSONValue?) throws -> Data {
        var object: [String: JSONValue] = [
            "id": .string("ce000000-0000-4000-8000-000000000001"),
            "name": .string("Exam 1"),
            "sortOrder": .number(1),
            "weekLabels": .array([]),
            "folderIds": .array([]),
        ]
        if let badge { object["badge"] = badge }
        return try JSONEncoder().encode(JSONValue.object(object))
    }

    @Test func aPageFromBeforeBadgesHasNone() throws {
        let page = try QBankJSON.decoder.decode(CourseExam.self, from: Self.page(badge: nil))
        #expect(page.badge == nil)
        #expect(!page.takesBadge, "a server before badges would drop one")
        let course = try Fixture.load("course-with-exams").decodeBody(CourseDetail.self)
        #expect(!course.exams.isEmpty)
        #expect(course.exams.allSatisfy { $0.badge == nil })
    }

    @Test func eachBadgeDecodesAndNullOrOneThisVersionDoesNotKnowIsNone() throws {
        for badge in PageBadge.allCases {
            let page = try QBankJSON.decoder.decode(CourseExam.self, from: Self.page(badge: .string(badge.rawValue)))
            #expect(page.badge == badge)
        }
        let none = try QBankJSON.decoder.decode(CourseExam.self, from: Self.page(badge: .null))
        #expect(none.badge == nil)
        #expect(none.takesBadge, "null is no badge from a server that takes one")
        #expect(try QBankJSON.decoder.decode(CourseExam.self, from: Self.page(badge: .string("revision"))).badge == nil)
    }

    @Test func aSavedCopyKeepsItsBadgeAndWhetherTheServerTakesOne() throws {
        for page in [
            CourseExam(id: "x1", name: "Exam 1", sortOrder: 1, weekLabels: [], badge: .concept),
            CourseExam(id: "x1", name: "Exam 1", sortOrder: 1, weekLabels: [], badge: nil),
            CourseExam(id: "x1", name: "Exam 1", sortOrder: 1, weekLabels: [], linkURL: "https://primer.invalid", takesBadge: false),
        ] {
            let saved = try QBankJSON.encoder.encode(page)
            #expect(try QBankJSON.decoder.decode(CourseExam.self, from: saved) == page)
        }
    }

    @Test func theUpdateSendsTheBadgeOnlyWhenAskedAndCreateNever() async throws {
        let body = try Self.page(badge: .string("study"))
        let transport = FixtureTransport(bodies: [body, body, body, body])
        let (client, _) = TestClient.make(transport)
        let id = "ce000000-0000-4000-8000-000000000001"
        let set = try await client.updateCourseExam(id: id, name: "Exam 1", folderIDs: [], badge: .study)
        _ = try await client.updateCourseExam(id: id, name: "Exam 1", folderIDs: [], badge: .some(nil))
        _ = try await client.updateCourseExam(id: id, name: "Exam 1", folderIDs: [])
        _ = try await client.createCourseExam(courseID: "c1", name: "Page 1", folderIDs: [])
        let sent = try transport.requests.map { try JSONDecoder().decode(JSONValue.self, from: #require($0.httpBody)) }
        #expect(transport.requests.map(\.httpMethod) == ["PUT", "PUT", "PUT", "POST"])
        #expect(sent[0]["badge"] == .string("study"))
        #expect(sent[1]["badge"]?.isNull == true, "null takes it off")
        #expect(sent[2]["badge"] == nil, "left out, the page keeps its badge")
        #expect(sent[3]["badge"] == nil, "a new page has no badge")
        #expect(set.badge == .study)
    }
}
