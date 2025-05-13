import SwiftUI

struct TypeButtonsView: View {
    @Binding var selectedType: String
    let einnahmeColorSelected: Color
    let ausgabeColorSelected: Color
    let umbuchungColorSelected: Color
    let defaultColor: Color

    var body: some View {
        HStack(spacing: 10) {
            // Einnahme-Button (Grün)
            Button(action: {
                selectedType = "einnahme"
            }) {
                VStack {
                    Image(systemName: "arrow.up.circle")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.white)
                    Text("Einnahme")
                        .foregroundColor(.white)
                        .font(.system(size: 10)) // Schriftgröße auf 9 gesetzt
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(selectedType == "einnahme" ? einnahmeColorSelected : defaultColor.opacity(0.6))
                .cornerRadius(10)
            }

            // Ausgabe-Button (Rot)
            Button(action: {
                selectedType = "ausgabe"
            }) {
                VStack {
                    Image(systemName: "arrow.down.circle")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.white)
                    Text("Ausgabe")
                        .foregroundColor(.white)
                        .font(.system(size: 10)) // Schriftgröße auf 9 gesetzt
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(selectedType == "ausgabe" ? ausgabeColorSelected : defaultColor.opacity(0.6))
                .cornerRadius(10)
            }

            // Umbuchung-Button (Blau)
            Button(action: {
                selectedType = "umbuchung"
            }) {
                VStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.white)
                    Text("Umbuchung")
                        .foregroundColor(.white)
                        .font(.system(size: 10)) // Schriftgröße auf 9 gesetzt
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(selectedType == "umbuchung" ? umbuchungColorSelected : defaultColor.opacity(0.6))
                .cornerRadius(10)
            }
        }
    }
}
