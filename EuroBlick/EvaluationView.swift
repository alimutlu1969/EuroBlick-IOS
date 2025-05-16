import SwiftUI
import Charts
import os.log
import UIKit
import Foundation // Für mathematische Funktionen

struct EvaluationView: View {
    let accounts: [Account]
    @ObservedObject var viewModel: TransactionViewModel

    @State private var selectedMonth: String
    @State private var showMonthPickerSheet = false
    @State private var showCustomDateRangeSheet = false
    @State private var showTransactionsSheet = false
    @State private var shouldShowTransactionsSheet = false
    @State private var transactionsToShow: [Transaction] = []
    @State private var transactionsTitle: String = ""
    @State private var monthlyData: [MonthlyData] = []
    @State private var selectedCategory: CategoryData? = nil
    @State private var selectedUsage: CategoryData? = nil
    @State private var customDateRange: (start: Date, end: Date)?
    @State private var tempStartDate: Date
    @State private var tempEndDate: Date
    @State private var startDateString: String
    @State private var endDateString: String
    @State private var pdfURL: URL?

    // DateFormatter für die Textfelder
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    init(accounts: [Account], viewModel: TransactionViewModel) {
        self.accounts = accounts
        self.viewModel = viewModel
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMM yyyy"
        _selectedMonth = State(initialValue: formatter.string(from: Date()))

        // Initialisiere temporäre Datumswerte für den benutzerdefinierten Zeitraum
        let calendar = Calendar.current
        let currentDate = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) ?? currentDate
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? currentDate
        _tempStartDate = State(initialValue: startOfMonth)
        _tempEndDate = State(initialValue: endOfMonth)
        _startDateString = State(initialValue: dateFormatter.string(from: startOfMonth))
        _endDateString = State(initialValue: dateFormatter.string(from: endOfMonth))
    }

    // Erweiterte Farbenliste für mehr Abwechslung im Tortendiagramm
    private let colors: [Color] = [
        .red, .green, .blue, .yellow, .purple, .orange, .pink, .cyan,
        .teal, .indigo, .mint, .brown, .gray, .black,
        .accentColor, .primary, .secondary, .init(red: 0.5, green: 0.8, blue: 0.3),
        .init(red: 0.7, green: 0.2, blue: 0.9), .init(red: 0.3, green: 0.6, blue: 0.8)
    ]

    private var availableMonths: [String] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "MMM yyyy"
        
        // Alle Transaktionen sammeln
        let allTx = accounts.flatMap { $0.transactions?.allObjects as? [Transaction] ?? [] }
        
        // Debugging: Rohdaten der Transaktionsdaten ausgeben
        let debugFormatter = DateFormatter()
        debugFormatter.dateFormat = "dd.MM.yyyy"
        for tx in allTx {
            let dateString = debugFormatter.string(from: tx.date)
            print("Transaktion Datum: \(dateString)")
        }
        
        // Monate extrahieren
        let months = Set(allTx.map { fmt.string(from: $0.date) })
        
        // Debugging: Formatierten Monat ausgeben
        for month in months {
            print("Formatierter Monat: \(month)")
        }
        
        // Sortierung basierend auf Jahr und Monat
        return ["Alle Monate", "Benutzerdefinierter Zeitraum"] + months.sorted(by: sortMonths)
    }

    private func sortMonths(_ month1: String, _ month2: String) -> Bool {
        let components1 = month1.split(separator: " ")
        let components2 = month2.split(separator: " ")
        guard components1.count == 2, components2.count == 2 else { return false }
        
        let year1 = String(components1[1])
        let year2 = String(components2[1])
        let monthName1 = String(components1[0])
        let monthName2 = String(components2[0])
        
        if year1 != year2 {
            return year1 < year2
        }
        
        let monthOrder = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]
        let monthIndex1 = monthOrder.firstIndex(of: monthName1) ?? 0
        let monthIndex2 = monthOrder.firstIndex(of: monthName2) ?? 0
        return monthIndex1 < monthIndex2
    }

    private var categoryData: [CategoryData] {
        let filteredTransactions = filterTransactionsByMonth(monthlyData.flatMap { $0.expenseTransactions })
        let grouped = Dictionary(grouping: filteredTransactions, by: { $0.categoryRelationship?.name ?? "Unbekannt" })
        
        // Erstelle eine Map von Kategorienamen zu festen Farben
        let categoryColors: [String: Color] = [
            "Personal": .blue,
            "Raumkosten": .green,
            "Versicherung": .purple,
            "Steuern": .orange,
            "Büro": .pink,
            "Marketing": .yellow,
            "Sonstiges": .gray
        ]
        
        return grouped.map { (category, transactions) in
            let value = transactions.reduce(0.0) { $0 + $1.amount }
            // Verwende die vordefinierte Farbe oder eine aus dem colors Array
            let color = categoryColors[category] ?? colors[abs(category.hashValue) % colors.count]
            return CategoryData(name: category, value: abs(value), color: color, transactions: transactions)
        }.sorted { abs($0.value) > abs($1.value) } // Sortiere nach absolutem Wert absteigend
    }

    private var totalCategoryExpenses: Double {
        categoryData.reduce(0.0) { $0 + $1.value }
    }

    // Neue Funktion für Einnahmen nach Kategorie
    private var incomeCategoryData: [CategoryData] {
        let filteredTransactions = filterTransactionsByMonth(monthlyData.flatMap { $0.incomeTransactions })
        let grouped = Dictionary(grouping: filteredTransactions, by: { $0.categoryRelationship?.name ?? "Unbekannt" })
        
        // Erstelle eine Map von Kategorienamen zu festen Farben für Einnahmen
        let categoryColors: [String: Color] = [
            "Gehalt": .blue,
            "Honorar": .green,
            "Provision": .purple,
            "Zinsen": .orange,
            "Erstattung": .pink,
            "Sonstiges": .gray
        ]
        
        return grouped.map { (category, transactions) in
            let value = transactions.reduce(0.0) { $0 + $1.amount }
            let color = categoryColors[category] ?? colors[abs(category.hashValue) % colors.count]
            return CategoryData(name: category, value: abs(value), color: color, transactions: transactions)
        }.sorted { abs($0.value) > abs($1.value) }
    }

    private var totalCategoryIncome: Double {
        incomeCategoryData.reduce(0.0) { $0 + $1.value }
    }

    private var usageData: [CategoryData] {
        let filteredTransactions = filterTransactionsByMonth(monthlyData.flatMap { $0.expenseTransactions })
        let grouped = Dictionary(grouping: filteredTransactions, by: { $0.usage ?? "Unbekannt" })
        
        // Erstelle eine Map von Verwendungszwecken zu festen Farben
        let usageColors: [String: Color] = [
            "Miete": .purple,
            "Gehalt": .blue,
            "Versicherung": .orange,
            "Steuer": .yellow,
            "Büromaterial": .pink,
            "Werbung": .mint,
            "Sonstiges": .gray
        ]
        
        return grouped.map { (usage, transactions) in
            let value = transactions.reduce(0.0) { $0 + $1.amount }
            // Verwende die vordefinierte Farbe oder eine aus dem colors Array
            let color = usageColors[usage] ?? colors[abs(usage.hashValue) % colors.count]
            return CategoryData(name: usage, value: abs(value), color: color, transactions: transactions)
        }.sorted { abs($0.value) > abs($1.value) } // Sortiere nach absolutem Wert absteigend
    }

    private var totalUsageExpenses: Double {
        usageData.reduce(0.0) { $0 + $1.value }
    }

    private var forecastData: [ForecastData] {
        let currentBalance = accounts.reduce(0.0) { $0 + viewModel.getBalance(for: $1) }
        let totalEinnahmen = monthlyData.first?.income ?? 0.0
        let totalAusgaben = monthlyData.first?.expenses ?? 0.0
        let totalUeberschuss = totalEinnahmen - totalAusgaben // Korrigierte Berechnung

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMM yyyy"
        
        let calendar = Calendar.current
        let currentDate = Date()
        
        let selectedDate: Date
        if selectedMonth != "Alle Monate" && selectedMonth != "Benutzerdefinierter Zeitraum", let parsedDate = formatter.date(from: selectedMonth) {
            selectedDate = parsedDate
        } else {
            selectedDate = currentDate
        }

        let components = calendar.dateComponents([.year, .month], from: selectedDate)
        guard let startOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return []
        }
        let daysInMonth = range.count
        let currentDay = calendar.component(.day, from: selectedDate)
        let remainingDays = daysInMonth - currentDay

        let dailyEinnahmen = totalEinnahmen / Double(currentDay)
        let dailyAusgaben = totalAusgaben / Double(currentDay)
        let dailyUeberschuss = totalUeberschuss / Double(currentDay)

        let endOfMonthBalance = currentBalance + (dailyUeberschuss * Double(remainingDays))
        let endOfMonthEinnahmen = totalEinnahmen + (dailyEinnahmen * Double(remainingDays))
        let endOfMonthAusgaben = totalAusgaben + (dailyAusgaben * Double(remainingDays))

        return [ForecastData(
            month: formatter.string(from: selectedDate),
            einnahmen: endOfMonthEinnahmen,
            ausgaben: endOfMonthAusgaben,
            balance: endOfMonthBalance
        )]
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

    private func colorForValue(_ value: Double) -> Color {
        value >= 0 ? .green : .red
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        // Monatspicker
                        HStack {
                            Button(action: {
                                showMonthPickerSheet = true
                            }) {
                                HStack {
                                    Text(selectedMonth == "Benutzerdefinierter Zeitraum" && customDateRange != nil ? customDateRangeDisplay : selectedMonth)
                                        .foregroundColor(.white)
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: "calendar")
                                        .foregroundColor(.white)
                                        .font(.headline)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                            }
                            .padding(.horizontal)
                            Spacer()
                            if selectedMonth != "Alle Monate", let data = monthlyData.first {
                                Text("Überschuss: \(String(format: "%.2f €", data.surplus))")
                                    .foregroundColor(data.surplus >= 0 ? .green : .red)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal)
                            }
                        }

                        // Einnahmen/Ausgaben/Überschuss Balkendiagramm
                        if let data = monthlyData.first {
                            Text("Einnahmen / Ausgaben / Überschuss")
                                .foregroundColor(.white)
                                .font(.subheadline)
                                .padding(.horizontal)
                            let maxValue = max(abs(data.income), abs(data.expenses), abs(data.surplus))
                            let maxHeight: CGFloat = 150
                            let scaleFactor = maxValue > 0 ? maxHeight / maxValue : 1.0

                            HStack {
                                // Einnahmen (links, grün)
                                VStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(width: 80, height: CGFloat(abs(data.income)) * scaleFactor)
                                        .onTapGesture {
                                            print("Einnahmen Balken geklickt")
                                            loadMonthlyData()
                                            if let data = monthlyData.first {
                                                transactionsTitle = "Einnahmen"
                                                transactionsToShow = data.incomeTransactions
                                                shouldShowTransactionsSheet = true
                                            }
                                        }
                                    Text("Einnahmen")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .padding(.top, 8)
                                    Text("\(String(format: "%.2f €", data.income))")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                        .padding(.top, 4)
                                }
                                Spacer()
                                // Ausgaben (mitte, rot)
                                VStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(Color.red)
                                        .frame(width: 80, height: CGFloat(abs(data.expenses)) * scaleFactor)
                                        .onTapGesture {
                                            print("Ausgaben Balken geklickt")
                                            loadMonthlyData()
                                            if let data = monthlyData.first {
                                                transactionsTitle = "Ausgaben"
                                                transactionsToShow = data.expenseTransactions
                                                shouldShowTransactionsSheet = true
                                            }
                                        }
                                    Text("Ausgaben")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .padding(.top, 8)
                                    Text("\(String(format: "%.2f €", data.expenses))")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                        .padding(.top, 4)
                                }
                                Spacer()
                                // Überschuss (rechts, dynamische Farbe)
                                VStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(data.surplus >= 0 ? Color.green : Color.red)
                                        .frame(width: 80, height: CGFloat(abs(data.surplus)) * scaleFactor)
                                    Text("Überschuss")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .padding(.top, 8)
                                    Text("\(String(format: "%.2f €", data.surplus))")
                                        .foregroundColor(data.surplus >= 0 ? .green : .red)
                                        .font(.caption)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.horizontal)
                            .frame(height: maxHeight + 60) // Höhe für Balken + Text
                        }

                        // Einnahmen-Tortendiagramm
                        IncomeCategoryChartView(
                            categoryData: incomeCategoryData,
                            totalIncome: totalCategoryIncome,
                            showTransactions: { transactions, title in
                                loadMonthlyData()
                                transactionsTitle = title
                                transactionsToShow = transactions
                                os_log(.info, "%@: %d Einträge", title, transactions.count)
                                shouldShowTransactionsSheet = true
                            }
                        )
                        .padding(.vertical, 20)

                        // Pie-Chart für Kategorien
                        CategoryChartView(
                            categoryData: categoryData,
                            totalExpenses: totalCategoryExpenses,
                            showTransactions: { transactions, title in
                                loadMonthlyData()
                                transactionsTitle = title
                                transactionsToShow = transactions
                                os_log(.info, "%@: %d Einträge", title, transactions.count)
                                shouldShowTransactionsSheet = true
                            }
                        )
                        .padding(.vertical, 20)

                        // Pie-Chart für Verwendungszweck
                        UsageChartView(
                            usageData: usageData,
                            totalExpenses: totalUsageExpenses,
                            showTransactions: { transactions, title in
                                loadMonthlyData()
                                transactionsTitle = title
                                transactionsToShow = transactions
                                os_log(.info, "%@: %d Einträge", title, transactions.count)
                                shouldShowTransactionsSheet = true
                            }
                        )
                        .padding(.vertical, 20)

                        // Prognostizierter Kontostand
                        ForecastChartView(
                            forecastData: forecastData,
                            monthlyData: monthlyData.first,
                            transactionsTitle: $transactionsTitle,
                            transactionsToShow: $transactionsToShow,
                            showTransactionsSheet: $shouldShowTransactionsSheet
                        )
                        .padding(.vertical, 20)

                        // PDF Export Button
                        if let pdfURL = pdfURL {
                            ShareLink(item: pdfURL) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.title2)
                                    Text("PDF teilen")
                                        .font(.headline)
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                                .shadow(radius: 3)
                                .padding(.horizontal)
                                .padding(.top, 20)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            Button(action: {
                                generatePDF()
                            }) {
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .font(.title2)
                                    Text("PDF erstellen")
                                        .font(.headline)
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                                .shadow(radius: 3)
                                .padding(.horizontal)
                                .padding(.top, 20)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.bottom)
                }
                .onAppear {
                    loadMonthlyData()
                }
            }
            .navigationTitle("Auswertungen")
            .navigationBarTitleDisplayMode(.inline)
            .font(.title2)
            .sheet(isPresented: $showMonthPickerSheet) {
                MonthPickerSheet(
                    selectedMonth: $selectedMonth,
                    showMonthPickerSheet: $showMonthPickerSheet,
                    showCustomDateRangeSheet: $showCustomDateRangeSheet,
                    availableMonths: availableMonths,
                    selectedCategory: $selectedCategory,
                    selectedUsage: $selectedUsage,
                    onFilter: {
                        loadMonthlyData()
                    }
                )
            }
            .sheet(isPresented: $showCustomDateRangeSheet) {
                CustomDateRangeSheetView(
                    tempStartDate: $tempStartDate,
                    tempEndDate: $tempEndDate,
                    customDateRange: $customDateRange,
                    selectedMonth: $selectedMonth,
                    showCustomDateRangeSheet: $showCustomDateRangeSheet,
                    onFilter: {
                        loadMonthlyData()
                    }
                )
            }
            .sheet(isPresented: $shouldShowTransactionsSheet) {
                TransactionSheet(
                    transactionsTitle: transactionsTitle,
                    transactions: transactionsToShow,
                    isPresented: $showTransactionsSheet,
                    showTransactionsSheet: $shouldShowTransactionsSheet,
                    viewModel: viewModel
                )
            }
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

    // Anzeige des benutzerdefinierten Zeitraums
    private var customDateRangeDisplay: String {
        guard let range = customDateRange else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
    }

    private func updateStartDateFromString() {
        if let newDate = dateFormatter.date(from: startDateString) {
            tempStartDate = newDate
        } else {
            startDateString = dateFormatter.string(from: tempStartDate)
        }
    }

    private func updateEndDateFromString() {
        if let newDate = dateFormatter.date(from: endDateString) {
            tempEndDate = newDate
        } else {
            endDateString = dateFormatter.string(from: tempEndDate)
        }
    }

    // Funktion zum Generieren des PDFs
    private func generatePDF() {
        let generator = ReportPDFGenerator(
            monthlyData: monthlyData,
            categoryData: categoryData,
            usageData: usageData,
            forecastData: forecastData,
            selectedMonth: selectedMonth,
            customDateRange: customDateRange,
            customDateRangeDisplay: customDateRangeDisplay
        )
        self.pdfURL = generator.generatePDF()
    }
}

// Sub-View für das Monatsauswahl-Sheet
struct MonthPickerSheet: View {
    @Binding var selectedMonth: String
    @Binding var showMonthPickerSheet: Bool
    @Binding var showCustomDateRangeSheet: Bool
    let availableMonths: [String]
    @Binding var selectedCategory: CategoryData?
    @Binding var selectedUsage: CategoryData?
    let onFilter: () -> Void

    var body: some View {
        VStack {
            Text("Monat auswählen")
                .foregroundColor(.white)
                .font(.headline)
                .padding()
            
            Menu {
                ForEach(availableMonths, id: \.self) { month in
                    Button(action: {
                        selectedMonth = month
                        if month == "Benutzerdefinierter Zeitraum" {
                            showMonthPickerSheet = false
                            showCustomDateRangeSheet = true
                        }
                    }) {
                        Text(month)
                            .foregroundColor(.white)
                    }
                }
            } label: {
                HStack {
                    Text(selectedMonth)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.white)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.3))
                .cornerRadius(10)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
            .padding(.horizontal)
            
            Button(action: {
                selectedCategory = nil
                selectedUsage = nil
                onFilter()
                showMonthPickerSheet = false
            }) {
                Text("Filter anwenden")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding()
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

// Sub-View für das Transaktions-Sheet
struct TransactionSheet: View {
    let transactionsTitle: String
    let transactions: [Transaction]
    @Binding var isPresented: Bool
    @Binding var showTransactionsSheet: Bool
    @ObservedObject var viewModel: TransactionViewModel
    
    @State private var editingTransaction: Transaction?
    
    var body: some View {
        VStack {
            // Header
            HStack {
                Text(transactionsTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Schließen") {
                    isPresented = false
                    showTransactionsSheet = false
                }
                .foregroundColor(.blue)
            }
            .padding()
            
            // Transactions List
            List {
                ForEach(transactions, id: \.self) { transaction in
                    VStack(alignment: .leading) {
                        Text(transaction.date, style: .date)
                            .foregroundColor(.white)
                        Text("Betrag: \(String(format: "%.2f €", transaction.amount))")
                            .foregroundColor(transaction.amount >= 0 ? .green : .red)
                        Text("Kategorie: \(transaction.categoryRelationship?.name ?? "Unbekannt")")
                            .foregroundColor(.white)
                        if let usage = transaction.usage {
                            Text("Verwendungszweck: \(usage)")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingTransaction = transaction
                    }
                }
                .listRowBackground(Color.black)
            }
            .listStyle(PlainListStyle())
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
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
        
        // Initialize state variables with the transaction values
        let amount = abs(transaction.amount)
        _editedAmount = State(initialValue: String(format: "%.2f", amount))
        _editedUsage = State(initialValue: transaction.usage ?? "")
        _editedCategory = State(initialValue: transaction.categoryRelationship?.name ?? "")
        
        print("Initializing EditView with values:")
        print("Amount: \(amount)")
        print("Usage: \(transaction.usage ?? "")")
        print("Category: \(transaction.categoryRelationship?.name ?? "")")
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

// Unterkomponente für das Kategorien-Diagramm
struct CategoryChartView: View {
    let categoryData: [CategoryData]
    let totalExpenses: Double
    let showTransactions: ([Transaction], String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Ausgaben nach Kategorie")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 5)
            
            GeometryReader { geometry in
                ZStack {
                    // Tortendiagramm
                    ForEach(computeSegments()) { segment in
                        Path { path in
                            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            let radius = min(geometry.size.width, geometry.size.height) / 3.2
                            path.move(to: center)
                            path.addArc(center: center,
                                      radius: radius,
                                      startAngle: .radians(segment.startAngle),
                                      endAngle: .radians(segment.endAngle),
                                      clockwise: false)
                            path.closeSubpath()
                        }
                        .fill(categoryColor(for: segment.name))
                        .onTapGesture {
                            if let categoryData = categoryData.first(where: { $0.name == segment.name }) {
                                showTransactions(categoryData.transactions, "Ausgaben: \(segment.name)")
                            }
                        }
                    }
                    
                    // Beschriftungen
                    OverlayAnnotationsView(
                        segments: computeSegments(),
                        geometry: geometry,
                        style: .angled
                    )
                }
            }
            .frame(height: 250)
            
            ExpenseCategoryTableView(
                categoryData: categoryData,
                totalExpenses: totalExpenses,
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
            let percentage = abs(category.value) / totalExpenses
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
        // Vordefinierte Farben für häufige Kategorien
        let categoryColors: [(pattern: String, color: Color)] = [
            ("personal", .blue),
            ("raumkosten", .green),
            ("priv. kv", .purple),
            ("kv-beiträge", .mint),
            ("steuern", .orange),
            ("büro", .pink),
            ("marketing", .yellow),
            ("versicherung", .cyan),
            ("wareneinkauf", .red),
            ("instandhaltung", .indigo),
            ("reparatur", .brown),
            ("sonstiges", .gray)
        ]
        
        // Suche nach einem passenden Muster
        let lowercaseName = name.lowercased()
        if let match = categoryColors.first(where: { lowercaseName.contains($0.pattern) }) {
            return match.color
        }
        
        // Wenn kein Muster passt, verwende eine Farbe aus der Ersatzpalette
        let fallbackColors: [Color] = [
            .blue, .green, .purple, .orange, .pink, .yellow,
            .mint, .cyan, .indigo, .red, .brown
        ]
        
        let index = abs(name.hashValue) % fallbackColors.count
        return fallbackColors[index]
    }
}

// Neue View für die Ausgaben-Kategorie-Tabelle
struct ExpenseCategoryTableView: View {
    let categoryData: [CategoryData]
    let totalExpenses: Double
    let showTransactions: ([Transaction], String) -> Void

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
            .font(.subheadline)
            
            // Tabellenzeilen
            ForEach(categoryData) { category in
                HStack(spacing: 0) {
                    // Kategorie mit Farbindikator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(categoryColor(for: category.name))
                            .frame(width: 12, height: 12)
                        Text(category.name)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Prozentanteil
                    Text(String(format: "%.1f%%", (category.value / totalExpenses) * 100))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    // Betrag
                    Text(String(format: "%.2f €", category.value))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.clear)
                .foregroundColor(.white)
                .font(.callout)
                .onTapGesture {
                    showTransactions(category.transactions, "Ausgaben: \(category.name)")
                }
                
                Divider()
                    .background(Color.gray.opacity(0.3))
            }
        }
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
    }
    
    private func categoryColor(for name: String) -> Color {
        // Vordefinierte Farben für häufige Kategorien
        let categoryColors: [(pattern: String, color: Color)] = [
            ("personal", .blue),
            ("raumkosten", .green),
            ("priv. kv", .purple),
            ("kv-beiträge", .mint),
            ("steuern", .orange),
            ("büro", .pink),
            ("marketing", .yellow),
            ("versicherung", .cyan),
            ("wareneinkauf", .red),
            ("instandhaltung", .indigo),
            ("reparatur", .brown),
            ("sonstiges", .gray)
        ]
        
        // Suche nach einem passenden Muster
        let lowercaseName = name.lowercased()
        if let match = categoryColors.first(where: { lowercaseName.contains($0.pattern) }) {
            return match.color
        }
        
        // Wenn kein Muster passt, verwende eine Farbe aus der Ersatzpalette
        let fallbackColors: [Color] = [
            .blue, .green, .purple, .orange, .pink, .yellow,
            .mint, .cyan, .indigo, .red, .brown
        ]
        
        let index = abs(name.hashValue) % fallbackColors.count
        return fallbackColors[index]
    }
}

// Aktualisiere die IncomeCategoryChartView um die Tabelle einzubinden
struct IncomeCategoryChartView: View {
    let categoryData: [CategoryData]
    let totalIncome: Double
    let showTransactions: ([Transaction], String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Einnahmen nach Kategorie")
                .font(.headline)
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
        // Vordefinierte Farben für häufige Einnahme-Kategorien
        let categoryColors: [(pattern: String, color: Color)] = [
            ("gehalt", .blue),
            ("honorar", .green),
            ("provision", .purple),
            ("zinsen", .orange),
            ("erstattung", .pink),
            ("sonstiges", .gray)
        ]
        
        // Suche nach einem passenden Muster
        let lowercaseName = name.lowercased()
        if let match = categoryColors.first(where: { lowercaseName.contains($0.pattern) }) {
            return match.color
        }
        
        // Wenn kein Muster passt, verwende eine Farbe aus der Ersatzpalette
        let fallbackColors: [Color] = [
            .blue, .green, .purple, .orange, .pink, .yellow,
            .mint, .cyan, .indigo, .red, .brown
        ]
        
        let index = abs(name.hashValue) % fallbackColors.count
        return fallbackColors[index]
    }
}

// Neue View für die Einnahmen-Kategorie-Tabelle
struct IncomeCategoryTableView: View {
    let categoryData: [CategoryData]
    let totalIncome: Double
    let showTransactions: ([Transaction], String) -> Void

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
            .font(.subheadline)
            
            // Tabellenzeilen
            ForEach(categoryData) { category in
                HStack(spacing: 0) {
                    // Kategorie mit Farbindikator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(categoryColor(for: category.name))
                            .frame(width: 12, height: 12)
                        Text(category.name)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Prozentanteil
                    Text(String(format: "%.1f%%", (category.value / totalIncome) * 100))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    // Betrag
                    Text(String(format: "%.2f €", category.value))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.clear)
                .foregroundColor(.white)
                .font(.callout)
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
    
    private func categoryColor(for name: String) -> Color {
        // Vordefinierte Farben für häufige Einnahme-Kategorien
        let categoryColors: [(pattern: String, color: Color)] = [
            ("gehalt", .blue),
            ("honorar", .green),
            ("provision", .purple),
            ("zinsen", .orange),
            ("erstattung", .pink),
            ("sonstiges", .gray)
        ]
        
        // Suche nach einem passenden Muster
        let lowercaseName = name.lowercased()
        if let match = categoryColors.first(where: { lowercaseName.contains($0.pattern) }) {
            return match.color
        }
        
        // Wenn kein Muster passt, verwende eine Farbe aus der Ersatzpalette
        let fallbackColors: [Color] = [
            .blue, .green, .purple, .orange, .pink, .yellow,
            .mint, .cyan, .indigo, .red, .brown
        ]
        
        let index = abs(name.hashValue) % fallbackColors.count
        return fallbackColors[index]
    }
}

// Unterkomponente für das Verwendungszweck-Diagramm
struct UsageChartView: View {
    let usageData: [CategoryData]
    let totalExpenses: Double
    let showTransactions: ([Transaction], String) -> Void

    var body: some View {
        VStack {
            Text("Ausgaben nach Verwendungszweck")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 5)
            
            GeometryReader { geometry in
                ZStack {
                    // Tortendiagramm
                    ForEach(computeSegments()) { segment in
                        Path { path in
                            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            let radius = min(geometry.size.width, geometry.size.height) / 3.2
                            path.move(to: center)
                            path.addArc(center: center,
                                      radius: radius,
                                      startAngle: .radians(segment.startAngle),
                                      endAngle: .radians(segment.endAngle),
                                      clockwise: false)
                            path.closeSubpath()
                        }
                        .fill(usageColor(for: segment.name))
                        .onTapGesture {
                            if let usageData = usageData.first(where: { $0.name == segment.name }) {
                                showTransactions(usageData.transactions, "Verwendungszweck: \(segment.name)")
                            }
                        }
                    }
                    
                    // Beschriftungen mit verbesserter Verteilung
                    let segments = computeSegments()
                    OverlayAnnotationsView(
                        segments: segments,
                        geometry: geometry,
                        style: .distributed
                    )
                }
            }
            .frame(height: 250)
        }
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
    }
    
    private func computeSegments() -> [SegmentData] {
        var startAngle: Double = 0
        return usageData.map { usage in
            let percentage = abs(usage.value) / totalExpenses
            let angle = 2 * .pi * percentage
            let segment = SegmentData(
                id: UUID(),
                name: usage.name,
                value: abs(usage.value),
                startAngle: startAngle,
                endAngle: startAngle + angle
            )
            startAngle += angle
            return segment
        }.sorted { $0.percentage > $1.percentage } // Sortiere nach Größe
    }

    private func usageColor(for name: String) -> Color {
        // Vordefinierte Farben für häufige Verwendungszwecke
        let usageColors: [(pattern: String, color: Color)] = [
            ("miete", .purple),
            ("gehalt", .blue),
            ("versicherung", .orange),
            ("steuer", .yellow),
            ("finanzamt", .red),
            ("krankenkasse", .mint),
            ("vodafone", .cyan),
            ("strom", .green),
            ("gas", .indigo),
            ("alba", .brown),
            ("signal iduna", .pink),
            ("raimund", .blue),
            ("ferhat", .orange),
            ("sevim", .green),
            ("helen", .purple),
            ("soner", .mint),
            ("birgi", .yellow)
        ]
        
        // Suche nach einem passenden Muster
        let lowercaseName = name.lowercased()
        if let match = usageColors.first(where: { lowercaseName.contains($0.pattern) }) {
            return match.color
        }
        
        // Wenn kein Muster passt, verwende eine Farbe aus der Ersatzpalette
        let fallbackColors: [Color] = [
            .purple, .blue, .orange, .yellow, .red, .mint,
            .cyan, .green, .indigo, .brown, .pink
        ]
        
        // Berechne einen Hash-Wert für den Namen für konsistente Farbzuweisung
        var hash = 0
        for char in name {
            hash = ((hash << 5) &+ hash) &+ Int(char.asciiValue ?? 0)
        }
        return fallbackColors[abs(hash) % fallbackColors.count]
    }
}

// Sub-View für das Prognose-Diagramm
struct ForecastChartView: View {
    let forecastData: [ForecastData]
    let monthlyData: MonthlyData?
    @Binding var transactionsTitle: String
    @Binding var transactionsToShow: [Transaction]
    @Binding var showTransactionsSheet: Bool

    private func colorForValue(_ value: Double) -> Color {
        value >= 0 ? .green : .red
    }

    private func barHeight(for value: Double, scaleFactor: CGFloat) -> CGFloat {
        CGFloat(abs(value)) * scaleFactor
    }
    
    // Berechne tägliche Durchschnittswerte
    private func calculateDailyAverages() -> (income: Double, expenses: Double, surplus: Double)? {
        guard let data = monthlyData else { return nil }
        
        let calendar = Calendar.current
        let today = Date()
        let currentDay = Double(calendar.component(.day, from: today))
        
        let dailyIncome = data.income / currentDay
        let dailyExpenses = data.expenses / currentDay
        let dailySurplus = dailyIncome - dailyExpenses
        
        return (dailyIncome, dailyExpenses, dailySurplus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Prognostizierter Kontostand am Monatsende")
                .foregroundColor(.white)
                .font(.headline)
                .padding(.horizontal)
            
            // Tägliche Durchschnittswerte
            if let averages = calculateDailyAverages() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tägliche Durchschnittswerte:")
                        .foregroundColor(.white)
                        .font(.subheadline)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Einnahmen: \(String(format: "%.2f €", averages.income))")
                                .foregroundColor(.green)
                            Text("Ausgaben: \(String(format: "%.2f €", averages.expenses))")
                                .foregroundColor(.red)
                            Text("Überschuss: \(String(format: "%.2f €", averages.surplus))")
                                .foregroundColor(colorForValue(averages.surplus))
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.3))
                .cornerRadius(10)
                .padding(.horizontal)
            }

            if let forecast = forecastData.first {
                let maxValue = max(abs(forecast.einnahmen), abs(forecast.ausgaben), abs(forecast.balance))
                let maxHeight: CGFloat = 150
                let scaleFactor = maxValue > 0 ? maxHeight / maxValue : 1.0

                HStack {
                    // Prognostizierte Einnahmen
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 80, height: barHeight(for: forecast.einnahmen, scaleFactor: scaleFactor))
                            .onTapGesture {
                                transactionsTitle = "Prognostizierte Einnahmen"
                                transactionsToShow = monthlyData?.incomeTransactions ?? []
                                showTransactionsSheet = true
                            }
                        Text("Einnahmen")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.top, 8)
                        Text(String(format: "%.2f €", forecast.einnahmen))
                            .foregroundColor(.green)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                    Spacer()
                    // Prognostizierte Ausgaben
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 80, height: barHeight(for: forecast.ausgaben, scaleFactor: scaleFactor))
                            .onTapGesture {
                                transactionsTitle = "Prognostizierte Ausgaben"
                                transactionsToShow = monthlyData?.expenseTransactions ?? []
                                showTransactionsSheet = true
                            }
                        Text("Ausgaben")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.top, 8)
                        Text(String(format: "%.2f €", forecast.ausgaben))
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                    Spacer()
                    // Prognostizierter Kontostand
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(colorForValue(forecast.balance))
                            .frame(width: 80, height: barHeight(for: forecast.balance, scaleFactor: scaleFactor))
                        Text("Kontostand")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.top, 8)
                        Text(String(format: "%.2f €", forecast.balance))
                            .foregroundColor(colorForValue(forecast.balance))
                            .font(.caption)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                .frame(height: maxHeight + 60)
            }
        }
        .padding(.vertical)
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
    }
}

// OverlayAnnotationsView wiederherstellen
struct OverlayAnnotationsView: View {
    let segments: [SegmentData]
    let geometry: GeometryProxy
    let style: LabelStyle
    
    enum LabelStyle {
        case straight
        case angled
        case distributed
    }

    var body: some View {
        // Filtere Segmente, die größer als 7% sind
        let significantSegments = segments.filter { segment in
            let percentage = (segment.endAngle - segment.startAngle) / (2 * .pi) * 100
            return percentage >= 7
        }
        
        ForEach(significantSegments) { segment in
            let (startPoint, endPoint, labelPosition) = computeLinePositions(segment: segment, geometry: geometry)
            
            ZStack {
                // Bezugslinie
                Path { path in
                    path.move(to: startPoint)
                    if style == .angled {
                        let midPoint = CGPoint(
                            x: endPoint.x,
                            y: startPoint.y
                        )
                        path.addLine(to: midPoint)
                        path.addLine(to: endPoint)
                    } else {
                        path.addLine(to: endPoint)
                    }
                }
                .stroke(Color.white, lineWidth: 1)
                
                // Beschriftung mit Hintergrund und Prozentangabe
                let percentage = Int((segment.endAngle - segment.startAngle) / (2 * .pi) * 100)
                Text("\(segment.name) (\(percentage)%)")
                    .foregroundColor(.white)
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                    .offset(x: labelPosition.x - geometry.size.width/2,
                           y: labelPosition.y - geometry.size.height/2)
            }
        }
    }
    
    private func computeLinePositions(segment: SegmentData, geometry: GeometryProxy) -> (start: CGPoint, end: CGPoint, label: CGPoint) {
        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let radius = min(geometry.size.width, geometry.size.height) / 3.2
        let labelPadding: CGFloat = 30
        
        let midAngle = segment.startAngle + (segment.endAngle - segment.startAngle) / 2
        
        switch style {
        case .distributed:
            // Startpunkt am Rand des Segments
            let startPoint = CGPoint(
                x: center.x + CGFloat(cos(midAngle)) * (radius * 0.8),
                y: center.y + CGFloat(sin(midAngle)) * (radius * 0.8)
            )
            
            let isRightSide = cos(midAngle) > 0
            let lineLength = radius * 0.8
            
            // Berechne die Endposition basierend auf dem Winkel
            let endPoint = CGPoint(
                x: center.x + CGFloat(cos(midAngle)) * (radius * 1.4) + (isRightSide ? lineLength : -lineLength),
                y: center.y + CGFloat(sin(midAngle)) * (radius * 1.4)
            )
            
            // Label-Position
            let labelPosition = CGPoint(
                x: endPoint.x + (isRightSide ? labelPadding : -labelPadding),
                y: endPoint.y
            )
            
            return (startPoint, endPoint, labelPosition)
            
        case .angled, .straight:
            // Startpunkt am Rand des Segments
            let startPoint = CGPoint(
                x: center.x + CGFloat(cos(midAngle)) * (radius * 0.8),
                y: center.y + CGFloat(sin(midAngle)) * (radius * 0.8)
            )
            
            let isRightSide = cos(midAngle) > 0
            let lineLength = radius * 0.6
            
            // Berechne vertikale Verschiebung basierend auf dem Winkel
            let verticalOffset = radius * 0.8 * sin(midAngle)
            
            // Endpunkt mit vertikaler Verschiebung
            let endPoint = CGPoint(
                x: center.x + CGFloat(cos(midAngle)) * radius + (isRightSide ? lineLength : -lineLength),
                y: center.y + verticalOffset
            )
            
            // Label-Position mit zusätzlichem vertikalen Abstand
            let labelPosition = CGPoint(
                x: endPoint.x + (isRightSide ? labelPadding : -labelPadding),
                y: endPoint.y + (verticalOffset * 0.2)
            )
            
            return (startPoint, endPoint, labelPosition)
        }
    }
}

// Neue CustomOverlayAnnotationsView für bessere Etiketten-Verteilung
struct CustomOverlayAnnotationsView: View {
    let segments: [SegmentData]
    let geometry: GeometryProxy
    
    var body: some View {
        ForEach(segments) { segment in
            if segment.percentage >= 5 { // Zeige nur Etiketten für Segmente > 5%
                let (startPoint, controlPoint1, controlPoint2, endPoint, labelPosition) = computeCurvedLinePositions(segment: segment, geometry: geometry)
                
                ZStack {
                    // Gebogene Linie
                    Path { path in
                        path.move(to: startPoint)
                        path.addCurve(
                            to: endPoint,
                            control1: controlPoint1,
                            control2: controlPoint2
                        )
                    }
                    .stroke(Color.white, lineWidth: 1)
                    
                    // Beschriftung mit Hintergrund und Prozentangabe
                    Text("\(segment.name) (\(Int(segment.percentage))%)")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .position(labelPosition)
                }
            }
        }
    }
    
    private func computeCurvedLinePositions(segment: SegmentData, geometry: GeometryProxy) -> (start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, label: CGPoint) {
        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let radius = min(geometry.size.width, geometry.size.height) / 3.2
        
        // Verwende den labelAngle für die Position der Etiketten
        let angle = segment.labelAngle ?? (segment.startAngle + (segment.endAngle - segment.startAngle) / 2)
        
        // Startpunkt am Rand des Segments
        let startPoint = CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
        
        let isRightSide = cos(angle) > 0
        let lineLength = radius * 0.8
        
        // Berechne die Kontrollpunkte für die gebogene Linie
        let controlPoint1 = CGPoint(
            x: startPoint.x + CGFloat(cos(angle)) * (lineLength * 0.5),
            y: startPoint.y + CGFloat(sin(angle)) * (lineLength * 0.5)
        )
        
        let endPoint = CGPoint(
            x: center.x + CGFloat(cos(angle)) * (radius * 1.8) + (isRightSide ? lineLength : -lineLength),
            y: center.y + CGFloat(sin(angle)) * (radius * 1.8)
        )
        
        let controlPoint2 = CGPoint(
            x: endPoint.x - (isRightSide ? lineLength * 0.5 : -lineLength * 0.5),
            y: endPoint.y
        )
        
        // Label-Position
        let labelPadding: CGFloat = 10
        let labelPosition = CGPoint(
            x: endPoint.x + (isRightSide ? labelPadding : -labelPadding),
            y: endPoint.y
        )
        
        return (startPoint, controlPoint1, controlPoint2, endPoint, labelPosition)
    }
}

// Erweitere das bestehende SegmentData Model
extension SegmentData {
    var labelAngle: Double? { nil }
}

extension DateFormatter {
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let vm = TransactionViewModel(context: ctx)
    let acc = Account(context: ctx)
    acc.name = "Test"
    return EvaluationView(accounts: [acc], viewModel: vm)
}
