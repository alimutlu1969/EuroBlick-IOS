import SwiftUI

struct TypeButtonsView: View {
    @Binding var selectedType: String
    let einnahmeColorSelected: Color
    let ausgabeColorSelected: Color
    let umbuchungColorSelected: Color
    let defaultColor: Color
    
    private let buttonWidth: CGFloat = 100
    private let buttonHeight: CGFloat = 40
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach([
                (type: "einnahme", icon: "plus", title: "Einnahme", color: einnahmeColorSelected),
                (type: "ausgabe", icon: "minus", title: "Ausgabe", color: ausgabeColorSelected),
                (type: "umbuchung", icon: "arrow.triangle.2.circlepath.circle.fill", title: "Umbuchung", color: umbuchungColorSelected)
            ], id: \.type) { button in
                TransactionTypeButton(
                    type: button.type,
                    icon: button.icon,
                    title: button.title,
                    isSelected: selectedType == button.type,
                    color: button.color,
                    action: { selectedType = button.type }
                )
            }
        }
        .padding(8)
        .background(Color(white: 0.15))
        .cornerRadius(12)
    }
}

struct TransactionTypeButton: View {
    let type: String
    let icon: String
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(width: 100, height: 40)
            .background(isSelected ? color : Color.clear)
            .foregroundColor(isSelected ? .white : .gray)
            .cornerRadius(8)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }
}

#Preview {
    TypeButtonsView(
        selectedType: .constant("einnahme"),
        einnahmeColorSelected: Color(red: 0.0, green: 0.392, blue: 0.0),
        ausgabeColorSelected: Color(red: 1.0, green: 0.0, blue: 0.0),
        umbuchungColorSelected: Color(red: 0.118, green: 0.565, blue: 1.0),
        defaultColor: Color.gray
    )
    .padding()
    .background(Color.black)
}
