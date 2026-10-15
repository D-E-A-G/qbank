import Foundation
import Observation
import QBankDesign
import QBankKit
import SwiftUI

/// The course's terms, A to Z, each with the week and set that defined it, as the web lists them
/// (`apps/web/src/screens/TermsScreen.tsx`), plus a search field. Without a connection, the copy
/// saved last.
@Observable
final class TermsModel {
    let course: CourseRef
    private(set) var terms: [Term]?
    /// When the terms on screen were saved on the phone, or nil when they came from QBank just now.
    private(set) var savedAt: Date?
    private(set) var problem: String?
    var query = ""

    private let app: AppModel

    init(app: AppModel, course: CourseRef) {
        self.app = app
        self.course = course
    }

    /// The terms whose name or meaning holds the query, ignoring case and accents.
    var shown: [Term] {
        Self.matching(terms ?? [], query)
    }

    func load() async {
        let id = course.id
        do {
            let loaded = try await app.load(.terms(courseID: id)) { () async throws(QBankError) in try await app.client.terms(courseID: id) }
            terms = loaded.value
            savedAt = loaded.savedAt
            problem = nil
        } catch {
            guard !app.handle(error), let words = Wording.problem(error) else { return }
            problem = words
        }
    }

    nonisolated static func matching(_ terms: [Term], _ query: String) -> [Term] {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return terms }
        return terms.filter { term in
            words.allSatisfy { word in
                term.term.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || term.meaning.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}

struct TermsView: View {
    let app: AppModel
    @State private var model: TermsModel

    init(app: AppModel, course: CourseRef) {
        self.app = app
        _model = State(initialValue: TermsModel(app: app, course: course))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                Text("When a term is defined in more than one set, the newest set’s definition is the one shown here.")
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
                if model.savedAt != nil {
                    OfflineBanner.showingSaved(phoneIsOnline: app.connection.isOnline)
                        .accessibilityIdentifier("terms.offline")
                }
                if let problem = model.problem {
                    ProblemText(text: problem)
                }
                content
            }
            .padding(.horizontal, QBankSpacing.gutterPhone)
            .padding(.bottom, QBankSpacing.space7)
        }
        .qbankScreenBackground()
        .navigationTitle("Terms")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search terms")
        .refreshable { await model.load() }
        .reloadsWithConnection(app) { await model.load() }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if let terms = model.terms {
            if terms.isEmpty {
                EmptyCard(message: "Terms appear here after a file that defines them is imported.", systemImage: "book.closed")
            } else if model.shown.isEmpty {
                EmptyCard(message: "No term matches “\(model.query.trimmingCharacters(in: .whitespaces))”.", systemImage: "magnifyingglass")
            } else {
                QBankListGroup {
                    ForEach(model.shown) { term in
                        TermRow(term: term)
                    }
                }
            }
        } else if model.problem == nil {
            Loading(title: "Loading terms")
        }
    }
}

private struct TermRow: View {
    let term: Term

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term.term)
                .qbankFont(.headline)
                .foregroundStyle(.qbank(.text1))
            Text(term.meaning)
                .qbankFont(.subheadline)
                .foregroundStyle(.qbank(.text2))
            Text("\(term.folderName) · \(term.setTitle)")
                .qbankFont(.subheadline)
                .foregroundStyle(.qbank(.text2))
        }
        .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
        .padding(.vertical, QBankSpacing.rowPaddingVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("terms.term.\(term.term)")
    }
}
