import QBankDesign
import SwiftUI

/// A field's label above it, as `LabeledField` draws it, for fields that are not a text field.
struct FieldTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .qbankFont(.subheadline, weight: .semibold)
            .foregroundStyle(.qbank(.text2))
            .padding(.horizontal, QBankSpacing.space1)
            .accessibilityHidden(true)
    }
}

/// A hint under a field, as `LabeledField` draws it.
struct FieldHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .qbankFont(.subheadline)
            .foregroundStyle(.qbank(.text3))
            .padding(.horizontal, QBankSpacing.space1)
    }
}

/// A menu drawn as a field: what is picked, and the up-down chevron of an iOS pop-up button.
struct MenuField: View {
    let text: String

    var body: some View {
        HStack(spacing: QBankSpacing.space2) {
            Text(text)
                .qbankFont(.body)
                .foregroundStyle(.qbank(.text1))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.qbank(.text3))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, QBankSpacing.space4)
        .frame(minHeight: QBankButtonStyle.Size.large.minHeight)
        .background(.qbank(.surface), in: .rect(cornerRadius: QBankRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: QBankRadius.sm, style: .continuous)
                .strokeBorder(.qbank(.separatorStrong), lineWidth: QBankBorder.regular)
        }
        .contentShape(.rect)
    }
}

/// One choice among chips, such as a folder: tinted when picked. A small note, such as "new",
/// sits after the name.
struct PickChip: View {
    let title: String
    var note: String?
    var systemImage: String?
    let isOn: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .qbankFont(.subheadline, weight: isOn ? .semibold : .medium)
                if let note {
                    Text(note)
                        .qbankFont(.caption1)
                        .foregroundStyle(.qbank(isOn ? .tint : .text3))
                }
            }
            .foregroundStyle(.qbank(isOn ? .tint : .text1))
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background {
                Capsule().fill(.qbank(isOn ? .tintSoft : .surface))
            }
            .overlay {
                Capsule().strokeBorder(.qbank(isOn ? .tintSoftBorder : .separatorStrong), lineWidth: QBankBorder.regular)
            }
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

/// A button's words, or a spinner beside them while it works.
struct ButtonLabel: View {
    let text: String
    let isBusy: Bool

    var body: some View {
        HStack(spacing: QBankSpacing.space2) {
            if isBusy {
                ProgressView()
                    .tint(QBankColor(.textOnTint))
            }
            Text(text)
        }
    }
}

/// The round mark at the top of a finished screen: a check, or the arrow of a replaced set.
struct DoneMark: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.qbank(.correct))
            .frame(width: 64, height: 64)
            .background(.qbank(.correctSoft), in: .circle)
            .accessibilityHidden(true)
    }
}
