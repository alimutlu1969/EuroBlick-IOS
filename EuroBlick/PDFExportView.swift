import SwiftUI
import UIKit

struct PDFExportView: View {
    let accounts: [Account]
    @ObservedObject var viewModel: TransactionViewModel
    
    @State private var selectedMonth: String
    @State private var showMonthPickerSheet = false
    @State private var showCustomDateRangeSheet = false
    @State private var customDateRange: (start: Date, end: Date)?
    @State private var monthlyData: [MonthlyData] = []
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    @State private var isGeneratingPDF = false
    @State private var selectedReportTypes: Set<ReportType> = [.incomeExpense, .incomeByCategory, .expenseByCategory, .balanceHistory]
    
    enum ReportType: String, CaseIterable {
        case incomeExpense = "Einnahmen/Ausgaben"
        case incomeByCategory = "Einnahmen nach Kategorie"
        case expenseByCategory = "Ausgaben nach Kategorie"
        case balanceHistory = "Kontosaldenverlauf"
        case forecast = "Prognose"
        
        var icon: String {
            switch self {
            case .incomeExpense: return "chart.bar.fill"
            case .incomeByCategory: return "chart.pie.fill"
            case .expenseByCategory: return "chart.pie.fill"
            case .balanceHistory: return "chart.line.uptrend.xyaxis"
            case .forecast: return "chart.line.uptrend.xyaxis.circle.fill"
            }
        }
    }
    
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
                        // Report-Typ-Auswahl
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Berichte auswählen")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            ForEach(ReportType.allCases, id: \.self) { reportType in
                                HStack {
                                    Image(systemName: reportType.icon)
                                        .foregroundColor(.blue)
                                        .frame(width: 30)
                                    
                                    Text(reportType.rawValue)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Image(systemName: selectedReportTypes.contains(reportType) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedReportTypes.contains(reportType) ? .blue : .gray)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                                .onTapGesture {
                                    if selectedReportTypes.contains(reportType) {
                                        selectedReportTypes.remove(reportType)
                                    } else {
                                        selectedReportTypes.insert(reportType)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                        
                        // Export Button
                        Button(action: {
                            generatePDF()
                        }) {
                            HStack {
                                if isGeneratingPDF {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                Text(isGeneratingPDF ? "PDF wird erstellt..." : "PDF erstellen & teilen")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedReportTypes.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(selectedReportTypes.isEmpty || isGeneratingPDF)
                        .padding(.horizontal)
                        
                        // Hinweis
                        Text("Das PDF enthält alle ausgewählten Berichte für den gewählten Zeitraum.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("PDF Export")
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
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(activityItems: [url])
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
    
    private func generatePDF() {
        isGeneratingPDF = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let pdfMetaData = [
                kCGPDFContextCreator: "EuroBlick",
                kCGPDFContextAuthor: "EuroBlick App",
                kCGPDFContextTitle: "Finanzbericht",
                kCGPDFContextSubject: "Finanzauswertung"
            ]
            
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = pdfMetaData as [String: Any]
            
            let pageWidth = 8.5 * 72.0
            let pageHeight = 11 * 72.0
            let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
            
            let data = renderer.pdfData { (context) in
                context.beginPage()
                
                var yPosition: CGFloat = 20
                
                // Titel
                let title = "Finanzbericht"
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 24),
                    .foregroundColor: UIColor.black
                ]
                let titleSize = title.size(withAttributes: titleAttributes)
                let titleRect = CGRect(x: (pageWidth - titleSize.width) / 2, y: yPosition, width: titleSize.width, height: titleSize.height)
                title.draw(in: titleRect, withAttributes: titleAttributes)
                
                yPosition += titleSize.height + 10
                
                // Zeitraum
                let dateRangeText = getDateRangeText()
                let dateAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.gray
                ]
                let dateSize = dateRangeText.size(withAttributes: dateAttributes)
                let dateRect = CGRect(x: (pageWidth - dateSize.width) / 2, y: yPosition, width: dateSize.width, height: dateSize.height)
                dateRangeText.draw(in: dateRect, withAttributes: dateAttributes)
                
                yPosition += dateSize.height + 20
                
                // Erstelle die ausgewählten Berichte
                if selectedReportTypes.contains(.incomeExpense) {
                    yPosition = drawIncomeExpenseReport(context: context, yPosition: yPosition, pageWidth: pageWidth)
                }
                
                if selectedReportTypes.contains(.incomeByCategory) {
                    if yPosition > pageHeight - 200 {
                        context.beginPage()
                        yPosition = 20
                    }
                    yPosition = drawCategoryReport(context: context, yPosition: yPosition, pageWidth: pageWidth, isIncome: true)
                }
                
                if selectedReportTypes.contains(.expenseByCategory) {
                    if yPosition > pageHeight - 200 {
                        context.beginPage()
                        yPosition = 20
                    }
                    yPosition = drawCategoryReport(context: context, yPosition: yPosition, pageWidth: pageWidth, isIncome: false)
                }
                
                if selectedReportTypes.contains(.balanceHistory) {
                    if yPosition > pageHeight - 200 {
                        context.beginPage()
                        yPosition = 20
                    }
                    yPosition = drawBalanceHistory(context: context, yPosition: yPosition, pageWidth: pageWidth)
                }
                
                if selectedReportTypes.contains(.forecast) {
                    if yPosition > pageHeight - 200 {
                        context.beginPage()
                        yPosition = 20
                    }
                    yPosition = drawForecast(context: context, yPosition: yPosition, pageWidth: pageWidth)
                }
            }
            
            // Speichere PDF
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "Finanzbericht_\(Date().timeIntervalSince1970).pdf"
            let url = documentsPath.appendingPathComponent(fileName)
            
            do {
                try data.write(to: url)
                DispatchQueue.main.async {
                    self.pdfURL = url
                    self.isGeneratingPDF = false
                    self.showShareSheet = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGeneratingPDF = false
                    print("Fehler beim Speichern der PDF: \(error)")
                }
            }
        }
    }
    
    private func getDateRangeText() -> String {
        if selectedMonth == "Alle Monate" {
            return "Zeitraum: Alle Monate"
        } else if selectedMonth == "Benutzerdefinierter Zeitraum", let range = customDateRange {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy"
            return "Zeitraum: \(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
        } else {
            return "Zeitraum: \(selectedMonth)"
        }
    }
    
    private func drawIncomeExpenseReport(context: UIGraphicsPDFRendererContext, yPosition: CGFloat, pageWidth: CGFloat) -> CGFloat {
        var y = yPosition
        
        // Überschrift
        let sectionTitle = "Einnahmen / Ausgaben"
        let sectionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        sectionTitle.draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttributes)
        y += 30
        
        // Tabelle
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        let totalIncome = monthlyData.reduce(0) { $0 + $1.income }
        let totalExpenses = monthlyData.reduce(0) { $0 + $1.expenses }
        let totalSurplus = totalIncome - totalExpenses
        
        // Zeichne Tabelle
        let labels = ["Einnahmen:", "Ausgaben:", "Überschuss:"]
        let values = [formatAmount(totalIncome), formatAmount(totalExpenses), formatAmount(totalSurplus)]
        let colors = [UIColor.systemGreen, UIColor.systemRed, totalSurplus >= 0 ? UIColor.systemGreen : UIColor.systemRed]
        
        for (index, label) in labels.enumerated() {
            label.draw(at: CGPoint(x: 40, y: y), withAttributes: textAttributes)
            
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: colors[index]
            ]
            let valueSize = values[index].size(withAttributes: valueAttributes)
            values[index].draw(at: CGPoint(x: pageWidth - 40 - valueSize.width, y: y), withAttributes: valueAttributes)
            
            y += 20
        }
        
        y += 20
        return y
    }
    
    private func drawCategoryReport(context: UIGraphicsPDFRendererContext, yPosition: CGFloat, pageWidth: CGFloat, isIncome: Bool) -> CGFloat {
        var y = yPosition
        
        // Überschrift
        let sectionTitle = isIncome ? "Einnahmen nach Kategorie" : "Ausgaben nach Kategorie"
        let sectionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        sectionTitle.draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttributes)
        y += 30
        
        // Berechne Kategoriedaten
        let transactions = monthlyData.flatMap { isIncome ? $0.incomeTransactions : $0.expenseTransactions }
        let grouped = Dictionary(grouping: transactions, by: { $0.categoryRelationship?.name ?? "Unbekannt" })
        let categoryData = grouped.map { (category, txs) in
            (category: category, value: txs.reduce(0) { $0 + abs($1.amount) })
        }.sorted { $0.value > $1.value }
        
        let total = categoryData.reduce(0) { $0 + $1.value }
        
        // Zeichne Kategorien
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        for data in categoryData {
            let percentage = total > 0 ? (data.value / total * 100) : 0
            let categoryText = "\(data.category) (\(String(format: "%.1f", percentage))%)"
            categoryText.draw(at: CGPoint(x: 40, y: y), withAttributes: textAttributes)
            
            let valueText = formatAmount(data.value)
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: isIncome ? UIColor.systemGreen : UIColor.systemRed
            ]
            let valueSize = valueText.size(withAttributes: valueAttributes)
            valueText.draw(at: CGPoint(x: pageWidth - 40 - valueSize.width, y: y), withAttributes: valueAttributes)
            
            y += 20
        }
        
        y += 20
        return y
    }
    
    private func drawBalanceHistory(context: UIGraphicsPDFRendererContext, yPosition: CGFloat, pageWidth: CGFloat) -> CGFloat {
        var y = yPosition
        
        // Überschrift
        let sectionTitle = "Kontosaldenverlauf"
        let sectionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        sectionTitle.draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttributes)
        y += 30
        
        // Berechne Saldenverlauf
        for account in accounts {
            let accountName = account.name ?? "Unbekannt"
            let currentBalance = viewModel.getBalance(for: account)
            
            let accountAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.black
            ]
            accountName.draw(at: CGPoint(x: 40, y: y), withAttributes: accountAttributes)
            y += 20
            
            let balanceText = "Aktueller Saldo: \(formatAmount(currentBalance))"
            let balanceAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: currentBalance >= 0 ? UIColor.systemGreen : UIColor.systemRed
            ]
            balanceText.draw(at: CGPoint(x: 60, y: y), withAttributes: balanceAttributes)
            y += 25
        }
        
        y += 20
        return y
    }
    
    private func drawForecast(context: UIGraphicsPDFRendererContext, yPosition: CGFloat, pageWidth: CGFloat) -> CGFloat {
        var y = yPosition
        
        // Überschrift
        let sectionTitle = "Prognose"
        let sectionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        sectionTitle.draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttributes)
        y += 30
        
        // Berechne Durchschnittswerte
        let avgIncome = monthlyData.isEmpty ? 0 : monthlyData.reduce(0) { $0 + $1.income } / Double(monthlyData.count)
        let avgExpenses = monthlyData.isEmpty ? 0 : monthlyData.reduce(0) { $0 + $1.expenses } / Double(monthlyData.count)
        let avgSurplus = avgIncome - avgExpenses
        
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        "Durchschnittliche monatliche Einnahmen:".draw(at: CGPoint(x: 40, y: y), withAttributes: textAttributes)
        formatAmount(avgIncome).draw(at: CGPoint(x: pageWidth - 140, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.systemGreen
        ])
        y += 20
        
        "Durchschnittliche monatliche Ausgaben:".draw(at: CGPoint(x: 40, y: y), withAttributes: textAttributes)
        formatAmount(avgExpenses).draw(at: CGPoint(x: pageWidth - 140, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.systemRed
        ])
        y += 20
        
        "Durchschnittlicher monatlicher Überschuss:".draw(at: CGPoint(x: 40, y: y), withAttributes: textAttributes)
        formatAmount(avgSurplus).draw(at: CGPoint(x: pageWidth - 140, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: avgSurplus >= 0 ? UIColor.systemGreen : UIColor.systemRed
        ])
        y += 20
        
        y += 20
        return y
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

// Share Sheet für iPad und iPhone
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let vm = TransactionViewModel(context: ctx)
    let acc = Account(context: ctx)
    acc.name = "Test"
    return NavigationStack {
        PDFExportView(accounts: [acc], viewModel: vm)
    }
} 