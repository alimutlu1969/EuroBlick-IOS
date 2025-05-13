import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TransactionViewModel
    let group: AccountGroup
    @State private var accountName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Neues Konto").foregroundColor(.gray)) {
                    TextField("Kontoname", text: $accountName)
                }
            }
            .navigationTitle("Konto hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        viewModel.addAccount(name: accountName, group: group)
                        dismiss()
                    }
                    .disabled(accountName.isEmpty)
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
                        print("Rendering AddAccountView Toolbar")
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
    let testGroup = AccountGroup(context: context)
    testGroup.name = "Testgruppe"
    return AddAccountView(viewModel: viewModel, group: testGroup)
        .environment(\.managedObjectContext, context)
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
