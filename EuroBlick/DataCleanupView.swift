import SwiftUI

struct DataCleanupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TransactionViewModel
    
    @State private var isCleaningDuplicates = false
    @State private var isFixingIcons = false
    @State private var showDuplicateResult = false
    @State private var showIconResult = false
    @State private var duplicateResultMessage = ""
    @State private var iconResultMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.orange)
                    
                    Text("Daten bereinigen")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Beheben Sie Probleme mit doppelten Kontogruppen und korrigieren Sie Icons und Farben")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                VStack(spacing: 16) {
                    // Doppelte Kontogruppen bereinigen
                    CleanupActionCard(
                        icon: "folder.badge.minus",
                        title: "Doppelte Kontogruppen entfernen",
                        description: "Entfernt Kontogruppen mit identischen Namen und verschiebt alle Konten zur ursprünglichen Gruppe",
                        isProcessing: isCleaningDuplicates,
                        action: {
                            cleanupDuplicateGroups()
                        }
                    )
                    
                    // Icons und Farben korrigieren
                    CleanupActionCard(
                        icon: "paintbrush.pointed",
                        title: "Icons und Farben korrigieren",
                        description: "Korrigiert Icons und Farben der Konten basierend auf deren Namen und Kategorien",
                        isProcessing: isFixingIcons,
                        action: {
                            fixIconsAndColors()
                        }
                    )
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Bereinigung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Duplikat-Bereinigung", isPresented: $showDuplicateResult) {
            Button("OK") { }
        } message: {
            Text(duplicateResultMessage)
        }
        .alert("Icon-Korrektur", isPresented: $showIconResult) {
            Button("OK") { }
        } message: {
            Text(iconResultMessage)
        }
    }
    
    private func cleanupDuplicateGroups() {
        isCleaningDuplicates = true
        
        viewModel.removeDuplicateAccountGroups {
            DispatchQueue.main.async {
                isCleaningDuplicates = false
                duplicateResultMessage = "Die Bereinigung wurde erfolgreich abgeschlossen. Doppelte Kontogruppen wurden entfernt."
                showDuplicateResult = true
            }
        }
    }
    
    private func fixIconsAndColors() {
        isFixingIcons = true
        
        viewModel.fixAccountIconsAndColors {
            DispatchQueue.main.async {
                isFixingIcons = false
                iconResultMessage = "Icons und Farben wurden erfolgreich korrigiert."
                showIconResult = true
            }
        }
    }
}

struct CleanupActionCard: View {
    let icon: String
    let title: String
    let description: String
    let isProcessing: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.orange)
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            Button(action: action) {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Wird ausgeführt...")
                    } else {
                        Text("Bereinigen")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isProcessing ? Color.gray.opacity(0.3) : Color.orange)
                .foregroundColor(isProcessing ? .secondary : .white)
                .cornerRadius(8)
            }
            .disabled(isProcessing)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = TransactionViewModel(context: context)
    return DataCleanupView(viewModel: viewModel)
} 