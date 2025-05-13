import SwiftUI

struct SelectAccountGroupView: View {
    @Environment(\.dismiss) var dismiss
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
                    Form {
                        ForEach(accountGroups) { group in
                            Button(action: {
                                groupToEdit = group
                                showAddAccountSheet = true
                                dismiss()
                            }) {
                                Text(group.name ?? "Unbekannte Gruppe")
                                    .foregroundColor(.black) // Schwarzer Text für Lesbarkeit
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.gray.opacity(0.2)) // Hellgrauer Hintergrund
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .background(Color.black) // Hintergrund der Form schwarz
                }
            }
            .navigationTitle("Kontogruppe auswählen")
            .foregroundColor(.white)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
            .background(Color.black) // Gesamthintergrund schwarz
            .onAppear {
                loadData()
            }
        }
    }

    private func loadData() {
        isLoading = true
        viewModel.fetchAccountGroups()
        DispatchQueue.main.async {
            accountGroups = viewModel.accountGroups
            isLoading = false
            print("Geladene Kontogruppen: \(accountGroups.count) - \(accountGroups.map { $0.name ?? "Unnamed" })")
        }
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
