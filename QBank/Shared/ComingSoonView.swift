import QBankDesign
import SwiftUI

/// Where a tap leads before its screen is built: an exam, Review, and Terms arrive in the next
/// slice of phase 1.
enum ComingSoonRoute: Hashable {
    case exam
    case review
    case terms

    var title: String {
        switch self {
        case .exam: "Exam"
        case .review: "Review"
        case .terms: "Terms"
        }
    }

    var message: String {
        switch self {
        case .exam: "Exams come in a later update of the app. Until then, take them on the web."
        case .review: "Review comes in a later update of the app. Until then, find it on the web."
        case .terms: "Terms come in a later update of the app. Until then, find them on the web."
        }
    }
}

/// An exam starts and ends on the server, so without a connection the Exam screen says so first.
struct ComingSoonView: View {
    let route: ComingSoonRoute
    var connection: Connection?

    var body: some View {
        VStack(spacing: QBankSpacing.space4) {
            Image(systemName: "hammer")
                .font(.largeTitle)
                .foregroundStyle(.qbank(.text3))
                .accessibilityHidden(true)
            Text(route.message)
                .qbankFont(.body)
                .foregroundStyle(.qbank(.text2))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("comingSoon.message")
        }
        .padding(.horizontal, QBankSpacing.space7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if route == .exam, connection?.isOnline == false {
                OfflineBanner.examsNeedConnection
                    .padding(.horizontal, QBankSpacing.gutterPhone)
                    .padding(.top, QBankSpacing.space3)
                    .accessibilityIdentifier("exam.needsConnection")
            }
        }
        .qbankScreenBackground()
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
