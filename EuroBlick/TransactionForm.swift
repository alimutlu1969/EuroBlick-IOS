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

    var body: some View {
        VStack(spacing: 25) {
            CustomTextField(text: $amount, placeholder: "Betrag", isSecure: false)
                .foregroundColor(.white)
                .keyboardType(.decimalPad)
                .padding(.all, 10)
                .focused($amountFieldFocused)
                .id(AddTransactionView.Field.amount)
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
                        print("Betrag gefiltert: '\(filtered)'")
                    }
                }

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
            .padding(.all, 10)
            .background(Color.gray.opacity(0.6))
            .cornerRadius(8)
            .focused($focusedField, equals: .category)
            .id(AddTransactionView.Field.category)
            .onAppear {
                print("Kategorie-Picker: Hintergrundfarbe auf dunkelgrau (Color.gray.opacity(0.6)) gesetzt, Textfarbe auf Weiß")
            }

            if category == "new" {
                CustomTextField(text: $newCategory, placeholder: "Neue Kategorie", isSecure: false)
                    .foregroundColor(.white)
                    .padding(.all, 10)
                    .focused($newCategoryFieldFocused)
                    .id(AddTransactionView.Field.newCategory)
                    .onChange(of: newCategoryFieldFocused) { oldValue, newValue in
                        if newValue {
                            focusedField = .newCategory
                        } else if focusedField == .newCategory {
                            focusedField = nil
                        }
                    }
            }

            if type == "umbuchung" {
                Picker("Zielkonto", selection: $targetAccount) {
                    Text("Kein Zielkonto").tag(nil as Account?).foregroundColor(.gray)
                    ForEach(accountGroups.flatMap { $0.accounts?.allObjects as? [Account] ?? [] }.filter { $0 != account }, id: \.self) { target in
                        Text(target.name ?? "").tag(target as Account?).foregroundColor(.white)
                    }
                }
                .pickerStyle(.menu)
                .accentColor(.white)
                .foregroundColor(.white)
                .padding(.all, 10)
                .background(Color.gray.opacity(0.6))
                .cornerRadius(8)
                .focused($focusedField, equals: .targetAccount)
                .id(AddTransactionView.Field.targetAccount)
                .onAppear {
                    print("Zielkonto-Picker: Hintergrundfarbe auf dunkelgrau (Color.gray.opacity(0.6)) gesetzt, Textfarbe auf Weiß")
                }
            }

            CustomTextField(text: $usage, placeholder: "Verwendungszweck", isSecure: false)
                .foregroundColor(.white)
                .padding(.all, 10)
                .focused($usageFieldFocused)
                .id(AddTransactionView.Field.usage)
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
                    DispatchQueue.main.async {
                        if filtered != newValue {
                            self.usage = filtered
                            print("Verwendungszweck gefiltert: '\(filtered)' (Original: '\(newValue)')")
                        } else {
                            print("Verwendungszweck unverändert: '\(filtered)'")
                        }
                    }
                }

            DatePicker("Datum", selection: $date, in: ...Date(), displayedComponents: .date)
                .foregroundStyle(.white)
                .tint(.white)
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(minHeight: 80)
                .padding(.vertical, 8)
                .environment(\.colorScheme, .dark)
                .focused($focusedField, equals: .date)
                .id(AddTransactionView.Field.date)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .onAppear {
                    print("DatePicker gerendert")
                }
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
