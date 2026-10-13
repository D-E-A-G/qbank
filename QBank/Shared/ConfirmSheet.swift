import QBankDesign
import SwiftUI

extension View {
    /// Asks before something that cannot be undone, as the web's ConfirmSheet asks: a sheet from
    /// the bottom with the question, what happens, the action, and a harmless way out, both always
    /// visible. Swiping it down is the same as the harmless way out.
    func confirmSheet(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        confirm: String,
        isDestructive: Bool = true,
        cancel: String = "Cancel",
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            ConfirmSheet(
                title: title,
                message: message,
                confirm: confirm,
                isDestructive: isDestructive,
                cancel: cancel,
                identifier: identifier
            ) { confirmed in
                isPresented.wrappedValue = false
                if confirmed { action() }
            }
        }
    }
}

private struct ConfirmSheet: View {
    let title: String
    let message: String
    let confirm: String
    let isDestructive: Bool
    let cancel: String
    let identifier: String
    let answer: (Bool) -> Void
    @State private var height: CGFloat = 280

    var body: some View {
        VStack(spacing: QBankSpacing.space3) {
            Text(title)
                .qbankFont(.headline)
                .foregroundStyle(.qbank(.text1))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("\(identifier).title")
            Text(message)
                .qbankFont(.subheadline)
                .foregroundStyle(.qbank(.text2))
                .multilineTextAlignment(.center)
                .padding(.bottom, QBankSpacing.space3)
            Button(confirm) { answer(true) }
                .buttonStyle(.qbank(isDestructive ? .destructive : .primary, size: .large, fullWidth: true))
                .accessibilityIdentifier("\(identifier).confirm")
            Button(cancel) { answer(false) }
                .buttonStyle(.qbank(.quiet, size: .large, fullWidth: true))
                .accessibilityIdentifier("\(identifier).cancel")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, QBankSpacing.gutterPhone)
        .padding(.top, 28)
        .padding(.bottom, QBankSpacing.space4)
        .frame(maxWidth: QBankLayout.contentMax)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationBackground(.qbank(.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
