import SwiftUI

struct AddTransactionView: View {
    @ObservedObject var viewModel: TransactionViewModel
    @Environment(\.dismiss) var dismiss
    let account: Account

    @State private var type: String = "einnahme"
    @State private var amount: String = ""
    @State private var category: String = ""
    @State private var newCategory: String = ""
    @State private var targetAccount: Account?
    @State private var usage: String = ""
    @State private var date: Date = Date()
    @State private var isCancelled: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    
    @StateObject private var keyboard = KeyboardResponder()
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case amount
        case category
        case newCategory
        case account
        case targetAccount
        case usage
        case date
    }

    private let einnahmeColorSelected = Color(red: 0.0, green: 0.392, blue: 0.0)
    private let ausgabeColorSelected = Color(red: 1.0, green: 0.0, blue: 0.0)
    private let umbuchungColorSelected = Color(red: 0.118, green: 0.565, blue: 1.0)
    private let defaultColor = Color.gray

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            headerView
                            typeButtonsView
                            transactionFormView(proxy: proxy)
                            actionButtons
                        }
                        .padding(.vertical, 20)
                        .padding(.bottom, keyboard.keyboardHeight > 0 ? keyboard.keyboardHeight + 20 : 40)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .onChange(of: usage) { newValue in
                print("AddTransactionView usage aktualisiert: '\(newValue)'")
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Fehler"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        alertMessage = ""
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private var headerView: some View {
        Text("Neue Transaktion")
            .font(.title)
            .foregroundColor(.white)
            .padding(.top, 10)
    }
    
    @ViewBuilder
    private var typeButtonsView: some View {
        TypeButtonsView(
            selectedType: $type,
            einnahmeColorSelected: einnahmeColorSelected,
            ausgabeColorSelected: ausgabeColorSelected,
            umbuchungColorSelected: umbuchungColorSelected,
            defaultColor: defaultColor
        )
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func transactionFormView(proxy: ScrollViewProxy) -> some View {
        TransactionForm(
            amount: $amount,
            category: $category,
            newCategory: $newCategory,
            account: .constant(account),
            targetAccount: $targetAccount,
            usage: $usage,
            date: $date,
            type: type,
            categories: viewModel.categories,
            accountGroups: viewModel.accountGroups
        )
        .scrollContentBackground(.hidden)
        .onChange(of: keyboard.keyboardHeight) { newHeight in
            if newHeight > 0 {
                withAnimation {
                    proxy.scrollTo("bottomButtons", anchor: .bottom)
                }
            }
        }
        .onChange(of: focusedField) { newFocus in
            if let field = newFocus {
                withAnimation {
                    proxy.scrollTo(field, anchor: .center)
                }
            }
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: {
                isCancelled = true
                dismiss()
            }) {
                Text("Abbrechen")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .cornerRadius(10)
            }

            Button(action: {
                validateAndSave()
            }) {
                Text("Speichern")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .id("bottomButtons")
    }

    private func validateAndSave() {
        guard !isCancelled else {
            print("Buchung abgebrochen, speichere nicht")
            return
        }
        guard !type.isEmpty, ["einnahme", "ausgabe", "umbuchung"].contains(type) else {
            DispatchQueue.main.async {
                self.alertMessage = "Ungültiger Transaktionstyp."
                self.showAlert = true
                print("Invalid input: type is empty or invalid")
            }
            return
        }
        guard !amount.isEmpty, let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")) else {
            DispatchQueue.main.async {
                self.alertMessage = "Bitte geben Sie einen gültigen Betrag ein."
                self.showAlert = true
                print("Invalid input: amount is empty or not a valid number")
            }
            return
        }
        guard amountValue != 0 else {
            DispatchQueue.main.async {
                self.alertMessage = "Betrag darf nicht 0 sein."
                self.showAlert = true
                print("Invalid input: amount is zero")
            }
            return
        }
        guard !category.isEmpty || (category == "new" && !newCategory.isEmpty) else {
            DispatchQueue.main.async {
                self.alertMessage = "Bitte wählen Sie eine Kategorie oder geben Sie eine neue ein."
                self.showAlert = true
                print("Invalid input: category is empty")
            }
            return
        }
        if type == "umbuchung" {
            guard targetAccount != nil, targetAccount != account else {
                DispatchQueue.main.async {
                    self.alertMessage = "Bitte wählen Sie ein anderes Zielkonto für die Umbuchung."
                    self.showAlert = true
                    print("Invalid input: targetAccount is nil or same as account for umbuchung")
                }
                return
            }
        }
        let adjustedAmount = type == "ausgabe" ? -amountValue : amountValue
        let finalCategory = category == "new" && !newCategory.isEmpty ? newCategory : category
        
        // Wenn eine neue Kategorie erstellt wird, speichere sie zuerst
        if category == "new" && !newCategory.isEmpty {
            viewModel.addCategory(name: newCategory) {
                print("Neue Kategorie '\(newCategory)' gespeichert")
                // Nach dem Speichern der Kategorie die Transaktion hinzufügen
                self.saveTransaction(adjustedAmount: adjustedAmount, finalCategory: finalCategory)
            }
        } else {
            // Wenn keine neue Kategorie, direkt die Transaktion speichern
            saveTransaction(adjustedAmount: adjustedAmount, finalCategory: finalCategory)
        }
    }
    
    private func saveTransaction(adjustedAmount: Double, finalCategory: String) {
        print("Saving new transaction: type=\(type), amount=\(adjustedAmount), category=\(finalCategory), usage=\(usage)")
        
        viewModel.addTransaction(
            type: type,
            amount: adjustedAmount,
            category: finalCategory,
            account: account,
            targetAccount: type == "umbuchung" ? targetAccount : nil,
            usage: usage.isEmpty ? nil : usage,
            date: date
        ) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.alertMessage = "Fehler beim Speichern: \(error.localizedDescription)"
                    self.showAlert = true
                    print("Fehler beim Speichern der Transaktion: \(error)")
                } else {
                    self.dismiss()
                }
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = TransactionViewModel(context: context)
    let account = Account(context: context)
    account.name = "Test-Konto"
    return AddTransactionView(viewModel: viewModel, account: account)
}
