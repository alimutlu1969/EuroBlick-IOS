import SwiftUI

struct CustomTextField: View {
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.gray.opacity(0.8)) // Helleres Grau, Richtung Weiß
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            
            Group {
                if isSecure {
                    SecureField("", text: $text)
                        .foregroundColor(.white) // Textfarbe auf Weiß
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .onChange(of: text) { _, newValue in
                            print("CustomTextField (\(placeholder)) aktualisiert: '\(newValue)'")
                        }
                } else {
                    TextField("", text: $text)
                        .foregroundColor(.white) // Textfarbe auf Weiß
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .onChange(of: text) { _, newValue in
                            print("CustomTextField (\(placeholder)) aktualisiert: '\(newValue)'")
                        }
                }
            }
        }
    }
}

#Preview {
    CustomTextField(text: .constant(""), placeholder: "Platzhalter", isSecure: false)
}
