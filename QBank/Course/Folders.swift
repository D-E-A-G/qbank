import QBankDesign
import QBankKit
import SwiftUI

/// A week on the course page as a folder, as the web's `WeekFolder` draws it: closed, one row with
/// the week, its sets and how far she is, with a thin bar while it is in progress and Done, "22 of
/// 27", or Not started at the right. Open, it holds its set rows and its exam line, lined up with
/// the week name.
struct WeekFolder<Content: View>: View {
    let week: Week
    @Binding var isOpen: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let progress = WeekProgress(week)
        FolderCard {
            FolderHead(
                title: week.label,
                meta: FolderWording.weekMeta(week, progress),
                progress: progress,
                state: FolderWording.state(progress),
                isOpen: $isOpen
            )
            .accessibilityIdentifier("course.week.\(week.label)")
            if isOpen {
                VStack(spacing: 0) {
                    Group(subviews: content) { rows in
                        ForEach(rows) { row in
                            row.overlay(alignment: .top) {
                                if row.id != rows.first?.id {
                                    Hairline().padding(.leading, FolderMetrics.inset)
                                }
                            }
                        }
                    }
                }
                .overlay(alignment: .top) { Hairline() }
                .transition(.opacity)
            }
        }
    }
}

/// An exam of the course as a folder: its name, its weeks, sets and questions and how many exams
/// she took over them, and how far she is. Open, it holds its weeks as folders, her exams over
/// them, and a Start button.
struct ExamFolderView<Content: View>: View {
    let folder: ExamFolder
    @Binding var isOpen: Bool
    @ViewBuilder let content: Content

    var body: some View {
        FolderCard {
            FolderHead(
                title: folder.exam.name,
                meta: FolderWording.examMeta(folder),
                progress: folder.progress,
                state: FolderWording.state(folder.progress),
                isOpen: $isOpen
            )
            .accessibilityIdentifier("course.exam.\(folder.exam.name)")
            if isOpen {
                // Its weeks sit as cards in a well, as the approved by-exam view draws them.
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .padding(QBankSpacing.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.qbank(.bg))
                .overlay(alignment: .top) { Hairline() }
                .transition(.opacity)
            }
        }
    }
}

/// The card around a folder, the course card's surface.
private struct FolderCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .clipShape(RoundedRectangle(cornerRadius: QBankRadius.md, style: .continuous))
            .qbankCardBackground()
    }
}

/// A folder's measures, as the web's `.folder-head` sets them.
enum FolderMetrics {
    static let leading: CGFloat = 14
    static let chevronWidth: CGFloat = 18
    static let gap: CGFloat = 10
    /// Where an open folder's rows start, under the folder's name: the padding, the chevron, the gap.
    static let inset: CGFloat = leading + chevronWidth + gap
}

/// The row that opens and closes a folder.
private struct FolderHead: View {
    let title: String
    let meta: String
    let progress: WeekProgress
    let state: String
    @Binding var isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : QBankMotion.reveal) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: FolderMetrics.gap) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.qbank(.text3))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: FolderMetrics.chevronWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .qbankFont(.headline)
                        .foregroundStyle(.qbank(.text1))
                        .multilineTextAlignment(.leading)
                    Text(meta)
                        .qbankFont(.footnote)
                        .foregroundStyle(.qbank(.text2))
                        .multilineTextAlignment(.leading)
                    if progress.state == .started {
                        QBankProgressBar(value: progress.fraction, height: 4, accessibilityTitle: "Answered")
                            .frame(maxWidth: 320)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !state.isEmpty {
                    Text(state)
                        .qbankFont(.footnote, weight: progress.state == .fresh ? .medium : .semibold)
                        .monospacedDigit()
                        .foregroundStyle(.qbank(stateColor))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.leading, FolderMetrics.leading)
            .padding(.trailing, QBankSpacing.space4)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.qbankRow)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityHint(isOpen ? "Closes the folder" : "Opens the folder")
        .accessibilityAddTraits(.isHeader)
    }

    private var stateColor: QBankColorToken {
        switch progress.state {
        case .done: .correct
        case .fresh: .text3
        case .started: .text1
        }
    }
}

/// A hairline across a folder.
private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(.qbank(.separator))
            .frame(height: QBankBorder.hairline)
    }
}
