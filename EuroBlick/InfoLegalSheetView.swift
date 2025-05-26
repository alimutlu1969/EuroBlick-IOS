import SwiftUI

struct InfoLegalSheetView: View {
    @Environment(\.presentationMode) var presentationMode
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("EuroBlick")
                        .font(.largeTitle)
                        .bold()
                    Text("Version 1.0.0")
                        .foregroundColor(.secondary)
                    Divider()
                    Text("Impressum")
                        .font(.headline)
                    Text("Ali Mutlu\nMusterstraße 1\n12345 Musterstadt\nE-Mail: ali.mutlu@me.com")
                    Divider()
                    Text("Datenschutz")
                        .font(.headline)
                    Text("Ihre Daten werden ausschließlich lokal auf Ihrem Gerät gespeichert. Es erfolgt keine Weitergabe an Dritte.")
                    Divider()
                    Text("Rechtliche Hinweise")
                        .font(.headline)
                    Text("Diese App dient der privaten Finanzverwaltung. Keine Haftung für Fehler oder Datenverlust.")
                }
                .padding()
            }
            .navigationTitle("Info / Rechtliches")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
} 