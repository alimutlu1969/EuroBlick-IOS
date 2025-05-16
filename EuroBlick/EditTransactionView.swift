import SwiftUI

struct EditTransactionView: View {
    @ObservedObject var viewModel: TransactionViewModel
    @Environment(\.dismiss) var dismiss
    let transaction: Transaction

    @State private var type: String
    @State private var amount: String
    @State private var category: String
    @State private var newCategory: String
    @State private var account: Account?
    @State private var targetAccount: Account?
    @State private var usage: String
    @State private var date: Date
    @State private var saveCount: Int = 0
    @State private var amountError: String = ""
    @State private var categoryError: String = ""
    @State private var accountError: String = ""
    @State private var isCancelled: Bool = false
    @State private var showTargetAccountPicker: Bool = false
    
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

    init(viewModel: TransactionViewModel, transaction: Transaction) {
        self.viewModel = viewModel
        self.transaction = transaction
        
        // Initialisiere die Zustandsvariablen mit den Werten der Transaktion
        _type = State(initialValue: transaction.type ?? "einnahme")
        _amount = State(initialValue: String(format: "%.2f", abs(transaction.amount)))
        _category = State(initialValue: transaction.categoryRelationship?.name ?? "")
        _newCategory = State(initialValue: "")
        _account = State(initialValue: transaction.account)
        _targetAccount = State(initialValue: transaction.targetAccount)
        _usage = State(initialValue: transaction.usage ?? "")
        _date = State(initialValue: transaction.date)
        
        print("EditTransactionView initialisiert mit:")
        print("- Type: \(transaction.type ?? "nil")")
        print("- Amount: \(transaction.amount)")
        print("- Category: \(transaction.categoryRelationship?.name ?? "nil")")
        print("- Account: \(transaction.account?.name ?? "nil")")
        print("- Usage: \(transaction.usage ?? "nil")")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            Spacer()
                                .frame(height: 40)  // Zusätzlicher Abstand oben
                            typeButtonsView
                            transactionFormView(proxy: proxy)
                            errorMessages
                            Spacer(minLength: 30)
                            actionButtons
                        }
                        .padding(.top)
                        .padding(.bottom, keyboard.keyboardHeight + 20)
                        .animation(.easeInOut, value: keyboard.keyboardHeight)
                    }
                }
            }
            .navigationTitle("Transaktion bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    @ViewBuilder
    private var headerView: some View {
        Text("Transaktion bearbeiten")
            .font(.title)
            .foregroundColor(.white)
            .padding()
    }
    
    @ViewBuilder
    private var typeButtonsView: some View {
        HStack(spacing: 10) {
            // Einnahmen Button
            Button(action: { type = "einnahme" }) {
                VStack(spacing: 4) {
                    Image(systemName: type == "einnahme" ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 20))
                    Text("Einnahme")
                        .font(.system(size: 11))
                }
                .frame(width: 70, height: 50)
                .foregroundColor(type == "einnahme" ? .white : .gray)
                .background(type == "einnahme" ? einnahmeColorSelected : Color.clear)
                .cornerRadius(8)
            }

            // Ausgaben Button
            Button(action: { type = "ausgabe" }) {
                VStack(spacing: 4) {
                    Image(systemName: type == "ausgabe" ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 20))
                    Text("Ausgabe")
                        .font(.system(size: 11))
                }
                .frame(width: 70, height: 50)
                .foregroundColor(type == "ausgabe" ? .white : .gray)
                .background(type == "ausgabe" ? ausgabeColorSelected : Color.clear)
                .cornerRadius(8)
            }

            // Umbuchung Button
            Button(action: { type = "umbuchung" }) {
                VStack(spacing: 4) {
                    Image(systemName: type == "umbuchung" ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                        .font(.system(size: 20))
                    Text("Umbuchung")
                        .font(.system(size: 11))
                }
                .frame(width: 70, height: 50)
                .foregroundColor(type == "umbuchung" ? .white : .gray)
                .background(type == "umbuchung" ? umbuchungColorSelected : Color.clear)
                .cornerRadius(8)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func transactionFormView(proxy: ScrollViewProxy) -> some View {
        TransactionForm(
            amount: $amount,
            category: $category,
            newCategory: $newCategory,
            account: $account,
            targetAccount: $targetAccount,
            usage: $usage,
            date: $date,
            type: type,
            categories: viewModel.categories,
            accountGroups: viewModel.accountGroups
        )
        .scrollContentBackground(.hidden)
        .onChange(of: keyboard.keyboardHeight) { oldValue, newValue in
            if newValue > 0 {
                withAnimation {
                    proxy.scrollTo("bottomButtons", anchor: .bottom)
                }
            }
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if let field = newValue {
                withAnimation {
                    proxy.scrollTo(field, anchor: .center)
                }
            }
        }
        .onChange(of: type) { oldValue, newValue in
            if newValue == "umbuchung" {
                showTargetAccountPicker = true
            }
        }
        .onChange(of: account) { oldValue, newValue in
            if let account = newValue {
                self.account = account
            }
        }
    }
    
    @ViewBuilder
    private var errorMessages: some View {
        Group {
            if !amountError.isEmpty {
                Text(amountError)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            if !categoryError.isEmpty {
                Text(categoryError)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            if !accountError.isEmpty {
                Text(accountError)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack {
            Divider()
                .background(Color.gray.opacity(0.3))
                .padding(.bottom, 20)
            
            HStack(spacing: 15) {
                Button(action: {
                    isCancelled = true
                    dismiss()
                    if transaction.type == nil && transaction.amount == 0.0 {
                        viewModel.getContext().delete(transaction)
                        viewModel.saveContext(viewModel.getContext())
                    }
                }) {
                    Text("Abbrechen")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                }

                Button(action: {
                    saveTransaction()
                }) {
                    Text("Speichern")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(isValidInput ? Color.blue.opacity(0.8) : Color.gray.opacity(0.5))
                        .cornerRadius(8)
                }
                .disabled(!isValidInput)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 15)
        .id("bottomButtons")
    }

    private func saveTransaction() {
        guard isValidInput else { return }
        
        let finalAmount = type == "ausgabe" ? -abs(Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) : abs(Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0)
        
        viewModel.updateTransaction(
            transaction,
            type: type,
            amount: finalAmount,
            category: category == "new" ? newCategory : category,
            account: account ?? transaction.account!,
            targetAccount: type == "umbuchung" ? targetAccount : nil,
            usage: usage,
            date: date
        ) {
            dismiss()
        }
    }

    private var isValidInput: Bool {
        guard !type.isEmpty, ["einnahme", "ausgabe", "umbuchung"].contains(type) else {
            print("Invalid input: type is empty or invalid")
            return false
        }
        guard !amount.isEmpty, let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")) else {
            print("Invalid input: amount is empty or not a valid number")
            return false
        }
        guard amountValue != 0 else {
            print("Invalid input: amount is zero")
            return false
        }
        guard !category.isEmpty || (category == "new" && !newCategory.isEmpty) else {
            print("Invalid input: category is empty")
            return false
        }
        guard account != nil else {
            print("Invalid input: account is nil")
            return false
        }
        if type == "umbuchung" {
            guard targetAccount != nil, targetAccount != account else {
                print("Invalid input: targetAccount is nil or same as account for umbuchung")
                return false
            }
        }
        print("Input is valid")
        return true
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = TransactionViewModel(context: context)
    EditTransactionView(viewModel: viewModel, transaction: Transaction(context: context))
}
