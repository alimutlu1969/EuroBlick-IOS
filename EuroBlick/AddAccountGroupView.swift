import SwiftUI

struct AddAccountGroupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TransactionViewModel
    @State private var groupName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Neue Kontogruppe").foregroundColor(.gray)) {
                    TextField("Gruppenname", text: $groupName)
                }
            }
            .navigationTitle("Kontogruppe hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        viewModel.addAccountGroup(name: groupName)
                        dismiss()
                    }
                    .disabled(groupName.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            print("Neue Kategorie hinzufügen ausgelöst")
                        }) {
                            Label("Kategorie hinzufügen", systemImage: "tag")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.black) // Sichtbare Farbe
                    }
                    .onAppear {
                        print("Rendering AddAccountGroupView Toolbar")
                    }
                }
            }
        }
        .background(Color.black)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = TransactionViewModel(context: context)
    return AddAccountGroupView(viewModel: viewModel)
        .environment(\.managedObjectContext, context)
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
