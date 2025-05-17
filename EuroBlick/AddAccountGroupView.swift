import SwiftUI

struct AddAccountGroupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TransactionViewModel
    @State private var groupName = ""
    @State private var showActionSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Neue Kontogruppe").foregroundColor(.gray)) {
                    TextField("Gruppenname", text: $groupName)
                        .textFieldStyle(DefaultTextFieldStyle())
                        .foregroundColor(.white)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Kontogruppe hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        viewModel.addAccountGroup(name: groupName)
                        dismiss()
                    }
                    .disabled(groupName.isEmpty)
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
    return AddAccountGroupView(viewModel: viewModel)
        .environment(\.managedObjectContext, context)
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
