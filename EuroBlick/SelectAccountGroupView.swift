import SwiftUI
import CoreData

struct SelectAccountGroupView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var managedObjectContext
    @ObservedObject var viewModel: TransactionViewModel
    let onGroupSelected: (AccountGroup) -> Void
    
    @State private var isLoading = true
    @State private var accountGroups: [AccountGroup] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
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
                                .listRowBackground(Color.gray.opacity(0.2))
                            }
                        }
                        .listStyle(PlainListStyle())
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Kontogruppe auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .foregroundColor(.white)
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
        
        do {
            let context = viewModel.getContext()
            if let groupInContext = try context.existingObject(with: group.objectID) as? AccountGroup {
                print("DEBUG: Gruppe erfolgreich in ViewModel-Kontext geholt: \(groupInContext.name ?? "unknown")")
                dismiss()
                onGroupSelected(groupInContext)
            } else {
                print("DEBUG: FEHLER - Konnte Gruppe nicht in ViewModel-Kontext holen")
            }
        } catch {
            print("DEBUG: FEHLER beim Laden der Gruppe: \(error)")
        }
    }
    
    private func loadGroups() {
        isLoading = true
        
        DispatchQueue.main.async {
            print("DEBUG: Lade Kontogruppen...")
            
            let context = viewModel.getContext()
            let fetchRequest: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            
            do {
                accountGroups = try context.fetch(fetchRequest)
                print("DEBUG: \(accountGroups.count) Gruppen geladen")
                
                print("DEBUG: Verfügbare Gruppen:")
                for group in accountGroups {
                    print("DEBUG: - Gruppe: \(group.name ?? "unknown"), ID: \(group.objectID), Konten: \(group.accounts?.count ?? 0)")
                }
                
                isLoading = false
            } catch {
                print("DEBUG: FEHLER beim Laden der Gruppen: \(error)")
                accountGroups = []
                isLoading = false
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = TransactionViewModel(context: context)
    let testGroup = AccountGroup(context: context)
    testGroup.name = "Testgruppe"
    viewModel.accountGroups.append(testGroup)
    return SelectAccountGroupView(viewModel: viewModel, onGroupSelected: { _ in })
        .environment(\.managedObjectContext, context)
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
