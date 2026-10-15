import QBankDesign
import SwiftUI

extension Device {
    /// A screen's side margin: the phone's on iPhone, the tablet's on iPad.
    static var gutter: CGFloat {
        isPad ? QBankSpacing.gutterTablet : QBankSpacing.gutterPhone
    }
}

extension View {
    /// A scrolling screen's content: the phone's side margins on iPhone, and on iPad the tablet's
    /// margins around a centered column of reading width, so lines and lists stay short however
    /// wide the iPad is.
    func screenColumn() -> some View {
        modifier(ScreenColumn())
    }

    /// The title of a screen with a `screenColumn()`: as before on iPhone, and on iPad inline,
    /// centered over the centered column, as iPad's own Settings titles its pages. A large title
    /// would sit at the screen's edge, away from the column.
    func screenColumnTitle() -> some View {
        navigationBarTitleDisplayMode(Device.isPad ? .inline : .automatic)
    }
}

private struct ScreenColumn: ViewModifier {
    func body(content: Content) -> some View {
        if Device.isPad {
            content
                .frame(maxWidth: QBankLayout.contentMax, alignment: .leading)
                .padding(.horizontal, QBankSpacing.gutterTablet)
                .frame(maxWidth: .infinity)
        } else {
            content
                .padding(.horizontal, QBankSpacing.gutterPhone)
        }
    }
}

extension QBankTextStyle {
    /// A question's stem: larger on iPad, as on the web's wide screens.
    static var stem: QBankTextStyle {
        Device.isPad ? .readingLarge : .reading
    }
}
