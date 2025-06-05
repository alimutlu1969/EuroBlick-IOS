import SwiftUI

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

            // Verwendungszweck Eingabefeld
            HStack(spacing: 10) {
                Image(systemName: "text.alignleft")
                    .foregroundColor(.gray)
                    .font(.system(size: 18))
                CustomTextField(text: $usage, placeholder: "Verwendungszweck", isSecure: false)
                    .foregroundColor(.white)
                    .focused($usageFieldFocused)
                    .id(AddTransactionView.Field.usage)
                    .frame(height: 32)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.6))
            .cornerRadius(8)
            .onChange(of: usageFieldFocused) { oldValue, newValue in
                if newValue {
                    focusedField = .usage
                } else if focusedField == .usage {
                    focusedField = nil
                }
            }
            .onChange(of: usage) { oldValue, newValue in
                let filtered = newValue.unicodeScalars
                    .filter { scalar in
                        let isAllowed = scalar.isASCII && CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.,").contains(scalar)
                        return isAllowed
                    }
                    .map { String($0) }
                    .joined()
                if filtered != newValue {
                    self.usage = filtered
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
