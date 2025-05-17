import SwiftUI
import CoreData

struct SelectAccountGroupView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var managedObjectContext
    @ObservedObject var viewModel: TransactionViewModel
    @Binding var showAddAccountSheet: Bool
    @Binding var groupToEdit: AccountGroup?
    
    @State private var isLoading = true
    @State private var accountGroups: [AccountGroup] = []
    
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
                                handleGroupSelection(group)
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
    
    private func handleGroupSelection(_ group: AccountGroup) {
        print("DEBUG: Gruppe ausgewählt - Name: \(group.name ?? "unknown"), ID: \(group.objectID)")
        print("DEBUG: Gruppe Details - Konten: \(group.accounts?.count ?? 0)")
        
        // Stelle sicher, dass die Gruppe im richtigen Kontext ist
        do {
            if let groupInContext = try managedObjectContext.existingObject(with: group.objectID) as? AccountGroup {
                print("DEBUG: Gruppe erfolgreich in aktuellen Kontext geholt")
                
                // Aktualisiere den ViewModel-Zustand synchron
                groupToEdit = groupInContext
                showAddAccountSheet = true
                
                // Schließe die View sofort
                dismiss()
            } else {
                print("DEBUG: FEHLER - Konnte Gruppe nicht in aktuellen Kontext holen")
            }
        } catch {
            print("DEBUG: FEHLER beim Laden der Gruppe: \(error)")
        }
    }
    
    private func loadGroups() {
        isLoading = true
        // Lade die Gruppen im Hauptkontext
        let fetchRequest: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        do {
            accountGroups = try managedObjectContext.fetch(fetchRequest)
            print("DEBUG: Verfügbare Gruppen:")
            for group in accountGroups {
                print("DEBUG: - Gruppe: \(group.name ?? "unknown"), ID: \(group.objectID)")
            }
        } catch {
            print("DEBUG: FEHLER beim Laden der Gruppen: \(error)")
            accountGroups = []
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
