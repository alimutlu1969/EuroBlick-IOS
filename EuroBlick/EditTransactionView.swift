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
        self._type = State(initialValue: transaction.type ?? "einnahme")
        self._amount = State(initialValue: transaction.amount == 0.0 ? "" : String(abs(transaction.amount)))
        self._category = State(initialValue: transaction.categoryRelationship?.name ?? "")
        self._newCategory = State(initialValue: "")
        self._account = State(initialValue: transaction.account)
        self._targetAccount = State(initialValue: transaction.targetAccount)
        self._usage = State(initialValue: transaction.usage ?? "")
        self._date = State(initialValue: transaction.date)
        print("Initialized EditTransactionView with type: \(self._type.wrappedValue), amount: \(self._amount.wrappedValue), account: \(self._account.wrappedValue?.name ?? "nil"), category: \(self._category.wrappedValue), usage: \(self._usage.wrappedValue)")
    }

    var body: some View {
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
        .onAppear {
            if account == nil {
                account = viewModel.accountGroups.compactMap { group -> [Account]? in
                    guard let accounts = group.accounts?.allObjects as? [Account] else { return nil }
                    return accounts
                }.flatMap { $0 }.first
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
        TypeButtonsView(
            selectedType: $type,
            einnahmeColorSelected: einnahmeColorSelected,
            ausgabeColorSelected: ausgabeColorSelected,
            umbuchungColorSelected: umbuchungColorSelected,
            defaultColor: defaultColor
        )
        .padding()
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
                guard isValidInput, let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")) else {
                    print("Failed to save: Invalid input")
                    return
                }
                guard !isCancelled else {
                    print("Buchung abgebrochen, speichere nicht")
                    return
                }
                saveCount += 1
                let adjustedAmount = type == "ausgabe" ? -amountValue : amountValue
                print("Saving transaction (attempt \(saveCount)): type=\(type), amount=\(adjustedAmount), category=\(category == "new" && !newCategory.isEmpty ? newCategory : category), usage=\(usage)")
                
                let finalCategory = category == "new" && !newCategory.isEmpty ? newCategory : category
                
                viewModel.updateTransaction(
                    transaction,
                    type: type,
                    amount: adjustedAmount,
                    category: finalCategory,
                    account: account!,
                    targetAccount: type == "umbuchung" ? targetAccount : nil,
                    usage: usage.isEmpty ? nil : usage,
                    date: date
                ) {
                    dismiss()
                }
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
