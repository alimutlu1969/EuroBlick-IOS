import SwiftUI

struct Style {
    // Farben
    static let primaryBackground = Color.black
    static let secondaryBackground = Color.gray.opacity(0.2)
    static let textPrimary = Color.white
    static let textSecondary = Color.gray
    static let accent = Color.blue
    static let destructive = Color.red
    static let disabled = Color.gray

    // Schriftgrößen
    static let titleFont = Font.headline
    static let bodyFont = Font.body
    static let subheadlineFont = Font.subheadline
    static let captionFont = Font.caption

    // Abstände
    static let standardPadding: CGFloat = 16
    static let smallPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 10
}

extension View {
    func customTextFieldStyle() -> some View {
        self
            .foregroundColor(Style.textPrimary)
            .padding(Style.standardPadding)
            .background(Style.secondaryBackground)
            .cornerRadius(Style.cornerRadius)
            .font(Style.bodyFont)
    }

    func customButtonStyle(isEnabled: Bool = true) -> some View {
        self
            .foregroundColor(Style.textPrimary)
            .padding(Style.standardPadding)
            .frame(maxWidth: .infinity)
            .background(isEnabled ? Style.accent : Style.disabled)
            .cornerRadius(Style.cornerRadius)
            .font(Style.bodyFont)
    }

    func customPickerStyle() -> some View {
        self
            .foregroundColor(Style.textPrimary)
            .padding(Style.standardPadding)
            .background(Style.secondaryBackground)
            .cornerRadius(Style.cornerRadius)
            .font(Style.bodyFont)
    }
}
