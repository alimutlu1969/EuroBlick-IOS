import SwiftUI
import Charts
import os.log
import UIKit
import Darwin // Für cos und sin

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

    struct MonthlyData: Identifiable {
        let id = UUID()
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

    struct ForecastData: Identifiable {
        let id = UUID()
        let month: String
        let einnahmen: Double
        let ausgaben: Double
        let balance: Double
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
        return grouped.map { (category, transactions) in
            let value = transactions.reduce(0.0) { $0 + $1.amount }
            let colorIndex = grouped.keys.sorted().firstIndex(of: category) ?? 0
            return CategoryData(name: category, value: value, color: colors[colorIndex % colors.count], transactions: transactions)
        }.sorted { $0.name < $1.name }
    }

    private var totalCategoryExpenses: Double {
        categoryData.reduce(0.0) { $0 + $1.value }
    }

    private var usageData: [CategoryData] {
        let filteredTransactions = filterTransactionsByMonth(monthlyData.flatMap { $0.expenseTransactions })
        let grouped = Dictionary(grouping: filteredTransactions, by: { $0.usage ?? "Unbekannt" })
        return grouped.map { (usage, transactions) in
            let value = transactions.reduce(0.0) { $0 + $1.amount }
            let colorIndex = grouped.keys.sorted().firstIndex(of: usage) ?? 0
            return CategoryData(name: usage, value: value, color: colors[colorIndex % colors.count], transactions: transactions)
        }.sorted { $0.name < $1.name }
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
                                        .font(.subheadline)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color.gray.opacity(0.3))
                                        .cornerRadius(8)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.white)
                                }
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
                                                print("transactionsToShow: \(transactionsToShow.count) Einträge")
                                                print("transactionsTitle: \(transactionsTitle)")
                                                print("shouldShowTransactionsSheet: \(shouldShowTransactionsSheet)")
                                            } else {
                                                print("Keine Daten für ausgewählten Monat gefunden")
                                            }
                                        }
                                    Text("Einnahmen")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .padding(.top, 8)
                                    Text("\(String(format: "%.2f €", data.income))")
                                        .foregroundColor(data.income >= 0 ? .green : .red)
                                        .font(.caption)
                                        .padding(.top, 4)
                                }
                                Spacer()
                                // Ausgaben (mitte, rot)
                                VStack {
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
                                                print("transactionsToShow: \(transactionsToShow.count) Einträge")
                                                print("transactionsTitle: \(transactionsTitle)")
                                                print("shouldShowTransactionsSheet: \(shouldShowTransactionsSheet)")
                                            } else {
                                                print("Keine Daten für ausgewählten Monat gefunden")
                                            }
                                        }
                                    Text("Ausgaben")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .padding(.top, 8)
                                    Text("\(String(format: "%.2f €", data.expenses))")
                                        .foregroundColor(data.expenses >= 0 ? .green : .red)
                                        .font(.caption)
                                        .padding(.top, 4)
                                }
                                Spacer()
                                // Überschuss (rechts, blau)
                                VStack {
                                    Rectangle()
                                        .fill(Color.blue)
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
                            .frame(height: 200)
                        }

                        // Pie-Chart für Kategorien
                        CategoryChartView(
                            data: categoryData,
                            selectedData: $selectedCategory,
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
                            data: usageData,
                            selectedData: $selectedUsage,
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
                            ShareLink(item: pdfURL, message: Text("Hier ist dein PDF-Export von EuroBlick")) {
                                Text("PDF Exportieren")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding()
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                                    .padding(.top, 20)
                            }
                        } else {
                            Button(action: {
                                generatePDF()
                            }) {
                                Text("PDF Exportieren")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding()
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                                    .padding(.top, 20)
                            }
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
                    showTransactionsSheet: $shouldShowTransactionsSheet
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
                surplus: income - expenses, // Korrigierte Berechnung
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
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)) // A4 Größe
        let data = renderer.pdfData { context in
            context.beginPage()
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.black
            ]
            
            let sectionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.black
            ]
            
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
            
            let legendAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.black
            ]
            
            let pageRect = context.pdfContextBounds
            var currentY: CGFloat = 20
            
            // Titel
            let title = NSAttributedString(string: "EuroBlick Auswertungen", attributes: titleAttributes)
            title.draw(at: CGPoint(x: 20, y: currentY))
            currentY += 30
            
            // Zeitraum
            let timeRange = selectedMonth == "Benutzerdefinierter Zeitraum" && customDateRange != nil ? customDateRangeDisplay : selectedMonth
            let timeRangeString = NSAttributedString(string: "Zeitraum: \(timeRange)", attributes: sectionAttributes)
            timeRangeString.draw(at: CGPoint(x: 20, y: currentY))
            currentY += 20
            
            // Einnahmen/Ausgaben/Überschuss
            if let data = monthlyData.first {
                let incomeTitle = NSAttributedString(string: "Einnahmen/Ausgaben/Überschuss", attributes: sectionAttributes)
                incomeTitle.draw(at: CGPoint(x: 20, y: currentY))
                currentY += 20
                
                // Balkendiagramm für Einnahmen/Ausgaben/Überschuss
                let maxValue = max(abs(data.income), abs(data.expenses), abs(data.surplus))
                let maxHeight: CGFloat = 150
                let scaleFactor = maxValue > 0 ? maxHeight / maxValue : 1.0
                
                let incomeHeight = CGFloat(abs(data.income)) * scaleFactor
                let expensesHeight = CGFloat(abs(data.expenses)) * scaleFactor
                let surplusHeight = CGFloat(abs(data.surplus)) * scaleFactor
                
                // Prüfe, ob genug Platz für das Diagramm vorhanden ist
                if currentY + maxHeight + 40 > pageRect.height - 50 {
                    context.beginPage()
                    currentY = 20
                }
                
                // Einnahmen-Balken (grün)
                context.cgContext.setFillColor(UIColor.green.cgColor)
                context.cgContext.fill(CGRect(x: 40, y: currentY, width: 80, height: incomeHeight))
                
                // Ausgaben-Balken (rot)
                context.cgContext.setFillColor(UIColor.red.cgColor)
                context.cgContext.fill(CGRect(x: 140, y: currentY, width: 80, height: expensesHeight))
                
                // Überschuss-Balken (blau)
                context.cgContext.setFillColor(UIColor.blue.cgColor)
                context.cgContext.fill(CGRect(x: 240, y: currentY, width: 80, height: surplusHeight))
                
                currentY += maxHeight + 10
                
                // Beschriftungen unter den Balken
                let incomeLabel = NSAttributedString(string: "Einnahmen: \(String(format: "%.2f €", data.income))", attributes: textAttributes)
                incomeLabel.draw(at: CGPoint(x: 40, y: currentY))
                
                let expensesLabel = NSAttributedString(string: "Ausgaben: \(String(format: "%.2f €", data.expenses))", attributes: textAttributes)
                expensesLabel.draw(at: CGPoint(x: 140, y: currentY))
                
                let surplusLabel = NSAttributedString(string: "Überschuss: \(String(format: "%.2f €", data.surplus))", attributes: textAttributes)
                surplusLabel.draw(at: CGPoint(x: 240, y: currentY))
                
                currentY += 20
                
                // Transaktionen
                let incomeTransactionsTitle = NSAttributedString(string: "Einnahmen-Transaktionen:", attributes: sectionAttributes)
                incomeTransactionsTitle.draw(at: CGPoint(x: 20, y: currentY))
                currentY += 20
                
                for tx in data.incomeTransactions {
                    let dateString = DateFormatter.monthFormatter.string(from: tx.date)
                    let amountString = String(format: "%.2f €", tx.amount)
                    let transactionString = "\(dateString) - \(amountString)"
                    let transactionText = NSAttributedString(string: transactionString, attributes: textAttributes)
                    transactionText.draw(at: CGPoint(x: 40, y: currentY))
                    currentY += 15
                    
                    if currentY > pageRect.height - 50 {
                        context.beginPage()
                        currentY = 20
                    }
                }
                
                currentY += 10
                
                let expensesTransactionsTitle = NSAttributedString(string: "Ausgaben-Transaktionen:", attributes: sectionAttributes)
                expensesTransactionsTitle.draw(at: CGPoint(x: 20, y: currentY))
                currentY += 20
                
                for tx in data.expenseTransactions {
                    let dateString = DateFormatter.monthFormatter.string(from: tx.date)
                    let amountString = String(format: "%.2f €", tx.amount)
                    let transactionString = "\(dateString) - \(amountString)"
                    let transactionText = NSAttributedString(string: transactionString, attributes: textAttributes)
                    transactionText.draw(at: CGPoint(x: 40, y: currentY))
                    currentY += 15
                    
                    if currentY > pageRect.height - 50 {
                        context.beginPage()
                        currentY = 20
                    }
                }
                
                currentY += 20
                
                let surplusTitle = NSAttributedString(string: "Überschuss: \(String(format: "%.2f €", data.surplus))", attributes: sectionAttributes)
                surplusTitle.draw(at: CGPoint(x: 20, y: currentY))
                currentY += 20
            }
            
            // Kategorien
            context.beginPage()
            currentY = 20
            
            let categoriesTitle = NSAttributedString(string: "Ausgaben nach Kategorie: \(String(format: "%.2f €", totalCategoryExpenses))", attributes: sectionAttributes)
            categoriesTitle.draw(at: CGPoint(x: 20, y: currentY))
            currentY += 20
            
            // Tortendiagramm für Kategorien
            let totalCategoryValue = categoryData.reduce(0.0) { $0 + abs($1.value) }
            let centerX: CGFloat = pageRect.width / 2
            let centerY: CGFloat = currentY + 100
            let radius: CGFloat = 80
            var startAngle: CGFloat = -.pi / 2
            
            for category in categoryData {
                let proportion = abs(category.value) / totalCategoryValue
                let angle = proportion * 2 * .pi
                let endAngle = startAngle + angle
                
                // Konvertiere SwiftUI-Color in UIColor
                let uiColor: UIColor
                switch category.color {
                case .red: uiColor = .red
                case .green: uiColor = .green
                case .blue: uiColor = .blue
                case .yellow: uiColor = .yellow
                case .purple: uiColor = .purple
                case .orange: uiColor = .orange
                case .pink: uiColor = .systemPink
                case .cyan: uiColor = .cyan
                case .teal: uiColor = .systemTeal
                case .indigo: uiColor = .systemIndigo
                case .mint: uiColor = .systemMint
                case .brown: uiColor = .brown
                case .gray: uiColor = .gray
                case .black: uiColor = .black
                case .accentColor: uiColor = .systemBlue
                case .primary: uiColor = .label
                case .secondary: uiColor = .secondaryLabel
                default:
                    let components = category.color.cgColor?.components ?? [0, 0, 0, 1]
                    uiColor = UIColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
                }
                
                // Zeichne das Segment
                let path = UIBezierPath()
                path.move(to: CGPoint(x: centerX, y: centerY))
                path.addArc(withCenter: CGPoint(x: centerX, y: centerY), radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                path.close()
                
                context.cgContext.setFillColor(uiColor.cgColor)
                context.cgContext.addPath(path.cgPath)
                context.cgContext.fillPath()
                
                startAngle = endAngle
            }
            
            // Innerer Kreis für Donut-Effekt
            let innerRadius = radius * 0.5
            let innerCircle = UIBezierPath(arcCenter: CGPoint(x: centerX, y: centerY), radius: innerRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.addPath(innerCircle.cgPath)
            context.cgContext.fillPath()
            
            currentY += 200
            
            // Legende für Kategorien
            var legendX: CGFloat = 20
            var legendY: CGFloat = currentY
            for category in categoryData {
                // Farbquadrat
                let uiColor: UIColor
                switch category.color {
                case .red: uiColor = .red
                case .green: uiColor = .green
                case .blue: uiColor = .blue
                case .yellow: uiColor = .yellow
                case .purple: uiColor = .purple
                case .orange: uiColor = .orange
                case .pink: uiColor = .systemPink
                case .cyan: uiColor = .cyan
                case .teal: uiColor = .systemTeal
                case .indigo: uiColor = .systemIndigo
                case .mint: uiColor = .systemMint
                case .brown: uiColor = .brown
                case .gray: uiColor = .gray
                case .black: uiColor = .black
                case .accentColor: uiColor = .systemBlue
                case .primary: uiColor = .label
                case .secondary: uiColor = .secondaryLabel
                default:
                    let components = category.color.cgColor?.components ?? [0, 0, 0, 1]
                    uiColor = UIColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
                }
                
                context.cgContext.setFillColor(uiColor.cgColor)
                context.cgContext.fill(CGRect(x: legendX, y: legendY, width: 10, height: 10))
                
                // Text
                let legendText = NSAttributedString(string: "\(category.name): \(String(format: "%.2f €", category.value))", attributes: legendAttributes)
                let textWidth = legendText.size().width
                legendText.draw(at: CGPoint(x: legendX + 15, y: legendY))
                
                // Dynamische Positionierung: Nächste Spalte oder neue Zeile
                legendX += textWidth + 30
                if legendX > pageRect.width - 100 {
                    legendX = 20
                    legendY += 15
                }
                
                if legendY > pageRect.height - 50 {
                    context.beginPage()
                    legendX = 20
                    legendY = 20
                }
            }
            
            currentY = legendY + 20
            
            // Verwendungszweck
            context.beginPage()
            currentY = 20
            
            let usageTitle = NSAttributedString(string: "Ausgaben nach Verwendungszweck: \(String(format: "%.2f €", totalUsageExpenses))", attributes: sectionAttributes)
            usageTitle.draw(at: CGPoint(x: 20, y: currentY))
            currentY += 20
            
            // Tortendiagramm für Verwendungszweck
            let totalUsageValue = usageData.reduce(0.0) { $0 + abs($1.value) }
            startAngle = -.pi / 2
            
            for usage in usageData {
                let proportion = abs(usage.value) / totalUsageValue
                let angle = proportion * 2 * .pi
                let endAngle = startAngle + angle
                
                // Konvertiere SwiftUI-Color in UIColor
                let uiColor: UIColor
                switch usage.color {
                case .red: uiColor = .red
                case .green: uiColor = .green
                case .blue: uiColor = .blue
                case .yellow: uiColor = .yellow
                case .purple: uiColor = .purple
                case .orange: uiColor = .orange
                case .pink: uiColor = .systemPink
                case .cyan: uiColor = .cyan
                case .teal: uiColor = .systemTeal
                case .indigo: uiColor = .systemIndigo
                case .mint: uiColor = .systemMint
                case .brown: uiColor = .brown
                case .gray: uiColor = .gray
                case .black: uiColor = .black
                case .accentColor: uiColor = .systemBlue
                case .primary: uiColor = .label
                case .secondary: uiColor = .secondaryLabel
                default:
                    let components = usage.color.cgColor?.components ?? [0, 0, 0, 1]
                    uiColor = UIColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
                }
                
                // Zeichne das Segment
                let path = UIBezierPath()
                path.move(to: CGPoint(x: centerX, y: centerY))
                path.addArc(withCenter: CGPoint(x: centerX, y: centerY), radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                path.close()
                
                context.cgContext.setFillColor(uiColor.cgColor)
                context.cgContext.addPath(path.cgPath)
                context.cgContext.fillPath()
                
                startAngle = endAngle
            }
            
            // Innerer Kreis für Donut-Effekt
            let innerCircleUsage = UIBezierPath(arcCenter: CGPoint(x: centerX, y: centerY), radius: innerRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.addPath(innerCircleUsage.cgPath)
            context.cgContext.fillPath()
            
            currentY += 200
            
            // Legende für Verwendungszweck
            legendX = 20
            legendY = currentY
            for usage in usageData {
                // Farbquadrat
                let uiColor: UIColor
                switch usage.color {
                case .red: uiColor = .red
                case .green: uiColor = .green
                case .blue: uiColor = .blue
                case .yellow: uiColor = .yellow
                case .purple: uiColor = .purple
                case .orange: uiColor = .orange
                case .pink: uiColor = .systemPink
                case .cyan: uiColor = .cyan
                case .teal: uiColor = .systemTeal
                case .indigo: uiColor = .systemIndigo
                case .mint: uiColor = .systemMint
                case .brown: uiColor = .brown
                case .gray: uiColor = .gray
                case .black: uiColor = .black
                case .accentColor: uiColor = .systemBlue
                case .primary: uiColor = .label
                case .secondary: uiColor = .secondaryLabel
                default:
                    let components = usage.color.cgColor?.components ?? [0, 0, 0, 1]
                    uiColor = UIColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
                }
                
                context.cgContext.setFillColor(uiColor.cgColor)
                context.cgContext.fill(CGRect(x: legendX, y: legendY, width: 10, height: 10))
                
                // Text
                let legendText = NSAttributedString(string: "\(usage.name): \(String(format: "%.2f €", usage.value))", attributes: legendAttributes)
                let textWidth = legendText.size().width
                legendText.draw(at: CGPoint(x: legendX + 15, y: legendY))
                
                // Dynamische Positionierung: Nächste Spalte oder neue Zeile
                legendX += textWidth + 30
                if legendX > pageRect.width - 100 {
                    legendX = 20
                    legendY += 15
                }
                
                if legendY > pageRect.height - 50 {
                    context.beginPage()
                    legendX = 20
                    legendY = 20
                }
            }
            
            currentY = legendY + 20
            
            // Prognostizierter Kontostand
            context.beginPage()
            currentY = 20
            
            if let forecast = forecastData.first {
                let forecastTitle = NSAttributedString(string: "Prognostizierter Kontostand am Monatsende", attributes: sectionAttributes)
                forecastTitle.draw(at: CGPoint(x: 20, y: currentY))
                currentY += 20
                
                let maxValue = max(abs(forecast.einnahmen), abs(forecast.ausgaben), abs(forecast.balance))
                let maxHeight: CGFloat = 150
                let scaleFactor = maxValue > 0 ? maxHeight / maxValue : 1.0
                
                // Einnahmen-Balken (grün)
                context.cgContext.setFillColor(UIColor.green.cgColor)
                context.cgContext.fill(CGRect(x: 40, y: currentY, width: 100, height: maxHeight * scaleFactor * (abs(forecast.einnahmen) / maxValue)))
                
                // Ausgaben-Balken (rot)
                context.cgContext.setFillColor(UIColor.red.cgColor)
                context.cgContext.fill(CGRect(x: 180, y: currentY, width: 100, height: maxHeight * scaleFactor * (abs(forecast.ausgaben) / maxValue)))
                
                // Kontostand-Balken (gelb)
                context.cgContext.setFillColor(UIColor.yellow.cgColor)
                context.cgContext.fill(CGRect(x: 320, y: currentY, width: 100, height: maxHeight * scaleFactor * (abs(forecast.balance) / maxValue)))
                
                currentY += maxHeight + 10
                
                // Beschriftungen unter den Balken
                let einnahmenLabel = NSAttributedString(string: "Einnahmen: \(String(format: "%.2f €", forecast.einnahmen))", attributes: textAttributes)
                einnahmenLabel.draw(at: CGPoint(x: 40, y: currentY))
                
                let ausgabenLabel = NSAttributedString(string: "Ausgaben: \(String(format: "%.2f €", forecast.ausgaben))", attributes: textAttributes)
                ausgabenLabel.draw(at: CGPoint(x: 180, y: currentY))
                
                let balanceLabel = NSAttributedString(string: "Kontostand: \(String(format: "%.2f €", forecast.balance))", attributes: textAttributes)
                balanceLabel.draw(at: CGPoint(x: 320, y: currentY))
                
                currentY += 20
            }
        }
        
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let pdfFileURL = temporaryDirectory.appendingPathComponent("EuroBlickAuswertungen.pdf")
        try? data.write(to: pdfFileURL)
        self.pdfURL = pdfFileURL
    }
}

// Sub-View für das Monatsauswahl-Sheet
struct MonthPickerSheet: View {
    @Binding var selectedMonth: String
    @Binding var showMonthPickerSheet: Bool
    @Binding var showCustomDateRangeSheet: Bool
    let availableMonths: [String]
    @Binding var selectedCategory: EvaluationView.CategoryData?
    @Binding var selectedUsage: EvaluationView.CategoryData?
    let onFilter: () -> Void

    var body: some View {
        VStack {
            Text("Monat auswählen")
                .foregroundColor(.white)
                .font(.headline)
                .padding()
            Picker("Monat auswählen", selection: $selectedMonth) {
                ForEach(availableMonths, id: \.self) { month in
                    Text(month).tag(month)
                        .foregroundColor(.white)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding()
            .foregroundColor(.white)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
            .onChange(of: selectedMonth) { oldValue, newValue in
                if newValue == "Benutzerdefinierter Zeitraum" {
                    showMonthPickerSheet = false
                    showCustomDateRangeSheet = true
                }
            }
            Button(action: {
                selectedCategory = nil
                selectedUsage = nil
                onFilter()
                showMonthPickerSheet = false
            }) {
                Text("Filtern")
                    .foregroundColor(.blue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            Spacer()
        }
        .background(Color.black)
        .onDisappear {
            os_log(.info, "MonthPickerSheet geschlossen")
        }
    }
}

// Sub-View für das Transaktions-Sheet
struct TransactionSheet: View {
    let transactionsTitle: String
    let transactions: [Transaction]
    @Binding var isPresented: Bool
    @Binding var showTransactionsSheet: Bool

    // DateFormatter für das Datum
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(transactionsTitle)
                        .foregroundColor(.white)
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        isPresented = false
                        showTransactionsSheet = false
                    }) {
                        Text("Schließen")
                            .foregroundColor(.blue)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(10)
                    }
                }
                .padding()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(transactions, id: \.self) { tx in
                            VStack(alignment: .leading, spacing: 8) {
                                // Datum
                                HStack {
                                    Text("Datum:")
                                        .foregroundColor(.gray)
                                    Text(dateFormatter.string(from: tx.date))
                                        .foregroundColor(.white)
                                }

                                // Betrag
                                HStack {
                                    Text("Betrag:")
                                        .foregroundColor(.gray)
                                    Text(String(format: "%.2f EUR", tx.amount))
                                        .foregroundColor(tx.amount >= 0 ? .green : .red)
                                }

                                // Kategorie
                                HStack {
                                    Text("Kategorie:")
                                        .foregroundColor(.gray)
                                    Text(tx.categoryRelationship?.name ?? "Unbekannt")
                                        .foregroundColor(.white)
                                }

                                // Verwendungszweck
                                HStack {
                                    Text("Verwendungszweck:")
                                        .foregroundColor(.gray)
                                    Text(tx.usage ?? "Unbekannt")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding()
                            Divider().background(Color.gray)
                        }
                    }
                }
                .background(Color.black)
            }
            .background(Color.black)
            .onAppear {
                print("TransactionSheet angezeigt mit Titel: \(transactionsTitle), \(transactions.count) Einträge")
            }
        }
    }
}

// Struktur für Segment-Daten, internal für Zugriff in CategoryChartView, UsageChartView und OverlayAnnotationsView
struct SegmentData: Identifiable {
    let id: UUID
    let name: String
    let value: Double
    let startAngle: Double
    let endAngle: Double
}

// Sub-View für den Pfeil
struct ArrowView: View {
    let points: [CGPoint]
    
    var body: some View {
        Path { path in
            path.move(to: points[0])
            path.addLine(to: points[1])
            path.addLine(to: points[2])
            path.move(to: points[3])
            path.addLine(to: points[4])
        }
        .stroke(.white, lineWidth: 1)
    }
}

// Sub-View für die Beschriftung
struct LabelView: View {
    let name: String
    let position: CGPoint
    
    var body: some View {
        Text(name)
            .foregroundColor(.white)
            .font(.caption)
            .position(x: position.x, y: position.y)
    }
}

// Sub-View für einzelne Annotationen (Pfeil und Beschriftung)
struct AnnotationView: View {
    let segment: SegmentData
    let arrowStart: CGPoint
    let arrowEnd: CGPoint
    let labelPosition: CGPoint
    let midAngle: CGFloat
    let arrowLength: CGFloat
    let angleOffset: CGFloat

    var body: some View {
        Group {
            ArrowView(points: computeArrowPoints())
            LabelView(name: segment.name, position: labelPosition)
        }
    }

    private func computeArrowPoints() -> [CGPoint] {
        // Pfeilanfang und -ende bleiben unverändert
        let p1 = arrowStart
        let p2 = arrowEnd

        // 1. Winkel- und trigonometrische Berechnung für das erste Segment
        let anglePlus  = Double(midAngle + angleOffset)       // CGFloat -> Double
        let cosPlus    = CGFloat(cos(anglePlus))              // Double -> CGFloat
        let sinPlus    = CGFloat(sin(anglePlus))              // Double -> CGFloat
        let dxPlus     = arrowLength * cosPlus
        let dyPlus     = arrowLength * sinPlus
        let p3 = CGPoint(
            x: arrowEnd.x - dxPlus,
            y: arrowEnd.y - dyPlus
        )

        // 2. Winkel- und trigonometrische Berechnung für das zweite Segment
        let angleMinus = Double(midAngle - angleOffset)
        let cosMinus   = CGFloat(cos(angleMinus))
        let sinMinus   = CGFloat(sin(angleMinus))
        let dxMinus    = arrowLength * cosMinus
        let dyMinus    = arrowLength * sinMinus
        let p5 = CGPoint(
            x: arrowEnd.x - dxMinus,
            y: arrowEnd.y - dyMinus
        )

        return [p1, p2, p3, p2, p5]
    }
}

// Sub-View für Pie-Chart-Beschriftungen und Pfeile
struct OverlayAnnotationsView: View {
    let segments: [SegmentData]
    let geometry: GeometryProxy

    var body: some View {
        ForEach(segments, id: \.id) { segment in
            let (arrowStart, arrowEnd, labelPosition, midAngle) = computeAnnotationPositions(segment: segment, geometry: geometry)
            AnnotationView(
                segment: segment,
                arrowStart: arrowStart,
                arrowEnd: arrowEnd,
                labelPosition: labelPosition,
                midAngle: midAngle,
                arrowLength: 5,
                angleOffset: .pi / 6
            )
        }
    }

    private func computeAnnotationPositions(segment: SegmentData, geometry: GeometryProxy) -> (CGPoint, CGPoint, CGPoint, CGFloat) {
        let midAngle = segment.startAngle + (segment.endAngle - segment.startAngle) / 2
        let outerRadius = min(geometry.size.width, geometry.size.height) / 2
        let labelRadius = outerRadius * 1.1 // Reduzierter Abstand für Beschriftungen
        
        // Typkonvertierungen für trigonometrische Berechnungen
        let angle = Double(midAngle)
        let cosAngle = CGFloat(cos(angle))
        let sinAngle = CGFloat(sin(angle))
        
        let arrowStart = CGPoint(
            x: geometry.size.width / 2 + cosAngle * outerRadius * 0.8,
            y: geometry.size.height / 2 + sinAngle * outerRadius * 0.8
        )
        let arrowEnd = CGPoint(
            x: geometry.size.width / 2 + cosAngle * labelRadius,
            y: geometry.size.height / 2 + sinAngle * labelRadius
        )
        
        // Berechne die vorläufige Beschriftungsposition
        var labelPosition = CGPoint(
            x: geometry.size.width / 2 + cosAngle * (labelRadius + 10), // Reduzierter zusätzlicher Abstand
            y: geometry.size.height / 2 + sinAngle * (labelRadius + 10)
        )
        
        // Begrenze die Beschriftungsposition auf den sichtbaren Bereich
        let padding: CGFloat = 20
        let minX = padding
        let maxX = geometry.size.width - padding
        let minY = padding
        let maxY = geometry.size.height - padding
        
        labelPosition.x = min(max(labelPosition.x, minX), maxX)
        labelPosition.y = min(max(labelPosition.y, minY), maxY)
        
        return (arrowStart, arrowEnd, labelPosition, CGFloat(midAngle))
    }
}

// Unterkomponente für das Kategorien-Diagramm
struct CategoryChartView: View {
    let data: [EvaluationView.CategoryData]
    @Binding var selectedData: EvaluationView.CategoryData?
    let totalExpenses: Double
    let showTransactions: ([Transaction], String) -> Void

    private func colorForValue(_ value: Double) -> Color {
        value >= 0 ? .green : .red
    }

    var body: some View {
        VStack {
            Text("Ausgaben nach Kategorie: \(String(format: "%.2f €", totalExpenses))")
                .foregroundColor(colorForValue(totalExpenses))
                .font(.caption)
                .padding(.horizontal)
            GeometryReader { geometry in
                ZStack {
                    PieChartContent(
                        data: data,
                        selectedData: $selectedData,
                        geometry: geometry,
                        showTransactions: showTransactions
                    )
                    OverlayAnnotationsView(
                        segments: computeSegments(),
                        geometry: geometry
                    )
                }
            }
            .frame(height: 400)
            if let selected = selectedData {
                Text("\(selected.name): \(String(format: "%.2f €", selected.value))")
                    .foregroundColor(colorForValue(selected.value))
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }

    private func computeSegments() -> [SegmentData] {
        let totalValue = data.reduce(0.0) { $0 + abs($1.value) }
        var cumulativeAngle: Double = -.pi / 2 // Start bei 12 Uhr
        return data.sorted { abs($0.value) > abs($1.value) }
            .prefix(3)
            .filter { abs($0.value) / totalValue > 0.1 }
            .map { datum in
                let proportion = abs(datum.value) / totalValue
                let angle = proportion * 2 * .pi
                let startAngle = cumulativeAngle
                let endAngle = cumulativeAngle + angle
                cumulativeAngle += angle
                return SegmentData(
                    id: datum.id,
                    name: datum.name,
                    value: datum.value,
                    startAngle: startAngle,
                    endAngle: endAngle
                )
            }
    }
}

// Sub-View für den Pie-Chart-Inhalt
struct PieChartContent: View {
    let data: [EvaluationView.CategoryData]
    @Binding var selectedData: EvaluationView.CategoryData?
    let geometry: GeometryProxy
    let showTransactions: ([Transaction], String) -> Void

    var body: some View {
        Chart(data) { datum in
            SectorMark(
                angle: .value("Wert", abs(datum.value)),
                innerRadius: .ratio(0.5),
                angularInset: 0.5
            )
            .foregroundStyle(datum.color)
            .cornerRadius(5)
            .opacity(selectedData == nil || selectedData?.id == datum.id ? 1.0 : 0.3)
        }
        .chartLegend(position: .bottom, alignment: .center, spacing: 10)
        .chartLegend(.visible)
        .frame(height: 350)
        .padding(.horizontal)
        .onTapGesture { location in
            let chartFrame = CGRect(x: 0, y: 0, width: geometry.size.width, height: 350)
            let (selected, _) = chartDataAtLocation(location: location, in: data, chartFrame: chartFrame)
            if let selected = selected {
                os_log(.info, "Selected category: %@ with value %.2f", selected.name, selected.value)
                selectedData = selected
                showTransactions(selected.transactions, "Transaktionen für Kategorie: \(selected.name)")
            } else {
                os_log(.info, "No category selected at location: (%f, %f)", location.x, location.y)
                selectedData = nil
            }
        }
    }

    private func chartDataAtLocation(location: CGPoint, in data: [EvaluationView.CategoryData], chartFrame: CGRect) -> (EvaluationView.CategoryData?, CGPoint?) {
        let center = CGPoint(x: chartFrame.midX, y: chartFrame.midY)
        let outerRadius = min(chartFrame.width, chartFrame.height) / 2
        let innerRadius = outerRadius * 0.5
        let distance = sqrt(pow(location.x - center.x, 2) + pow(location.y - center.y, 2))

        if distance <= outerRadius && distance >= innerRadius {
            let angle = atan2(location.y - center.y, location.x - center.x) + .pi / 2
            var normalizedAngle = angle < 0 ? angle + 2 * .pi : angle

            normalizedAngle = normalizedAngle < 0 ? normalizedAngle + 2 * .pi : normalizedAngle

            let totalValue = data.reduce(0.0) { $0 + abs($1.value) }
            let angularInset: Double = 0.5 * .pi / 180
            var cumulativeAngle: Double = 0

            // Verwende die gleiche Sortierung und Filterung wie in computeSegments
            let filteredData = data.sorted { abs($0.value) > abs($1.value) }
                .prefix(3)
                .filter { abs($0.value) / totalValue > 0.1 }

            for datum in filteredData {
                let segmentAngle = (abs(datum.value) / totalValue) * 2 * .pi - angularInset
                let startAngle = cumulativeAngle
                let endAngle = cumulativeAngle + segmentAngle

                os_log(.info, "Category: %@", datum.name)
                os_log(.info, "Value: %.2f", datum.value)
                os_log(.info, "Segment Angle: %.2f", segmentAngle)
                os_log(.info, "Cumulative Angle: %.2f to %.2f", startAngle, endAngle)

                if normalizedAngle >= startAngle && normalizedAngle <= endAngle {
                    return (datum, location)
                }
                cumulativeAngle += segmentAngle + angularInset
            }
            os_log(.info, "Normalized angle: %.2f not found in any segment", normalizedAngle)
        } else {
            os_log(.info, "Click outside chart radius: %.2f (inner: %.2f, outer: %.2f)", distance, innerRadius, outerRadius)
        }
        return (nil, nil)
    }
}

// Unterkomponente für das Verwendungszweck-Diagramm
struct UsageChartView: View {
    let data: [EvaluationView.CategoryData]
    @Binding var selectedData: EvaluationView.CategoryData?
    let totalExpenses: Double
    let showTransactions: ([Transaction], String) -> Void

    private func colorForValue(_ value: Double) -> Color {
        value >= 0 ? .green : .red
    }

    var body: some View {
        VStack {
            Text("Ausgaben nach V-Zweck: \(String(format: "%.2f €", totalExpenses))")
                .foregroundColor(colorForValue(totalExpenses))
                .font(.caption)
                .padding(.horizontal)
            GeometryReader { geometry in
                ZStack {
                    PieChartContent(
                        data: data,
                        selectedData: $selectedData,
                        geometry: geometry,
                        showTransactions: showTransactions
                    )
                    OverlayAnnotationsView(
                        segments: computeSegments(),
                        geometry: geometry
                    )
                }
            }
            .frame(height: 400)
            if let selected = selectedData {
                Text("\(selected.name): \(String(format: "%.2f €", selected.value))")
                    .foregroundColor(colorForValue(selected.value))
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }

    private func computeSegments() -> [SegmentData] {
        let totalValue = data.reduce(0.0) { $0 + abs($1.value) }
        var cumulativeAngle: Double = -.pi / 2 // Start bei 12 Uhr
        return data.sorted { abs($0.value) > abs($1.value) }
            .prefix(3)
            .filter { abs($0.value) / totalValue > 0.1 }
            .map { datum in
                let proportion = abs(datum.value) / totalValue
                let angle = proportion * 2 * .pi
                let startAngle = cumulativeAngle
                let endAngle = cumulativeAngle + angle
                cumulativeAngle += angle
                return SegmentData(
                    id: datum.id,
                    name: datum.name,
                    value: datum.value,
                    startAngle: startAngle,
                    endAngle: endAngle
                )
            }
    }
}

// Sub-View für das Prognose-Diagramm
struct ForecastChartView: View {
    let forecastData: [EvaluationView.ForecastData]
    let monthlyData: EvaluationView.MonthlyData?
    @Binding var transactionsTitle: String
    @Binding var transactionsToShow: [Transaction]
    @Binding var showTransactionsSheet: Bool

    private func colorForValue(_ value: Double) -> Color {
        value >= 0 ? .green : .red
    }

    private func barHeight(for value: Double, scaleFactor: CGFloat) -> CGFloat {
        CGFloat(abs(value)) * scaleFactor
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Prognostizierter Kontostand am Monatsende")
                .foregroundColor(.white)
                .font(.caption)
                .padding(.horizontal)
            if let forecast = forecastData.first {
                let maxValue = max(abs(forecast.einnahmen), abs(forecast.ausgaben), abs(forecast.balance))
                let maxHeight: CGFloat = 150
                let scaleFactor = maxValue > 0 ? maxHeight / maxValue : 1.0

                HStack {
                    // Prognostizierte Einnahmen (grün)
                    VStack {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 100, height: barHeight(for: forecast.einnahmen, scaleFactor: scaleFactor))
                            .onTapGesture {
                                transactionsTitle = "Prognostizierte Einnahmen"
                                transactionsToShow = monthlyData?.incomeTransactions ?? []
                                os_log(.info, "Prognostizierte Einnahmen Transaktionen: %d Einträge", transactionsToShow.count)
                                showTransactionsSheet = true
                            }
                        Text("Einnahmen")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.top, 8)
                        Text(String(format: "%.2f €", forecast.einnahmen))
                            .foregroundColor(colorForValue(forecast.einnahmen))
                            .font(.caption)
                            .padding(.top, 4)
                    }
                    Spacer()
                    // Prognostizierte Ausgaben (rot)
                    VStack {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 100, height: barHeight(for: forecast.ausgaben, scaleFactor: scaleFactor))
                            .onTapGesture {
                                transactionsTitle = "Prognostizierte Ausgaben"
                                transactionsToShow = monthlyData?.expenseTransactions ?? []
                                os_log(.info, "Prognostizierte Ausgaben Transaktionen: %d Einträge", transactionsToShow.count)
                                showTransactionsSheet = true
                            }
                        Text("Ausgaben")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.top, 8)
                        Text(String(format: "%.2f €", forecast.ausgaben))
                            .foregroundColor(colorForValue(forecast.ausgaben))
                            .font(.caption)
                            .padding(.top, 4)
                    }
                    Spacer()
                    // Prognostizierter Kontostand (gelb)
                    VStack {
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: 100, height: barHeight(for: forecast.balance, scaleFactor: scaleFactor))
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
                .frame(height: 200)
            }
        }
    }
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
