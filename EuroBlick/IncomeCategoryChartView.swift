import SwiftUI
import Charts

struct IncomeCategoryChartView: View {
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
        let months = Set(allTx.map { fmt.string(from: $0.date) })
        
        return ["Alle Monate", "Benutzerdefinierter Zeitraum"] + months.sorted()
    }
    
    private var incomeCategoryData: [CategoryData] {
        let filteredTransactions = filterTransactionsByMonth(monthlyData.flatMap { $0.incomeTransactions })
            .filter { transaction in
                // Filtere alle Umbuchungen heraus (interne Transfers zwischen Konten)
                transaction.type != "umbuchung"
            }
        let grouped = Dictionary(grouping: filteredTransactions, by: { $0.categoryRelationship?.name ?? "Unbekannt" })
        
        return grouped.map { (category, transactions) in
            let value = transactions.reduce(0.0) { $0 + $1.amount }
            let color = categoryColor(for: category)
            return CategoryData(name: category, value: abs(value), color: color, transactions: transactions)
        }.sorted { abs($0.value) > abs($1.value) }
    }
    
    private var totalCategoryIncome: Double {
        incomeCategoryData.reduce(0.0) { $0 + $1.value }
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
        let categoryColors: [(pattern: String, color: Color)] = [
            ("gehalt", .blue),
            ("honorar", .green),
            ("provision", .purple),
            ("zinsen", .orange),
            ("erstattung", .pink),
            ("sonstiges", .gray)
        ]
        
        let lowercaseName = name.lowercased()
        if let match = categoryColors.first(where: { lowercaseName.contains($0.pattern) }) {
            return match.color
        }
        
        let fallbackColors: [Color] = [
            .blue, .green, .purple, .orange, .pink, .yellow,
            .mint, .cyan, .indigo, .red, .brown
        ]
        
        let index = abs(name.hashValue) % fallbackColors.count
        return fallbackColors[index]
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
                
                ScrollView {
                    VStack(spacing: 20) {
                        if !incomeCategoryData.isEmpty {
                            IncomeCategoryChartViewComponent(
                                categoryData: incomeCategoryData,
                                totalIncome: totalCategoryIncome,
                                showTransactions: { transactions, title in
                                    transactionsToShow = transactions
                                    transactionsTitle = title
                                    showTransactionsSheet = true
                                }
                            )
                        } else {
                            Text("Keine Einnahmen im ausgewählten Zeitraum")
                                .foregroundColor(.gray)
                                .padding()
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Einnahmen nach Kategorie")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
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
    }
    
    private func loadMonthlyData() {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "MMM yyyy"
        let allTx = accounts.flatMap { $0.transactions?.allObjects as? [Transaction] ?? [] }
        let filtered: [Transaction]
        if selectedMonth == "Benutzerdefinierter Zeitraum", let range = customDateRange {
            filtered = allTx.filter { transaction in
                let date = transaction.date
                return date >= range.start && date <= range.end
            }
        } else {
            filtered = selectedMonth == "Alle Monate" ? allTx : allTx.filter { fmt.string(from: $0.date) == selectedMonth }
        }
        let grouped = Dictionary(grouping: filtered, by: { fmt.string(from: $0.date) })
        monthlyData = grouped.keys.sorted().map { month in
            let txs = grouped[month] ?? []
            // Filtere Umbuchungen aus - sie sind weder Einnahmen noch Ausgaben
            let ins = txs.filter { $0.type == "einnahme" }
            let outs = txs.filter { $0.type == "ausgabe" }
            let income = ins.reduce(0) { $0 + $1.amount }
            let expenses = outs.reduce(0) { $0 + abs($1.amount) }
            return MonthlyData(
                month: month,
                income: income,
                expenses: expenses,
                surplus: income - expenses,
                incomeTransactions: ins,
                expenseTransactions: outs
            )
        }
    }
}

// MARK: - Chart Component

struct IncomeCategoryChartViewComponent: View {
    let categoryData: [CategoryData]
    let totalIncome: Double
    let showTransactions: ([Transaction], String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Einnahmen nach Kategorie")
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.bottom, 5)
            
            GeometryReader { geometry in
                ZStack {
                    ForEach(computeSegments()) { segment in
                        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        let radius = min(geometry.size.width, geometry.size.height) / 3.2
                        
                        Path { path in
                            path.move(to: center)
                            path.addArc(
                                center: center,
                                radius: radius,
                                startAngle: .radians(segment.startAngle),
                                endAngle: .radians(segment.endAngle),
                                clockwise: false
                            )
                            path.closeSubpath()
                        }
                        .fill(categoryColor(for: segment.name))
                        .onTapGesture {
                            if let categoryData = categoryData.first(where: { $0.name == segment.name }) {
                                showTransactions(categoryData.transactions, "Einnahmen: \(segment.name)")
                            }
                        }
                    }
                    
                    OverlayAnnotationsView(
                        segments: computeSegments(),
                        geometry: geometry,
                        style: .angled
                    )
                }
            }
            .frame(height: 250)
            
            IncomeCategoryTableView(
                categoryData: categoryData,
                totalIncome: totalIncome,
                showTransactions: showTransactions
            )
        }
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
    }
    
    private func computeSegments() -> [SegmentData] {
        var startAngle: Double = 0
        return categoryData.map { category in
            let percentage = abs(category.value) / totalIncome
            let angle = 2 * .pi * percentage
            let segment = SegmentData(
                id: UUID(),
                name: category.name,
                value: abs(category.value),
                startAngle: startAngle,
                endAngle: startAngle + angle
            )
            startAngle += angle
            return segment
        }.sorted { $0.percentage > $1.percentage }
    }

    private func categoryColor(for name: String) -> Color {
        categoryData.first(where: { $0.name == name })?.color ?? .gray
    }
}

// MARK: - Table View

struct IncomeCategoryTableView: View {
    let categoryData: [CategoryData]
    let totalIncome: Double
    let showTransactions: ([Transaction], String) -> Void

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
        VStack(spacing: 0) {
            // Tabellenkopf
            HStack(spacing: 0) {
                Text("Kategorie")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Anteil")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("Betrag")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .font(.caption)
            
            // Tabellenzeilen
            ForEach(categoryData) { category in
                HStack(spacing: 0) {
                    // Kategorie mit Farbindikator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 12, height: 12)
                        Text(category.name)
                            .foregroundColor(.white)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Prozentanteil
                    Text(String(format: "%.1f%%", (category.value / totalIncome) * 100))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(.white)
                        .font(.caption2)
                    
                    // Betrag in Grün für Einnahmen
                    Text(formatAmount(category.value))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(.green)
                        .font(.caption2)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.clear)
                .font(.callout)
                .contentShape(Rectangle())
                .onTapGesture {
                    showTransactions(category.transactions, "Einnahmen: \(category.name)")
                }
                
                Divider()
                    .background(Color.gray.opacity(0.3))
            }
        }
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let vm = TransactionViewModel(context: ctx)
    let acc = Account(context: ctx)
    acc.name = "Test"
    return NavigationStack {
        IncomeCategoryChartView(accounts: [acc], viewModel: vm)
    }
} 