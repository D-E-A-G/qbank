import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("QBank")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("welcome.title")
            Text("NCLEX practice questions, on your iPhone.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WelcomeView()
}
