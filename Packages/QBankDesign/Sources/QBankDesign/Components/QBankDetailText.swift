import SwiftUI

/// A line of parts joined by " · ", such as "2 sets · 9 of 26 answered": on one line when it
/// fits, otherwise one part per line, so no line ends on a separator. The font and color come
/// from the caller; VoiceOver reads the text as written.
public struct QBankDetailText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .lineLimit(1)
            Text(text.replacingOccurrences(of: " · ", with: "\n"))
                .accessibilityLabel(text)
        }
    }
}
