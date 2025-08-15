import SwiftUI

struct AddTransactionView: View {
    @ObservedObject var viewModel: TransactionViewModel
    @Environment(\.dismiss) var dismiss
    let account: Account
    let initialType: String?

    @State private var type: String
    @State private var amount: String = ""
    @State private var category: String = ""
    @State private var newCategory: String = ""
    @State private var targetAccount: Account?
    @State private var usage: String = ""
    @State private var date: Date = Date()
    @State private var isCancelled: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showAccountPicker = false
    
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
    
    private let inputBackground = Color(white: 0.15)
    private let spacing: CGFloat = 20 // 0.5cm spacing

    init(viewModel: TransactionViewModel, account: Account, initialType: String? = nil) {
        self.viewModel = viewModel
        self.account = account
        self.initialType = initialType
        self._type = State(initialValue: initialType ?? "einnahme")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            typeButtonsView
                                .padding(.top, spacing)
                            Spacer(minLength: 20)
                            // Betrag-Feld
                            InputField(
                                icon: "eurosign.circle.fill",
                                placeholder: "Betrag",
                                text: $amount,
                                keyboardType: .decimalPad,
                                field: .amount,
                                focusedField: $focusedField
                            )
                            
                            // Category Picker
                            Menu {
                                Button(action: { category = "" }) {
                                    Text("Kategorie auswählen")
                                }
                                Button(action: { category = "new" }) {
                                    Text("Neue Kategorie")
                                }
                                ForEach(viewModel.getSortedCategories(), id: \.self) { cat in
                                    Button(action: { category = cat.name ?? "" }) {
                                        Text(cat.name ?? "")
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "tag.fill")
                                        .foregroundColor(.gray)
                                    Text(category.isEmpty ? "Kategorie auswählen" : category)
                                        .foregroundColor(category.isEmpty ? .gray : .white)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(inputBackground)
                                .cornerRadius(8)
                            }
                            .padding(.horizontal)

                            if category == "new" {
                                InputField(
                                    icon: "tag.fill",
                                    placeholder: "Neue Kategorie",
                                    text: $newCategory,
                                    field: .newCategory,
                                    focusedField: $focusedField
                                )
                            }

                            // Target Account Selection
                            if type == "umbuchung" {
                                Button(action: { showAccountPicker = true }) {
                                    HStack {
                                        Image(systemName: "building.columns.fill")
                                            .foregroundColor(.gray)
                                        Text(targetAccount?.name ?? "Zielkonto auswählen")
                                            .foregroundColor(targetAccount == nil ? .gray : .white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(inputBackground)
                                    .cornerRadius(8)
                                }
                                .padding(.horizontal)
                            }

                            // Usage Field
                            AutoCompleteTextField(
                                text: $usage,
                                suggestions: usageSuggestions,
                                placeholder: "Verwendungszweck",
                                icon: "text.alignleft"
                            )

                            // Date Picker
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundColor(.gray)
                                DatePicker("", selection: $date, displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(.white)
                                    .environment(\.locale, Locale(identifier: "de_DE"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(inputBackground)
                            .cornerRadius(8)
                            .padding(.horizontal)
                            Spacer(minLength: 20)
                            // Action Buttons
                            HStack(spacing: spacing) {
                                ActionButton(
                                    title: "Abbrechen",
                                    backgroundColor: Color(red: 0.9, green: 0.3, blue: 0.3)
                                ) {
                                    isCancelled = true
                                    dismiss()
                                }
                                ActionButton(
                                    title: "Speichern",
                                    backgroundColor: Color.blue
                                ) {
                                    validateAndSave()
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 50)
                        }
                    }
                }
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
            .sheet(isPresented: $showAccountPicker) {
                AccountPickerView(
                    viewModel: viewModel,
                    currentAccount: account,
                    selectedAccount: $targetAccount,
                    isPresented: $showAccountPicker
                )
            }
        }
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
        let adjustedAmount = type == "ausgabe" ? -abs(amountValue) : abs(amountValue)
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

    // Vorschlagsliste für Verwendungszwecke generieren
    private var usageSuggestions: [String] {
        let allTransactions = viewModel.accountGroups.flatMap { group in
            (group.accounts?.allObjects as? [Account] ?? []).flatMap { account in
                (account.transactions?.allObjects as? [Transaction] ?? [])
            }
        }
        let usages = allTransactions.compactMap { $0.usage }.filter { !$0.isEmpty }
        let uniqueUsages = Array(Set(usages)).sorted()
        return uniqueUsages
    }
}

// MARK: - Supporting Views

struct InputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var field: AddTransactionView.Field
    @FocusState.Binding var focusedField: AddTransactionView.Field?
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .font(.system(size: 16))
            CustomTextField(
                text: $text,
                placeholder: placeholder,
                isSecure: false
            )
            .foregroundColor(.white)
            .keyboardType(keyboardType)
            .focused($focusedField, equals: field)
            .frame(height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(Color(white: 0.15))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct AccountPickerView: View {
    let viewModel: TransactionViewModel
    let currentAccount: Account
    @Binding var selectedAccount: Account?
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.accountGroups) { group in
                    Section(header: Text(group.name ?? "").foregroundColor(.white)) {
                        ForEach(group.accounts?.allObjects as? [Account] ?? [], id: \.self) { acc in
                            if acc != currentAccount {
                                Button(action: {
                                    selectedAccount = acc
                                    isPresented = false
                                }) {
                                    HStack {
                                        Text(acc.name ?? "")
                                            .foregroundColor(.white)
                                        Spacer()
                                        if acc == selectedAccount {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Konto auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - AutoComplete TextField Component
struct AutoCompleteTextField: View {
    @Binding var text: String
    let suggestions: [String]
    let placeholder: String
    let icon: String
    
    @State private var filteredSuggestions: [String] = []
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.gray)
                    .font(.system(size: 18))
                TextField(placeholder, text: $text)
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        updateSuggestions(for: newValue)
                    }
                    .onTapGesture {
                        updateSuggestions(for: text)
                        showSuggestions = true
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.6))
            .cornerRadius(8)
            .frame(height: 32)
            
            if showSuggestions && !filteredSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSuggestions, id: \.self) { suggestion in
                        Button(action: {
                            text = suggestion
                            showSuggestions = false
                        }) {
                            Text(suggestion)
                                .foregroundColor(.blue)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color.white.opacity(0.08))
                    }
                }
                .background(Color.black)
                .cornerRadius(8)
                .shadow(radius: 2)
                .padding(.horizontal, 2)
                .zIndex(1)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                showSuggestions = false
            }
        }
    }
    
    private func updateSuggestions(for input: String) {
        if input.count < 2 {
            filteredSuggestions = []
            showSuggestions = false
            return
        }
        filteredSuggestions = suggestions.filter {
            $0.lowercased().contains(input.lowercased()) && $0 != input
        }.prefix(5).map { $0 }
        showSuggestions = !filteredSuggestions.isEmpty
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = TransactionViewModel(context: context)
    let account = Account(context: context)
    account.name = "Test-Konto"
    return AddTransactionView(viewModel: viewModel, account: account, initialType: "einnahme")
}
