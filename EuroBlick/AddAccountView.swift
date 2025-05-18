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
    @State private var isProcessing = false
    @State private var selectedType = "offline"
    
    private let accountTypes = [
        ("Bargeld", "bargeld", "banknote.fill"),
        ("Offline", "offline", "building.columns.fill"),
        ("Bankkonto", "bankkonto", "building.columns.fill")
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    Form {
                        Section(header: Text("Kontoinformationen").foregroundColor(.gray)) {
                            VStack(alignment: .leading) {
                                Text("Kontoname")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                                
                                HStack {
                                    TextField("", text: $accountName)
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .medium))
                                    
                                    if !accountName.isEmpty {
                                        Button(action: { accountName = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color.blue.opacity(0.3))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue, lineWidth: 1)
                                )
                            }
                            .padding(.vertical, 8)
                            
                            Picker("Kontotyp", selection: $selectedType) {
                                ForEach(accountTypes, id: \.1) { type in
                                    HStack {
                                        Image(systemName: type.2)
                                        Text(type.0)
                                    }.tag(type.1)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .foregroundColor(.white)
                            
                            Picker("Icon", selection: $selectedIcon) {
                                ForEach(["banknote.fill", "building.columns.fill", "creditcard.fill", "wallet.pass.fill"], id: \.self) { icon in
                                    Image(systemName: icon).tag(icon)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            
                            ColorPicker("Icon-Farbe", selection: $selectedColor)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Neues Konto")
            .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(accountName.isEmpty || isProcessing)
                    .foregroundColor(accountName.isEmpty || isProcessing ? .gray : .white)
                }
            }
            .alert("Fehler", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func handleAddAccount() {
        guard !isProcessing else { return }
        
        isProcessing = true
        
        do {
            guard let currentGroup = try managedObjectContext.existingObject(with: group.objectID) as? AccountGroup else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gruppe nicht gefunden"])
            }
            
            viewModel.addAccount(
                name: accountName,
                group: currentGroup,
                icon: selectedIcon,
                color: selectedColor,
                type: selectedType
            )
            
            dismiss()
            
        } catch {
            print("DEBUG: FEHLER beim Hinzufügen des Kontos: \(error)")
            showError = true
            errorMessage = "Fehler beim Hinzufügen des Kontos. Bitte versuchen Sie es erneut."
            isProcessing = false
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
