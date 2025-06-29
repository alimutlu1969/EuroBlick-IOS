import SwiftUI
import Charts

// MARK: - Data Models

struct MonthlyData {
    let month: String
    let income: Double
    let expenses: Double
    let surplus: Double
    let incomeTransactions: [Transaction]
    let expenseTransactions: [Transaction]
}

struct CategoryData: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
    let transactions: [Transaction]
}

struct SegmentData: Identifiable {
    let id: UUID
    let name: String
    let value: Double
    let startAngle: Double
    let endAngle: Double
    
    var percentage: Double {
        (endAngle - startAngle) / (2 * .pi) * 100
    }
}

struct ForecastData {
    let month: String
    let einnahmen: Double
    let ausgaben: Double
    let balance: Double
}

// MARK: - Shared Views

// Date Filter Header
struct DateFilterHeader: View {
    @Binding var selectedMonth: String
    @Binding var showMonthPickerSheet: Bool
    @Binding var customDateRange: (start: Date, end: Date)?
    let monthlyData: [MonthlyData]
    
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        let number = NSNumber(value: abs(amount))
        let formattedAmount = formatter.string(from: number) ?? String(format: "%.2f", abs(amount))
        return amount >= 0 ? "+\(formattedAmount) €" : "-\(formattedAmount) €"
    }

    private func formatBalance(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        let number = NSNumber(value: abs(amount))
        let formattedAmount = formatter.string(from: number) ?? String(format: "%.2f", abs(amount))
        return "\(formattedAmount) €"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                showMonthPickerSheet = true
            }) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    Text(selectedMonth == "Benutzerdefinierter Zeitraum" && customDateRange != nil ? customDateRangeDisplay : selectedMonth)
                        .foregroundColor(.white)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .foregroundColor(.white)
                        .font(.caption2)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.3))
                .cornerRadius(10)
            }
            .padding(.horizontal)
            
            if selectedMonth != "Alle Monate", let data = monthlyData.first {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Einnahmen: \(formatBalance(data.income))")
                            .foregroundColor(.green)
                        Text("Ausgaben: \(formatBalance(abs(data.expenses)))")
                            .foregroundColor(.red)
                    }
                    .font(.caption)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Überschuss")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(formatAmount(data.surplus))
                            .font(.headline)
                            .foregroundColor(data.surplus >= 0 ? .green : .red)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
    }
    
    private var customDateRangeDisplay: String {
        guard let range = customDateRange else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
    }
}

// Month Picker Sheet
struct MonthPickerSheet: View {
    @Binding var selectedMonth: String
    @Binding var showMonthPickerSheet: Bool
    @Binding var showCustomDateRangeSheet: Bool
    let availableMonths: [String]
    @Binding var selectedCategory: CategoryData?
    @Binding var selectedUsage: CategoryData?
    let onFilter: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredMonths: [String] {
        if searchText.isEmpty {
            return availableMonths
        }
        return availableMonths.filter { $0.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Suchleiste
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Suchen...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .foregroundColor(.white)
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            // Schnellauswahl-Optionen
                            Group {
                                Button(action: {
                                    selectedMonth = "Alle Monate"
                                    dismiss()
                                    onFilter()
                                }) {
                                    HStack {
                                        Image(systemName: "calendar")
                                        Text("Alle Monate")
                                        Spacer()
                                        if selectedMonth == "Alle Monate" {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                
                                Button(action: {
                                    selectedMonth = "Benutzerdefinierter Zeitraum"
                                    showMonthPickerSheet = false
                                    showCustomDateRangeSheet = true
                                }) {
                                    HStack {
                                        Image(systemName: "calendar.badge.clock")
                                        Text("Benutzerdefinierter Zeitraum")
                                        Spacer()
                                        if selectedMonth == "Benutzerdefinierter Zeitraum" {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue.opacity(0.3))
                            .cornerRadius(12)
                            
                            // Trennlinie
                            Text("Verfügbare Monate")
                                .foregroundColor(.gray)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            
                            // Monatsliste
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(filteredMonths.filter { $0 != "Alle Monate" && $0 != "Benutzerdefinierter Zeitraum" }, id: \.self) { month in
                                    Button(action: {
                                        selectedMonth = month
                                        dismiss()
                                        onFilter()
                                    }) {
                                        HStack {
                                            Text(month)
                                            Spacer()
                                            if selectedMonth == month {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                        .padding()
                                        .background(selectedMonth == month ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2))
                                        .cornerRadius(12)
                                        .contentShape(Rectangle())
                                    }
                                    .foregroundColor(.white)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Zeitraum wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

// Transaction Sheet
struct TransactionSheet: View {
    let transactionsTitle: String
    let transactions: [Transaction]
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: TransactionViewModel
    
    @State private var editingTransaction: Transaction?
    
    // DateFormatter für deutsches Langformat
    static let germanLongDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMMM yyyy"
        return formatter
    }()
    
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        let number = NSNumber(value: abs(amount))
        let formattedAmount = formatter.string(from: number) ?? String(format: "%.2f", abs(amount))
        return "\(formattedAmount) €"
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text(transactionsTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Schließen") {
                            isPresented = false
                        }
                        .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    
                    // Transactions List - Sortiert absteigend nach Datum
                    List {
                        ForEach(transactions.sorted(by: { $0.date > $1.date }), id: \.self) { transaction in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(Self.germanLongDateFormatter.string(from: transaction.date))
                                        .foregroundColor(.white)
                                        .font(.caption)
                                    Spacer()
                                    Text(formatAmount(transaction.amount))
                                        .foregroundColor(transaction.amount >= 0 ? .green : .red)
                                        .font(.headline)
                                }
                                
                                Text("Kategorie: \(transaction.categoryRelationship?.name ?? "Unbekannt")")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                
                                if let usage = transaction.usage, !usage.isEmpty {
                                    Text(usage)
                                        .foregroundColor(.white.opacity(0.8))
                                        .font(.caption2)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 8)
                            .listRowBackground(Color.black)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingTransaction = transaction
                            }
                        }
                        .listRowBackground(Color.black)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $editingTransaction) { transaction in
            EditView(
                transaction: transaction,
                isPresented: Binding(
                    get: { editingTransaction != nil },
                    set: { if !$0 { editingTransaction = nil } }
                ),
                viewModel: viewModel
            )
        }
    }
}

// Edit View
struct EditView: View {
    let transaction: Transaction
    @Binding var isPresented: Bool
    let viewModel: TransactionViewModel
    
    @State private var editedAmount: String
    @State private var editedUsage: String
    @State private var editedCategory: String
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    init(transaction: Transaction, isPresented: Binding<Bool>, viewModel: TransactionViewModel) {
        self.transaction = transaction
        self._isPresented = isPresented
        self.viewModel = viewModel
        
        let amount = abs(transaction.amount)
        _editedAmount = State(initialValue: String(format: "%.2f", amount))
        _editedUsage = State(initialValue: transaction.usage ?? "")
        _editedCategory = State(initialValue: transaction.categoryRelationship?.name ?? "")
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Group {
                        VStack(alignment: .leading) {
                            Text("Betrag:")
                                .foregroundColor(.gray)
                            TextField("Betrag", text: $editedAmount)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Kategorie:")
                                .foregroundColor(.gray)
                            TextField("Kategorie", text: $editedCategory)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Verwendungszweck:")
                                .foregroundColor(.gray)
                            TextField("Verwendungszweck", text: $editedUsage)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("Transaktion bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Abbrechen") {
                    isPresented = false
                },
                trailing: Button("Speichern") {
                    saveChanges()
                }
            )
            .alert("Hinweis", isPresented: $showAlert) {
                Button("OK") {
                    if alertMessage == "Änderungen gespeichert" {
                        isPresented = false
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func saveChanges() {
        guard let amountValue = Double(editedAmount.replacingOccurrences(of: ",", with: ".")) else {
            alertMessage = "Ungültiger Betrag"
            showAlert = true
            return
        }
        
        let finalAmount = transaction.amount >= 0 ? abs(amountValue) : -abs(amountValue)
        
        guard let account = transaction.account else {
            alertMessage = "Konto nicht gefunden"
            showAlert = true
            return
        }
        
        viewModel.updateTransaction(
            transaction,
            type: transaction.type ?? (finalAmount >= 0 ? "einnahme" : "ausgabe"),
            amount: finalAmount,
            category: editedCategory,
            account: account,
            targetAccount: transaction.targetAccount,
            usage: editedUsage,
            date: transaction.date
        )
        
        alertMessage = "Änderungen gespeichert"
        showAlert = true
    }
} 