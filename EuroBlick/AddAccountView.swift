import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TransactionViewModel
    let group: AccountGroup
    @State private var accountName = ""
    @State private var showActionSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Neues Konto").foregroundColor(.gray)) {
                    TextField("Kontoname", text: $accountName)
                        .textFieldStyle(DefaultTextFieldStyle())
                        .foregroundColor(.white)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Konto hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        viewModel.addAccount(name: accountName, group: group)
                        dismiss()
                    }
                    .disabled(accountName.isEmpty)
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        print("Neue Kategorie hinzufügen ausgelöst")
                    }) {
                        Image(systemName: "tag.badge.plus")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
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
