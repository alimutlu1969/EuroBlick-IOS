import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var managedObjectContext
    @ObservedObject var viewModel: TransactionViewModel
    let group: AccountGroup
    
    @State private var accountName = ""
    @State private var selectedIcon = "banknote.fill"
    @State private var selectedColor = Color.blue
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isViewReady = false
    @State private var isProcessing = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if !isViewReady {
                    ProgressView("Lade...")
                        .foregroundColor(.white)
                } else {
                    VStack(spacing: 20) {
                        // Gruppen-Header
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text("Gruppe: \(group.name ?? "")")
                                .foregroundColor(.white)
                        }
                        .font(.system(size: AppFontSize.bodyLarge))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        
                        // Konto-Name Eingabe
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kontoname")
                                .foregroundColor(.white)
                                .font(.system(size: AppFontSize.bodyMedium))
                            TextField("", text: $accountName)
                                .foregroundColor(.black)
                                .font(.system(size: AppFontSize.bodyLarge))
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                                        )
                                )
                        }
                        
                        // Icon Auswahl
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Icon")
                                .foregroundColor(.white)
                                .font(.system(size: AppFontSize.bodyMedium))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    ForEach(["banknote.fill", "creditcard.fill", "building.columns.fill", "wallet.pass.fill"], id: \.self) { icon in
                                        Button(action: { selectedIcon = icon }) {
                                            Image(systemName: icon)
                                                .font(.system(size: AppFontSize.mainIcon))
                                                .foregroundColor(selectedIcon == icon ? selectedColor : .gray)
                                                .padding(10)
                                                .background(
                                                    Circle()
                                                        .fill(selectedIcon == icon ? Color.gray.opacity(0.3) : Color.clear)
                                                )
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Farb-Auswahl
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Farbe")
                                .foregroundColor(.white)
                                .font(.system(size: AppFontSize.bodyMedium))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    ForEach([Color.blue, Color.green, Color.orange, Color.red, Color.purple], id: \.self) { color in
                                        Button(action: { selectedColor = color }) {
                                            Circle()
                                                .fill(color)
                                                .frame(width: 30, height: 30)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                                                )
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        if isProcessing {
                            ProgressView("Konto wird erstellt...")
                                .foregroundColor(.white)
                                .padding()
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("Neues Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .disabled(isProcessing)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        handleAddAccount()
                    }
                    .disabled(accountName.isEmpty || !isViewReady || isProcessing)
                    .foregroundColor(accountName.isEmpty || !isViewReady || isProcessing ? .gray : .white)
                }
            }
            .alert("Fehler", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await initializeView()
        }
    }
    
    private func handleAddAccount() {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            do {
                // Hole die Gruppe im Hauptkontext
                guard let currentGroup = try managedObjectContext.existingObject(with: group.objectID) as? AccountGroup else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gruppe nicht gefunden"])
                }
                
                // Erstelle das Konto
                viewModel.addAccount(
                    name: accountName,
                    group: currentGroup,
                    icon: selectedIcon,
                    color: selectedColor
                )
                
                // Warte kurz, um sicherzustellen, dass die Änderungen gespeichert wurden
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 Sekunden
                
                await MainActor.run {
                    // Aktualisiere die UI und schließe die View
                    viewModel.objectWillChange.send()
                    viewModel.fetchAccountGroups()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    print("DEBUG: FEHLER beim Hinzufügen des Kontos: \(error)")
                    showError = true
                    errorMessage = "Fehler beim Hinzufügen des Kontos. Bitte versuchen Sie es erneut."
                    isProcessing = false
                }
            }
        }
    }
    
    private func initializeView() async {
        await MainActor.run {
            print("DEBUG: AddAccountView wird initialisiert")
            print("DEBUG: Gruppe Details - Name: \(group.name ?? "unknown"), ID: \(group.objectID)")
            
            // Versuche die Gruppe im Hauptkontext zu finden
            do {
                if let _ = try managedObjectContext.existingObject(with: group.objectID) as? AccountGroup {
                    print("DEBUG: Gruppe erfolgreich im Hauptkontext gefunden")
                    isViewReady = true
                } else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gruppe nicht gefunden"])
                }
            } catch {
                print("DEBUG: FEHLER beim Initialisieren der View: \(error)")
                showError = true
                errorMessage = "Fehler beim Laden der Gruppe. Bitte versuchen Sie es später erneut."
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = TransactionViewModel(context: context)
    let testGroup = AccountGroup(context: context)
    testGroup.name = "Testgruppe"
    return AddAccountView(viewModel: viewModel, group: testGroup)
        .environment(\.managedObjectContext, context)
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
