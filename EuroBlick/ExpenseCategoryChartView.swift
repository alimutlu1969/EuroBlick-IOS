import SwiftUI
import Charts

struct ExpenseCategoryChartView: View {
    let accounts: [Account]
    @ObservedObject var viewModel: TransactionViewModel
    
    @State private var selectedMonth: String
    @State private var showMonthPickerSheet = false
    @State private var showCustomDateRangeSheet = false
    @State private var customDateRange: (start: Date, end: Date)?
    @State private var monthlyData: [MonthlyData] = []
    @State private var showTransactionsSheet = false
    @State private var transactionsToShow: [Transaction] = []
    @State private var transactionsTitle: String = ""
    @State private var isLoading = true
    
    init(accounts: [Account], viewModel: TransactionViewModel) {
        self.accounts = accounts
        self.viewModel = viewModel
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMM yyyy"
        _selectedMonth = State(initialValue: formatter.string(from: Date()))
    }
    
    private var availableMonths: [String] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "MMM yyyy"
        
        let allTx = accounts.flatMap { $0.transactions?.allObjects as? [Transaction] ?? [] }
            .filter { !$0.excludeFromBalance } // Exclude transactions marked as excluded
        let months = Set(allTx.map { fmt.string(from: $0.date) })
        
        return ["Alle Monate", "Benutzerdefinierter Zeitraum"] + months.sorted()
    }
    
    private var categoryData: [CategoryData] {
        let filteredTransactions = filterTransactionsByMonth(monthlyData.flatMap { $0.expenseTransactions })
            .filter { transaction in
                // Filtere alle Umbuchungen heraus (interne Transfers zwischen Konten)
                transaction.type != "umbuchung"
            }
        let grouped = Dictionary(grouping: filteredTransactions, by: { $0.categoryRelationship?.name ?? "Unbekannt" })
        
        return grouped.map { (category, transactions) in
            let value = transactions.reduce(0.0) { $0 + abs($1.amount) }
            let color = categoryColor(for: category)
            return CategoryData(name: category, value: abs(value), color: color, transactions: transactions)
        }.sorted { abs($0.value) > abs($1.value) }
    }
    
    private var totalCategoryExpenses: Double {
        categoryData.reduce(0.0) { $0 + $1.value }
    }
    
    private func filterTransactionsByMonth(_ transactions: [Transaction]) -> [Transaction] {
        if selectedMonth == "Alle Monate" {
            return transactions
        } else if selectedMonth == "Benutzerdefinierter Zeitraum", let range = customDateRange {
            return transactions.filter { transaction in
                let date = transaction.date
                return date >= range.start && date <= range.end
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMM yyyy"
        return transactions.filter { transaction in
            let date = transaction.date
            return formatter.string(from: date) == selectedMonth
        }
    }
    
    private func categoryColor(for name: String) -> Color {
        let colors: [Color] = [.red, .orange, .pink, .purple, .blue, .indigo, .brown, .gray]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }
    
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
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Date Filter Header
                DateFilterHeader(
                    selectedMonth: $selectedMonth,
                    showMonthPickerSheet: $showMonthPickerSheet,
                    customDateRange: $customDateRange,
                    monthlyData: monthlyData
                )
                .background(Color.black.opacity(0.3))
                
                if isLoading {
                    Spacer()
                    ProgressView("Lade Daten...")
                        .foregroundColor(.white)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if !categoryData.isEmpty {
                                CategoryChartView(
                                    categoryData: categoryData,
                                    totalExpenses: totalCategoryExpenses,
                                    showTransactions: { transactions, title in
                                        print("🔍 ExpenseCategoryChartView: showTransactions aufgerufen mit Titel '\(title)' und \(transactions.count) Transaktionen")
                                        transactionsToShow = transactions
                                        transactionsTitle = title
                                        print("🔍 ExpenseCategoryChartView: showTransactionsSheet wird auf true gesetzt")
                                        DispatchQueue.main.async {
                                            showTransactionsSheet = true
                                        }
                                        print("🔍 ExpenseCategoryChartView: showTransactionsSheet wurde gesetzt")
                                    }
                                )
                            } else {
                                Text("Keine Ausgaben im ausgewählten Zeitraum")
                                    .foregroundColor(.gray)
                                    .padding()
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .navigationTitle("Ausgaben nach Kategorie")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadMonthlyData()
        }
        .onChange(of: selectedMonth) { oldValue, newValue in
            loadMonthlyData()
        }
        .sheet(isPresented: $showMonthPickerSheet) {
            MonthPickerSheet(
                selectedMonth: $selectedMonth,
                showMonthPickerSheet: $showMonthPickerSheet,
                showCustomDateRangeSheet: $showCustomDateRangeSheet,
                availableMonths: availableMonths,
                selectedCategory: .constant(nil),
                selectedUsage: .constant(nil),
                onFilter: {
                    loadMonthlyData()
                }
            )
        }
        .sheet(isPresented: $showTransactionsSheet) {
            TransactionSheet(
                transactionsTitle: transactionsTitle,
                transactions: transactionsToShow,
                isPresented: $showTransactionsSheet,
                viewModel: viewModel
            )
        }
        .onChange(of: showTransactionsSheet) { oldValue, newValue in
            print("🔍 ExpenseCategoryChartView: showTransactionsSheet geändert von \(oldValue) zu \(newValue)")
        }
    }
    
    private func loadMonthlyData() {
        isLoading = true
        print("DEBUG: loadMonthlyData started for ExpenseCategoryChartView")
        print("DEBUG: selectedMonth = '\(selectedMonth)'")
        print("DEBUG: accounts count = \(accounts.count)")
        
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "MMM yyyy"
        let allTx = accounts.flatMap { $0.transactions?.allObjects as? [Transaction] ?? [] }
            .filter { !$0.excludeFromBalance } // Exclude transactions marked as excluded
        print("DEBUG: Total transactions found = \(allTx.count) (excluding excluded transactions)")
        
        let filtered: [Transaction]
        if selectedMonth == "Benutzerdefinierter Zeitraum", let range = customDateRange {
            filtered = allTx.filter { transaction in
                let date = transaction.date
                return date >= range.start && date <= range.end
            }
            print("DEBUG: Filtered for custom date range = \(filtered.count)")
        } else if selectedMonth == "Alle Monate" {
            filtered = allTx
            print("DEBUG: Using all transactions = \(filtered.count)")
        } else {
            filtered = allTx.filter { fmt.string(from: $0.date) == selectedMonth }
            print("DEBUG: Filtered for month '\(selectedMonth)' = \(filtered.count)")
        }
        
        let grouped = Dictionary(grouping: filtered, by: { fmt.string(from: $0.date) })
        print("DEBUG: Grouped by months = \(grouped.keys.sorted())")
        
        monthlyData = grouped.keys.sorted().map { month in
            let txs = grouped[month] ?? []
            let ins = txs.filter { $0.type == "einnahme" }
            let outs = txs.filter { $0.type == "ausgabe" }
            let income = ins.reduce(0) { $0 + $1.amount }
            let expenses = outs.reduce(0) { $0 + abs($1.amount) }
            print("DEBUG: Month '\(month)' - Income: \(income), Expenses: \(expenses), Transactions: \(txs.count)")
            return MonthlyData(
                month: month,
                income: income,
                expenses: expenses,
                surplus: income - expenses,
                incomeTransactions: ins,
                expenseTransactions: outs
            )
        }
        
        print("DEBUG: Final monthlyData count = \(monthlyData.count)")
        if let firstData = monthlyData.first {
            print("DEBUG: First data - Month: '\(firstData.month)', Income: \(firstData.income), Expenses: \(firstData.expenses), IncomeTransactions: \(firstData.incomeTransactions.count), ExpenseTransactions: \(firstData.expenseTransactions.count)")
        }
        
        isLoading = false
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let vm = TransactionViewModel(context: ctx)
    let acc = Account(context: ctx)
    acc.name = "Test"
    return NavigationStack {
        ExpenseCategoryChartView(accounts: [acc], viewModel: vm)
    }
} 