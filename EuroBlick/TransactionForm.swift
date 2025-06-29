import SwiftUI

// MARK: - AutoComplete TextField Component
struct AutoCompleteTextField: View {
    @Binding var text: String
    let suggestions: [String]
    let placeholder: String
    let icon: String
    
    @State private var suggestion: String = ""
    @State private var showSuggestion = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.gray)
                    .font(.system(size: 18))
                
                TextField(placeholder, text: $text)
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .focused($isFocused)
                    .onChange(of: text) { oldValue, newValue in
                        updateSuggestion(for: newValue)
                    }
                    .onSubmit {
                        if !suggestion.isEmpty {
                            text += suggestion
                            suggestion = ""
                            showSuggestion = false
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.6))
            .cornerRadius(8)
            .frame(height: 32)
            
            // Vorschlag unter dem Eingabefeld (besser sichtbar)
            if showSuggestion && !suggestion.isEmpty {
                HStack {
                    Text("Vorschlag: \(text + suggestion)")
                        .foregroundColor(.blue)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                        .onTapGesture {
                            text += suggestion
                            suggestion = ""
                            showSuggestion = false
                        }
                    
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }
    
    private func updateSuggestion(for input: String) {
        guard !input.isEmpty else {
            suggestion = ""
            showSuggestion = false
            return
        }
        
        // Debug: Zeige verfügbare Vorschläge
        print("🔍 Suche Vorschlag für: '\(input)'")
        print("📋 Verfügbare Vorschläge: \(suggestions.prefix(5))")
        
        // Finde passenden Vorschlag
        let matchingSuggestion = suggestions.first { suggestion in
            suggestion.lowercased().hasPrefix(input.lowercased()) && suggestion != input
        }
        
        if let match = matchingSuggestion {
            let remainingPart = String(match.dropFirst(input.count))
            suggestion = remainingPart
            showSuggestion = true
            print("✅ Vorschlag gefunden: '\(match)' -> '\(remainingPart)'")
        } else {
            suggestion = ""
            showSuggestion = false
            print("❌ Kein Vorschlag gefunden")
        }
    }
}

struct TransactionForm: View {
    @Binding var amount: String
    @Binding var category: String
    @Binding var newCategory: String
    @Binding var account: Account?
    @Binding var targetAccount: Account?
    @Binding var usage: String
    @Binding var date: Date
    let type: String
    let categories: [Category]
    let accountGroups: [AccountGroup]
    
    @FocusState var focusedField: AddTransactionView.Field?
    
    @FocusState private var amountFieldFocused: Bool
    @FocusState private var newCategoryFieldFocused: Bool
    @FocusState private var usageFieldFocused: Bool
    @State private var showTargetAccountPicker = false
    
    // Sammle alle Verwendungszwecke für Auto-Vervollständigung
    private var usageSuggestions: [String] {
        let allTransactions = accountGroups.flatMap { group in
            (group.accounts?.allObjects as? [Account] ?? []).flatMap { account in
                (account.transactions?.allObjects as? [Transaction] ?? [])
            }
        }
        
        let usages = allTransactions.compactMap { $0.usage }.filter { !$0.isEmpty }
        let uniqueUsages = Array(Set(usages)).sorted()
        return uniqueUsages
    }

    var body: some View {
        VStack(spacing: 35) {
            Spacer()
                .frame(height: 40)  // Zusätzlicher Abstand am Anfang (ca. 1 cm)
                
            // Betrag Eingabefeld
            HStack(spacing: 10) {
                Image(systemName: "eurosign.circle.fill")
                    .foregroundColor(.gray)
                    .font(.system(size: 18))
                CustomTextField(text: $amount, placeholder: "Betrag", isSecure: false)
                    .foregroundColor(.white)
                    .keyboardType(.decimalPad)
                    .focused($amountFieldFocused)
                    .id(AddTransactionView.Field.amount)
                    .frame(height: 32)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.6))
            .cornerRadius(8)
            .onChange(of: amountFieldFocused) { oldValue, newValue in
                if newValue {
                    focusedField = .amount
                } else if focusedField == .amount {
                    focusedField = nil
                }
            }
            .onChange(of: amount) { oldValue, newValue in
                let filtered = newValue.filter { "0123456789,.".contains($0) }
                if filtered != newValue {
                    amount = filtered
                }
            }

            // Kategorie Picker
            Picker("Kategorie", selection: $category) {
                Text("Kategorie auswählen").tag("").foregroundColor(.gray)
                Text("Neue Kategorie").tag("new").foregroundColor(.white)
                ForEach(categories, id: \.self) { category in
                    Text(category.name ?? "").tag(category.name ?? "").foregroundColor(.white)
                }
            }
            .pickerStyle(.menu)
            .accentColor(.white)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: 44)
            .background(Color.gray.opacity(0.6))
            .cornerRadius(8)
            .focused($focusedField, equals: .category)
            .id(AddTransactionView.Field.category)

            if category == "new" {
                CustomTextField(text: $newCategory, placeholder: "Neue Kategorie", isSecure: false)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(height: 44)
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(8)
                    .focused($newCategoryFieldFocused)
                    .id(AddTransactionView.Field.newCategory)
            }

            // Zielkonto Picker für Umbuchungen
            if type == "umbuchung" {
                Button(action: {
                    showTargetAccountPicker = true
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.gray)
                        Text(targetAccount?.name ?? "Zielkonto auswählen")
                            .foregroundColor(targetAccount == nil ? .gray : .white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(height: 44)
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showTargetAccountPicker) {
                    NavigationStack {
                        List {
                            ForEach(accountGroups) { group in
                                Section(header: Text(group.name ?? "").foregroundColor(.white)) {
                                    ForEach(group.accounts?.allObjects as? [Account] ?? [], id: \.self) { acc in
                                        if acc != account {  // Zeige nicht das aktuelle Konto an
                                            Button(action: {
                                                targetAccount = acc
                                                showTargetAccountPicker = false
                                            }) {
                                                HStack {
                                                    Text(acc.name ?? "")
                                                        .foregroundColor(.white)
                                                    Spacer()
                                                    if acc == targetAccount {
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
                        .navigationTitle("Zielkonto auswählen")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Fertig") {
                                    showTargetAccountPicker = false
                                }
                            }
                        }
                    }
                }
            }

            // Verwendungszweck Eingabefeld mit Auto-Vervollständigung
            AutoCompleteTextField(
                text: $usage,
                suggestions: usageSuggestions,
                placeholder: "Verwendungszweck",
                icon: "text.alignleft"
            )
            .onChange(of: usageFieldFocused) { oldValue, newValue in
                if newValue {
                    focusedField = .usage
                } else if focusedField == .usage {
                    focusedField = nil
                }
            }

            // Datum Picker
            DatePicker("Datum", selection: $date, displayedComponents: [.date])
                .foregroundStyle(.white)
                .tint(.white)
                .datePickerStyle(.compact)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(height: 44)
                .background(Color.gray.opacity(0.6))
                .cornerRadius(8)
                .environment(\.colorScheme, .dark)
                .focused($focusedField, equals: .date)
                .id(AddTransactionView.Field.date)
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
        .padding(.horizontal)
    }
}

#Preview {
    TransactionForm(
        amount: .constant(""),
        category: .constant(""),
        newCategory: .constant(""),
        account: .constant(nil),
        targetAccount: .constant(nil),
        usage: .constant(""),
        date: .constant(Date()),
        type: "einnahme",
        categories: [],
        accountGroups: []
    )
}
