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
                            headerView
                            typeButtonsView
                            transactionFormView(proxy: proxy)
                            errorMessages
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Speichern") {
                        saveTransaction()
                    }
                    .foregroundColor(.white)
                    .disabled(!isValidInput)
                }
            }
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
        HStack(spacing: 15) {
            // Einnahmen Button
            Button(action: { type = "einnahme" }) {
                VStack {
                    Image(systemName: type == "einnahme" ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 24))
                    Text("Einnahme")
                        .font(.system(size: 12))
                }
                .frame(width: 80, height: 60)
                .foregroundColor(type == "einnahme" ? .white : .gray)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(type == "einnahme" ? einnahmeColorSelected : Color.gray.opacity(0.2))
                )
            }

            // Ausgaben Button
            Button(action: { type = "ausgabe" }) {
                VStack {
                    Image(systemName: type == "ausgabe" ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 24))
                    Text("Ausgabe")
                        .font(.system(size: 12))
                }
                .frame(width: 80, height: 60)
                .foregroundColor(type == "ausgabe" ? .white : .gray)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(type == "ausgabe" ? ausgabeColorSelected : Color.gray.opacity(0.2))
                )
            }

            // Umbuchung Button
            Button(action: { type = "umbuchung" }) {
                VStack {
                    Image(systemName: type == "umbuchung" ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                        .font(.system(size: 24))
                    Text("Umbuchung")
                        .font(.system(size: 12))
                }
                .frame(width: 80, height: 60)
                .foregroundColor(type == "umbuchung" ? .white : .gray)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(type == "umbuchung" ? umbuchungColorSelected : Color.gray.opacity(0.2))
                )
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
        HStack {
            Button(action: {
                isCancelled = true
                dismiss()
                if transaction.type == nil && transaction.amount == 0.0 {
                    viewModel.getContext().delete(transaction)
                    viewModel.saveContext(viewModel.getContext())
                }
            }) {
                Text("Abbrechen")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .cornerRadius(10)
            }

            Button(action: {
                saveTransaction()
            }) {
                Text("Speichern")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isValidInput ? Color.blue : Color.gray)
                    .cornerRadius(10)
            }
            .disabled(!isValidInput)
        }
        .padding(.horizontal)
        .padding(.bottom)
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
