#if canImport(SwiftUI)
import SwiftUI

/// The iOS inset-grouped list, drawn as a card: an uppercase mono header, rows
/// with hairline separators inset 16pt from the left, and a footnote below.
/// Used for week groups on Course, Review, Settings and Exam setup. Works inside
/// a `ScrollView` next to cards, unlike a `List`.
public struct QBankListGroup<Content: View>: View {
    private let header: String?
    private let footer: String?
    private let content: Content

    public init(header: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                QBankSectionHeader(header)
                    .padding(.horizontal, QBankSpacing.space5)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                            .overlay(alignment: .bottom) {
                                if index < rows.count - 1 {
                                    Rectangle()
                                        .fill(.qbank(.separator))
                                        .frame(height: QBankBorder.hairline)
                                        .padding(.leading, QBankSpacing.space5)
                                }
                            }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: QBankRadius.md, style: .continuous))
            .qbankCardBackground()
            if let footer {
                Text(footer)
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text3))
                    .padding(.horizontal, QBankSpacing.space5)
            }
        }
    }
}

/// A small uppercase section label ("SEMESTER 1", "WEEK 2").
public struct QBankSectionHeader: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title.uppercased())
            .qbankFont(.footnote, weight: .semibold)
            .tracking(QBankTextStyle.footnote.size * QBankTextStyle.capsTrackingEm)
            .foregroundStyle(.qbank(.text3))
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)
    }
}

/// One row of a ``QBankListGroup``: an optional icon, a title with an optional
/// detail line, a trailing value or custom accessory, and an optional chevron.
/// For a tappable row, wrap it in a `Button` with `.buttonStyle(.qbankRow)`.
public struct QBankListRow<Accessory: View>: View {
    private let title: String
    private let detail: String?
    private let value: String?
    private let systemImage: String?
    private let showsChevron: Bool
    private let isDestructive: Bool
    private let isSelected: Bool
    private let accessory: Accessory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        _ title: String,
        detail: String? = nil,
        value: String? = nil,
        systemImage: String? = nil,
        showsChevron: Bool = false,
        isDestructive: Bool = false,
        isSelected: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.value = value
        self.systemImage = systemImage
        self.showsChevron = showsChevron
        self.isDestructive = isDestructive
        self.isSelected = isSelected
        self.accessory = accessory()
    }

    public var body: some View {
        // At accessibility text sizes the value and accessory move under the title,
        // so long titles keep the row's width.
        let content = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: QBankSpacing.space3))
            : AnyLayout(HStackLayout(spacing: QBankSpacing.space4))
        HStack(spacing: QBankSpacing.space4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3) // 20pt at the default size, and scales
                    .foregroundStyle(.qbank(isDestructive ? .wrong : .tint))
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            content {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .qbankFont(.body)
                        .foregroundStyle(.qbank(isDestructive ? .wrong : .text1))
                    if let detail {
                        Text(detail)
                            .qbankFont(.footnote)
                            .foregroundStyle(.qbank(.text3))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value)
                        .qbankFont(.body)
                        .foregroundStyle(.qbank(.text3))
                }
                accessory
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.qbank(.text4))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
        .padding(.vertical, 11)
        .frame(minHeight: QBankSpacing.rowMin)
        .background(isSelected ? AnyShapeStyle(.qbank(.tintSoft)) : AnyShapeStyle(.clear))
        .contentShape(Rectangle())
        // A row reads as one element, unless its accessory holds its own controls.
        .accessibilityElement(children: Accessory.self == EmptyView.self ? .combine : .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension QBankListRow where Accessory == EmptyView {
    public init(
        _ title: String,
        detail: String? = nil,
        value: String? = nil,
        systemImage: String? = nil,
        showsChevron: Bool = false,
        isDestructive: Bool = false,
        isSelected: Bool = false
    ) {
        self.init(
            title,
            detail: detail,
            value: value,
            systemImage: systemImage,
            showsChevron: showsChevron,
            isDestructive: isDestructive,
            isSelected: isSelected
        ) { EmptyView() }
    }
}

/// A list row as one button: the row darkens to `surfacePressed` while pressed.
public struct QBankRowButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AnyShapeStyle(.qbank(.surfacePressed)) : AnyShapeStyle(.clear))
            .animation(QBankMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QBankRowButtonStyle {
    public static var qbankRow: QBankRowButtonStyle { QBankRowButtonStyle() }
}

#Preview("List group") {
    ScrollView {
        VStack(spacing: QBankSpacing.gapSection) {
            QBankListGroup(header: "Week 2") {
                Button {} label: {
                    QBankListRow(
                        "Therapeutic Communication and the Relationship",
                        detail: "9 of 14 answered",
                        showsChevron: true
                    )
                }
                .buttonStyle(.qbankRow)
                QBankListRow("Psychosocial Assessment and Safety Screening", detail: "Replaced Oct 6 · 12 questions") {
                    Button {} label: { Label("Restore", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.qbank(.secondary, size: .small))
                }
            }
            QBankListGroup(header: "Account", footer: "Passkeys use Face ID or Touch ID.") {
                QBankListRow("Passkeys", value: "2", systemImage: "key", showsChevron: true)
                QBankListRow("Sign out", systemImage: "rectangle.portrait.and.arrow.right", isDestructive: true)
            }
        }
        .padding(QBankSpacing.gutterPhone)
    }
    .qbankScreenBackground()
}
#endif
