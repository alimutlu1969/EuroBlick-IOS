import SwiftUI

struct ColorSchemeSheetView: View {
    @AppStorage("selectedColorScheme") private var selectedColorScheme: String = "system"
    @AppStorage("accentColor") private var accentColor: String = "orange"
    @Environment(\.presentationMode) var presentationMode
    
    let colorSchemes = [
        ("System", "system"),
        ("Hell", "light"),
        ("Dunkel", "dark")
    ]
    let accentColors: [(String, Color)] = [
        ("Orange", .orange),
        ("Blau", .blue),
        ("Grün", .green),
        ("Rot", .red),
        ("Lila", .purple)
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Farbschema")) {
                    ForEach(colorSchemes, id: \.1) { scheme in
                        let name = scheme.0
                        let value = scheme.1
                        HStack {
                            Text(name)
                            Spacer()
                            if selectedColorScheme == value {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedColorScheme = value
                        }
                    }
                }
                Section(header: Text("Akzentfarbe")) {
                    HStack(spacing: 16) {
                        ForEach(accentColors, id: \.0) { accent in
                            let name = accent.0
                            let color = accent.1
                            ZStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: accentColor == name.lowercased() ? 3 : 0)
                                    )
                                if accentColor == name.lowercased() {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .onTapGesture {
                                accentColor = name.lowercased()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Farbdesign")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
} 