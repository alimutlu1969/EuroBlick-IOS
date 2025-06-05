import SwiftUI
import Charts

struct IncomeExpenseChartView: View {
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
            .filter { !$0.excludeFromBalance }
        let months = Set(allTx.map { fmt.string(from: $0.date) })
        
        return ["Alle Monate", "Benutzerdefinierter Zeitraum"] + months.sorted()
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
                            if let data = monthlyData.first {
                                // Balkendiagramm
                                BarChartView(data: data, showTransactions: { transactions, title in
                                    print("🔍 IncomeExpenseChartView: showTransactions aufgerufen mit Titel '\(title)' und \(transactions.count) Transaktionen")
                                    transactionsToShow = transactions
                                    transactionsTitle = title
                                    print("🔍 IncomeExpenseChartView: showTransactionsSheet wird auf true gesetzt")
                                    DispatchQueue.main.async {
                                        showTransactionsSheet = true
                                    }
                                    print("🔍 IncomeExpenseChartView: showTransactionsSheet wurde gesetzt")
                                })
                                .frame(height: 300)
                                .padding()
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(10)
                                .padding(.horizontal)
                                
                                // Detaillierte Auflistung
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Details")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    // Einnahmen
                                    HStack {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 12, height: 12)
                                        Text("Einnahmen")
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(formatAmount(data.income))
                                            .foregroundColor(.green)
                                    }
                                    
                                    // Ausgaben
                                    HStack {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 12, height: 12)
                                        Text("Ausgaben")
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(formatAmount(data.expenses))
                                            .foregroundColor(.red)
                                    }
                                    
                                    Divider()
                                        .background(Color.gray)
                                    
                                    // Überschuss
                                    HStack {
                                        Circle()
                                            .fill(data.surplus >= 0 ? Color.green : Color.red)
                                            .frame(width: 12, height: 12)
                                        Text("Überschuss")
                                            .foregroundColor(.white)
                                            .fontWeight(.bold)
                                        Spacer()
                                        Text(formatAmount(data.surplus))
                                            .foregroundColor(data.surplus >= 0 ? .green : .red)
                                            .fontWeight(.bold)
                                    }
                                }
                                .padding()
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(10)
                                .padding(.horizontal)
                            } else {
                                Text("Keine Daten für den ausgewählten Zeitraum")
                                    .foregroundColor(.gray)
                                    .padding()
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .navigationTitle("Einnahmen / Ausgaben")
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
            print("🔍 IncomeExpenseChartView: showTransactionsSheet geändert von \(oldValue) zu \(newValue)")
        }
    }
    
    private func loadMonthlyData() {
        isLoading = true
        print("DEBUG: loadMonthlyData started for IncomeExpenseChartView")
        print("DEBUG: selectedMonth = '\(selectedMonth)'")
        print("DEBUG: accounts count = \(accounts.count)")
        
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "MMM yyyy"
        let allTx = accounts.flatMap { $0.transactions?.allObjects as? [Transaction] ?? [] }
            .filter { !$0.excludeFromBalance }
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
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let vm = TransactionViewModel(context: ctx)
    let acc = Account(context: ctx)
    acc.name = "Test"
    return NavigationStack {
        IncomeExpenseChartView(accounts: [acc], viewModel: vm)
    }
} 