import SwiftUI

struct SelectAccountGroupView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var managedObjectContext
    @ObservedObject var viewModel: TransactionViewModel
    @Binding var showAddAccountSheet: Bool
    @Binding var groupToEdit: AccountGroup?
    
    @State private var isLoading = true
    @State private var accountGroups: [AccountGroup] = []
    @State private var selectedGroup: AccountGroup?
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Lade Kontogruppen...")
                        .foregroundColor(.white)
                } else if accountGroups.isEmpty {
                    Text("Keine Kontogruppen vorhanden")
                        .foregroundColor(.white)
                } else {
                    List {
                        ForEach(accountGroups) { group in
                            Button(action: {
                                print("DEBUG: Gruppe ausgewählt - Name: \(group.name ?? "unknown"), ID: \(group.objectID)")
                                print("DEBUG: Gruppe Details - Konten: \(group.accounts?.count ?? 0)")
                                
                                // Stelle sicher, dass die Gruppe im richtigen Kontext ist
                                if let groupInContext = try? managedObjectContext.existingObject(with: group.objectID) as? AccountGroup {
                                    print("DEBUG: Gruppe erfolgreich in aktuellen Kontext geholt")
                                    selectedGroup = groupInContext
                                    groupToEdit = groupInContext
                                    showAddAccountSheet = true
                                    dismiss()
                                } else {
                                    print("DEBUG: FEHLER - Konnte Gruppe nicht in aktuellen Kontext holen")
                                }
                            }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.blue)
                                    Text(group.name ?? "")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(group.accounts?.count ?? 0) Konten")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Kontogruppe auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            print("DEBUG: SelectAccountGroupView erschienen")
            loadGroups()
        }
    }
    
    private func loadGroups() {
        isLoading = true
        accountGroups = viewModel.accountGroups
        print("DEBUG: Verfügbare Gruppen:")
        for group in accountGroups {
            print("DEBUG: - Gruppe: \(group.name ?? "unknown"), ID: \(group.objectID)")
        }
        isLoading = false
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = TransactionViewModel(context: context)
    let testGroup = AccountGroup(context: context)
    testGroup.name = "Testgruppe"
    viewModel.accountGroups.append(testGroup)
    return SelectAccountGroupView(viewModel: viewModel, showAddAccountSheet: .constant(false), groupToEdit: .constant(nil))
        .environment(\.managedObjectContext, context)
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
