import Foundation
import Testing
@testable import QBankKit

@Suite("Offline content cache")
struct ContentCacheTests {
    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("QBankKitTests-\(UUID().uuidString)", isDirectory: true)
    }

    static func caches() -> [(String, any ContentCache, URL?)] {
        let directory = temporaryDirectory()
        return [("file", FileContentCache(directory: directory), directory), ("memory", InMemoryContentCache(), nil)]
    }

    @Test func storesAndReadsRecordedContent() async throws {
        for (kind, cache, directory) in Self.caches() {
            defer { directory.map { try? FileManager.default.removeItem(at: $0) } }
            let semesters = try Fixture.load("semesters").decodeBody(SemestersResponse.self).semesters
            let course = try Fixture.load("course").decodeBody(CourseDetail.self)
            let set = try Fixture.load("practice-set").decodeBody(PracticeSet.self)
            let terms = try Fixture.load("terms").decodeBody(TermsResponse.self).terms
            let review = try Fixture.load("review").decodeBody(ReviewList.self)
            let savedAt = Date(timeIntervalSince1970: 1_790_000_000.25)

            #expect(try await cache.value(for: .semesters) == nil, "\(kind)")
            try await cache.store(semesters, for: .semesters, savedAt: savedAt)
            try await cache.store(course, for: .course(course.id), savedAt: savedAt)
            try await cache.store(set, for: .practiceSet(set.id), savedAt: savedAt)
            try await cache.store(terms, for: .terms(courseID: course.id), savedAt: savedAt)
            try await cache.store(review, for: .review(courseID: course.id), savedAt: savedAt)

            #expect(try await cache.value(for: .semesters) == Cached(value: semesters, savedAt: savedAt), "\(kind)")
            #expect(try await cache.value(for: .course(course.id)) == Cached(value: course, savedAt: savedAt), "\(kind)")
            #expect(try await cache.value(for: .practiceSet(set.id))?.value == set, "\(kind)")
            #expect(try await cache.value(for: .terms(courseID: course.id))?.value == terms, "\(kind)")
            #expect(try await cache.value(for: .review(courseID: course.id))?.value == review, "\(kind)")

            let entries = try await cache.entries()
            #expect(entries.count == 5, "\(kind)")
            #expect(entries.allSatisfy { $0.savedAt == savedAt && $0.byteCount > 0 }, "\(kind)")
            #expect(entries.map(\.name).contains("practice-set-\(set.id)"), "\(kind)")
        }
    }

    @Test func newerValueReplacesOlder() async throws {
        for (kind, cache, directory) in Self.caches() {
            defer { directory.map { try? FileManager.default.removeItem(at: $0) } }
            let key = CacheKey<[Term]>.terms(courseID: "c1")
            let old = Term(key: "a", term: "A", meaning: "Old", weekLabel: "Week 1", setTitle: "S")
            let new = Term(key: "a", term: "A", meaning: "New", weekLabel: "Week 1", setTitle: "S")
            try await cache.store([old], for: key, savedAt: Date(timeIntervalSince1970: 1))
            try await cache.store([new], for: key, savedAt: Date(timeIntervalSince1970: 2))
            #expect(try await cache.value(for: key) == Cached(value: [new], savedAt: Date(timeIntervalSince1970: 2)), "\(kind)")
            #expect(try await cache.entries().count == 1, "\(kind)")
        }
    }

    @Test func removeOneAndRemoveAll() async throws {
        for (kind, cache, directory) in Self.caches() {
            defer { directory.map { try? FileManager.default.removeItem(at: $0) } }
            let course = try Fixture.load("course").decodeBody(CourseDetail.self)
            try await cache.store(course, for: .course("c1"))
            try await cache.store(course, for: .course("c2"))
            try await cache.remove(.course("c1"))
            try await cache.remove(.course("not-there"))
            #expect(try await cache.value(for: .course("c1")) == nil, "\(kind)")
            #expect(try await cache.value(for: .course("c2")) != nil, "\(kind)")
            try await cache.removeAll()
            #expect(try await cache.entries().isEmpty, "\(kind)")
            try await cache.removeAll()
        }
    }

    @Test func fileCacheIgnoresAFileItCannotRead() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileContentCache(directory: directory)
        try await cache.store([Term](), for: .terms(courseID: "c1"))
        try Data("not json".utf8).write(to: directory.appendingPathComponent("terms-c1.json"))
        #expect(try await cache.value(for: .terms(courseID: "c1")) == nil)
        #expect(try await cache.entries().isEmpty)
    }

    @Test func fileCacheKeepsNamesInsideItsDirectory() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileContentCache(directory: directory)
        let key = CacheKey<[Term]>("../../escape/attempt")
        try await cache.store([], for: key)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == ["______escape_attempt.json"])
        #expect(try await cache.value(for: key)?.value == [])
        #expect(try await cache.entries().map(\.name) == ["../../escape/attempt"])
    }

    #if canImport(Darwin)
    @Test func fileCacheIsLeftOutOfBackups() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await FileContentCache(directory: directory).store([Term](), for: .terms(courseID: "c1"))
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
    #endif

    @Test func emptyDirectoryHasNoEntries() async throws {
        #expect(try await FileContentCache(directory: Self.temporaryDirectory()).entries().isEmpty)
    }
}
