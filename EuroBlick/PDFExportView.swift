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
    
    private var availableMonths: [String] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "MMM yyyy"
        
        let allTx = accounts.flatMap { $0.transactions?.allObjects as? [Transaction] ?? [] }
        let months = Set(allTx.map { fmt.string(from: $0.date) })
        
        return ["Alle Monate", "Benutzerdefinierter Zeitraum"] + months.sorted()
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
                var currentPage = 1
                
                // Cover Page
                context.beginPage()
                self.drawCoverPage(context: context, pageWidth: pageWidth, pageHeight: pageHeight)
                
                // Finance Overview
                if self.selectedReportTypes.contains(.incomeExpense) {
                    context.beginPage()
                    currentPage += 1
                    self.drawFinanceOverviewPage(context: context, pageWidth: pageWidth, pageHeight: pageHeight, pageNumber: currentPage)
                }
                
                // Income Categories
                if self.selectedReportTypes.contains(.incomeByCategory) {
                    context.beginPage()
                    currentPage += 1
                    self.drawCategoriesPage(context: context, pageWidth: pageWidth, pageHeight: pageHeight, isIncome: true, pageNumber: currentPage)
                }
                
                // Expense Categories
                if self.selectedReportTypes.contains(.expenseByCategory) {
                    context.beginPage()
                    currentPage += 1
                    self.drawCategoriesPage(context: context, pageWidth: pageWidth, pageHeight: pageHeight, isIncome: false, pageNumber: currentPage)
                }
                
                // Balance History Chart
                if self.selectedReportTypes.contains(.balanceHistory) {
                    context.beginPage()
                    currentPage += 1
                    self.drawBalanceHistoryPage(context: context, pageWidth: pageWidth, pageHeight: pageHeight, pageNumber: currentPage)
                }
                
                // Forecast
                if self.selectedReportTypes.contains(.forecast) {
                    context.beginPage()
                    currentPage += 1
                    self.drawForecastPage(context: context, pageWidth: pageWidth, pageHeight: pageHeight, pageNumber: currentPage)
                }
            }
            
            // Save PDF
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
    
    private func drawCoverPage(context: UIGraphicsPDFRendererContext, pageWidth: CGFloat, pageHeight: CGFloat) {
        // Dark header background
        let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 120)
        UIColor.black.setFill()
        context.cgContext.fill(headerRect)
        
        // Title
        let title = "Finanzbericht"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 36),
            .foregroundColor: UIColor.white
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = CGRect(x: (pageWidth - titleSize.width) / 2, y: 40, width: titleSize.width, height: titleSize.height)
        title.draw(in: titleRect, withAttributes: titleAttributes)
        
        // Date range
        let dateRangeText = getDateRangeText()
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.white
        ]
        let dateSize = dateRangeText.size(withAttributes: dateAttributes)
        let dateRect = CGRect(x: (pageWidth - dateSize.width) / 2, y: 90, width: dateSize.width, height: dateSize.height)
        dateRangeText.draw(in: dateRect, withAttributes: dateAttributes)
        
        // Content
        var yPosition: CGFloat = 160
        
        // Report types
        let reportTitle = "Enthaltene Berichte:"
        let reportTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        reportTitle.draw(at: CGPoint(x: 40, y: yPosition), withAttributes: reportTitleAttributes)
        yPosition += 30
        
        let reportAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.black
        ]
        
        for reportType in selectedReportTypes.sorted(by: { $0.rawValue < $1.rawValue }) {
            let bulletPoint = "•"
            bulletPoint.draw(at: CGPoint(x: 40, y: yPosition), withAttributes: reportAttributes)
            reportType.rawValue.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: reportAttributes)
            yPosition += 25
        }
        
        // Footer
        let footerText = "Erstellt mit EuroBlick"
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.gray
        ]
        let footerSize = footerText.size(withAttributes: footerAttributes)
        let footerRect = CGRect(x: (pageWidth - footerSize.width) / 2, y: pageHeight - 40, width: footerSize.width, height: footerSize.height)
        footerText.draw(in: footerRect, withAttributes: footerAttributes)
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
    
    private func drawFinanceOverviewPage(context: UIGraphicsPDFRendererContext, pageWidth: CGFloat, pageHeight: CGFloat, pageNumber: Int) {
        // Dark header background
        let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 80)
        UIColor.black.setFill()
        context.cgContext.fill(headerRect)
        
        // Title
        let title = "Finanzübersicht"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.white
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = CGRect(x: (pageWidth - titleSize.width) / 2, y: 25, width: titleSize.width, height: titleSize.height)
        title.draw(in: titleRect, withAttributes: titleAttributes)
        
        // Page number
        let pageText = "Seite \(pageNumber)"
        let pageAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.gray
        ]
        let pageSize = pageText.size(withAttributes: pageAttributes)
        let pageRect = CGRect(x: pageWidth - pageSize.width - 20, y: pageHeight - 30, width: pageSize.width, height: pageSize.height)
        pageText.draw(in: pageRect, withAttributes: pageAttributes)
        
        var yPosition: CGFloat = 100
        
        // Summary box
        let boxRect = CGRect(x: 40, y: yPosition, width: pageWidth - 80, height: 120)
        UIColor.systemGray6.setFill()
        context.cgContext.fill(boxRect)
        
        // Draw border
        context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
        context.cgContext.setLineWidth(1)
        context.cgContext.stroke(boxRect)
        
        // Calculate totals
        let totalIncome = monthlyData.reduce(0) { $0 + $1.income }
        let totalExpenses = monthlyData.reduce(0) { $0 + $1.expenses }
        let totalSurplus = totalIncome - totalExpenses
        
        // Draw summary content
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.black
        ]
        
        let labels = ["Gesamteinnahmen:", "Gesamtausgaben:", "Gesamtüberschuss:"]
        let values = [totalIncome, totalExpenses, totalSurplus]
        let colors = [UIColor.systemGreen, UIColor.systemRed, totalSurplus >= 0 ? UIColor.systemGreen : UIColor.systemRed]
        
        for (index, label) in labels.enumerated() {
            label.draw(at: CGPoint(x: 60, y: yPosition + 20 + CGFloat(index * 30)), withAttributes: summaryAttributes)
            
            let valueText = formatAmount(values[index])
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: colors[index]
            ]
            let valueSize = valueText.size(withAttributes: valueAttributes)
            valueText.draw(at: CGPoint(x: boxRect.maxX - valueSize.width - 20, y: yPosition + 20 + CGFloat(index * 30)), withAttributes: valueAttributes)
        }
        
        yPosition += 140
        
        // Monthly breakdown
        let breakdownTitle = "Monatliche Aufschlüsselung"
        let breakdownAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        breakdownTitle.draw(at: CGPoint(x: 40, y: yPosition), withAttributes: breakdownAttributes)
        yPosition += 30
        
        // Table header
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        let columns = ["Monat", "Einnahmen", "Ausgaben", "Überschuss"]
        let columnWidths: [CGFloat] = [120, 100, 100, 100]
        var xPosition: CGFloat = 40
        
        for (index, column) in columns.enumerated() {
            column.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: headerAttributes)
            xPosition += columnWidths[index]
        }
        
        yPosition += 20
        
        // Draw separator line
        context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
        context.cgContext.setLineWidth(1)
        context.cgContext.move(to: CGPoint(x: 40, y: yPosition))
        context.cgContext.addLine(to: CGPoint(x: pageWidth - 40, y: yPosition))
        context.cgContext.strokePath()
        
        yPosition += 10
        
        // Table rows
        let rowAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        for data in monthlyData {
            xPosition = 40
            
            // Month
            data.month.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: rowAttributes)
            xPosition += columnWidths[0]
            
            // Income
            let incomeText = formatAmount(data.income)
            let incomeAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.systemGreen
            ]
            incomeText.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: incomeAttributes)
            xPosition += columnWidths[1]
            
            // Expenses
            let expenseText = formatAmount(data.expenses)
            let expenseAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.systemRed
            ]
            expenseText.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: expenseAttributes)
            xPosition += columnWidths[2]
            
            // Surplus
            let surplusText = formatAmount(data.surplus)
            let surplusAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: data.surplus >= 0 ? UIColor.systemGreen : UIColor.systemRed
            ]
            surplusText.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: surplusAttributes)
            
            yPosition += 25
        }
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
    
    private func drawCategoriesPage(context: UIGraphicsPDFRendererContext, pageWidth: CGFloat, pageHeight: CGFloat, isIncome: Bool, pageNumber: Int) {
        // Dark header background
        let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 80)
        UIColor.black.setFill()
        context.cgContext.fill(headerRect)
        
        // Title
        let title = isIncome ? "Einnahmen nach Kategorie" : "Ausgaben nach Kategorie"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.white
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = CGRect(x: (pageWidth - titleSize.width) / 2, y: 25, width: titleSize.width, height: titleSize.height)
        title.draw(in: titleRect, withAttributes: titleAttributes)
        
        // Page number
        let pageText = "Seite \(pageNumber)"
        let pageAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.gray
        ]
        let pageSize = pageText.size(withAttributes: pageAttributes)
        let pageRect = CGRect(x: pageWidth - pageSize.width - 20, y: pageHeight - 30, width: pageSize.width, height: pageSize.height)
        pageText.draw(in: pageRect, withAttributes: pageAttributes)
        
        var yPosition: CGFloat = 100
        
        // Calculate category data
        let transactions = monthlyData.flatMap { isIncome ? $0.incomeTransactions : $0.expenseTransactions }
        let grouped = Dictionary(grouping: transactions, by: { $0.categoryRelationship?.name ?? "Unbekannt" })
        let categoryData = grouped.map { (category, txs) in
            (category: category, value: txs.reduce(0) { $0 + abs($1.amount) })
        }.sorted { $0.value > $1.value }
        
        let total = categoryData.reduce(0) { $0 + $1.value }
        
        // Draw pie chart
        let chartSize: CGFloat = 200
        let chartRect = CGRect(x: (pageWidth - chartSize) / 2, y: yPosition, width: chartSize, height: chartSize)
        
        // Draw pie chart background
        UIColor.systemGray6.setFill()
        context.cgContext.fill(chartRect)
        
        // Draw pie chart
        let center = CGPoint(x: chartRect.midX, y: chartRect.midY)
        let radius = chartSize / 2 - 10
        
        var startAngle: CGFloat = -.pi / 2
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemPink, .systemTeal, .systemIndigo]
        
        for (index, data) in categoryData.enumerated() {
            let percentage = data.value / total
            let endAngle = startAngle + (2 * .pi * percentage)
            
            let path = UIBezierPath()
            path.move(to: center)
            path.addArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            path.close()
            
            colors[index % colors.count].setFill()
            path.fill()
            
            // Draw border
            UIColor.white.setStroke()
            path.lineWidth = 1
            path.stroke()
            
            startAngle = endAngle
        }
        
        yPosition += chartSize + 40
        
        // Draw legend
        let legendTitle = "Kategorieaufschlüsselung"
        let legendTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        legendTitle.draw(at: CGPoint(x: 40, y: yPosition), withAttributes: legendTitleAttributes)
        yPosition += 30
        
        // Table header
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        let columns = ["Kategorie", "Betrag", "Anteil"]
        let columnWidths: [CGFloat] = [200, 120, 100]
        var xPosition: CGFloat = 40
        
        for (index, column) in columns.enumerated() {
            column.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: headerAttributes)
            xPosition += columnWidths[index]
        }
        
        yPosition += 20
        
        // Draw separator line
        context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
        context.cgContext.setLineWidth(1)
        context.cgContext.move(to: CGPoint(x: 40, y: yPosition))
        context.cgContext.addLine(to: CGPoint(x: pageWidth - 40, y: yPosition))
        context.cgContext.strokePath()
        
        yPosition += 10
        
        // Table rows
        let rowAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        for (index, data) in categoryData.enumerated() {
            xPosition = 40
            
            // Category with color indicator
            let color = colors[index % colors.count]
            let colorRect = CGRect(x: xPosition, y: yPosition + 4, width: 8, height: 8)
            color.setFill()
            context.cgContext.fill(colorRect)
            
            data.category.draw(at: CGPoint(x: xPosition + 20, y: yPosition), withAttributes: rowAttributes)
            xPosition += columnWidths[0]
            
            // Amount
            let amountText = formatAmount(data.value)
            let amountAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: isIncome ? UIColor.systemGreen : UIColor.systemRed
            ]
            amountText.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: amountAttributes)
            xPosition += columnWidths[1]
            
            // Percentage
            let percentage = (data.value / total * 100)
            let percentageText = String(format: "%.1f%%", percentage)
            percentageText.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: rowAttributes)
            
            yPosition += 25
        }
    }
    
    private func drawBalanceHistoryPage(context: UIGraphicsPDFRendererContext, pageWidth: CGFloat, pageHeight: CGFloat, pageNumber: Int) {
        // Dark header background
        let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 80)
        UIColor.black.setFill()
        context.cgContext.fill(headerRect)
        
        // Title
        let title = "Kontosaldenverlauf"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.white
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = CGRect(x: (pageWidth - titleSize.width) / 2, y: 25, width: titleSize.width, height: titleSize.height)
        title.draw(in: titleRect, withAttributes: titleAttributes)
        
        // Page number
        let pageText = "Seite \(pageNumber)"
        let pageAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.gray
        ]
        let pageSize = pageText.size(withAttributes: pageAttributes)
        let pageRect = CGRect(x: pageWidth - pageSize.width - 20, y: pageHeight - 30, width: pageSize.width, height: pageSize.height)
        pageText.draw(in: pageRect, withAttributes: pageAttributes)
        
        var yPosition: CGFloat = 100
        
        // Draw chart background
        let chartRect = CGRect(x: 40, y: yPosition, width: pageWidth - 80, height: 300)
        UIColor.systemGray6.setFill()
        context.cgContext.fill(chartRect)
        
        // Draw border
        context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
        context.cgContext.setLineWidth(1)
        context.cgContext.stroke(chartRect)
        
        // Calculate balance history
        let allTransactions = monthlyData.flatMap { $0.incomeTransactions + $0.expenseTransactions }
            .sorted { $0.date < $1.date }
        
        var runningBalance: Double = 0
        var balancePoints: [(date: Date, balance: Double)] = []
        
        for transaction in allTransactions {
            runningBalance += transaction.type == "einnahme" ? transaction.amount : -transaction.amount
            balancePoints.append((date: transaction.date, balance: runningBalance))
        }
        
        // Draw chart
        if !balancePoints.isEmpty {
            let minBalance = balancePoints.map { $0.balance }.min() ?? 0
            let maxBalance = balancePoints.map { $0.balance }.max() ?? 0
            let balanceRange = maxBalance - minBalance
            
            let xStep = (chartRect.width - 40) / CGFloat(balancePoints.count - 1)
            let yScale = (chartRect.height - 40) / CGFloat(balanceRange)
            
            // Draw grid lines
            context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
            context.cgContext.setLineWidth(0.5)
            
            // Horizontal grid lines
            let gridSteps = 5
            for i in 0...gridSteps {
                let y = chartRect.minY + 20 + CGFloat(i) * (chartRect.height - 40) / CGFloat(gridSteps)
                context.cgContext.move(to: CGPoint(x: chartRect.minX + 20, y: y))
                context.cgContext.addLine(to: CGPoint(x: chartRect.maxX - 20, y: y))
                
                // Draw value
                let value = maxBalance - Double(i) * balanceRange / Double(gridSteps)
                let valueText = formatAmount(value)
                let valueAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8),
                    .foregroundColor: UIColor.gray
                ]
                valueText.draw(at: CGPoint(x: chartRect.minX + 5, y: y - 4), withAttributes: valueAttributes)
            }
            context.cgContext.strokePath()
            
            // Draw balance line
            context.cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
            context.cgContext.setLineWidth(2)
            
            let path = UIBezierPath()
            for (index, point) in balancePoints.enumerated() {
                let x = chartRect.minX + 20 + CGFloat(index) * xStep
                let y = chartRect.maxY - 20 - CGFloat(point.balance - minBalance) * yScale
                
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.stroke()
            
            // Draw points
            for (index, point) in balancePoints.enumerated() {
                let x = chartRect.minX + 20 + CGFloat(index) * xStep
                let y = chartRect.maxY - 20 - CGFloat(point.balance - minBalance) * yScale
                
                let pointRect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                UIColor.systemBlue.setFill()
                context.cgContext.fillEllipse(in: pointRect)
            }
        }
        
        yPosition += 320
        
        // Draw current balances
        let balancesTitle = "Aktuelle Kontosalden"
        let balancesTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        balancesTitle.draw(at: CGPoint(x: 40, y: yPosition), withAttributes: balancesTitleAttributes)
        yPosition += 30
        
        // Table header
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        let columns = ["Konto", "Saldo"]
        let columnWidths: [CGFloat] = [300, 150]
        var xPosition: CGFloat = 40
        
        for (index, column) in columns.enumerated() {
            column.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: headerAttributes)
            xPosition += columnWidths[index]
        }
        
        yPosition += 20
        
        // Draw separator line
        context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
        context.cgContext.setLineWidth(1)
        context.cgContext.move(to: CGPoint(x: 40, y: yPosition))
        context.cgContext.addLine(to: CGPoint(x: pageWidth - 40, y: yPosition))
        context.cgContext.strokePath()
        
        yPosition += 10
        
        // Table rows
        let rowAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        for account in accounts {
            xPosition = 40
            
            // Account name
            account.name?.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: rowAttributes)
            xPosition += columnWidths[0]
            
            // Balance
            let balance = viewModel.getBalance(for: account)
            let balanceText = formatAmount(balance)
            let balanceAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: balance >= 0 ? UIColor.systemGreen : UIColor.systemRed
            ]
            balanceText.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: balanceAttributes)
            
            yPosition += 25
        }
    }
    
    private func drawForecastPage(context: UIGraphicsPDFRendererContext, pageWidth: CGFloat, pageHeight: CGFloat, pageNumber: Int) {
        // Dark header background
        let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 80)
        UIColor.black.setFill()
        context.cgContext.fill(headerRect)
        
        // Title
        let title = "Finanzprognose"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.white
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = CGRect(x: (pageWidth - titleSize.width) / 2, y: 25, width: titleSize.width, height: titleSize.height)
        title.draw(in: titleRect, withAttributes: titleAttributes)
        
        // Page number
        let pageText = "Seite \(pageNumber)"
        let pageAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.gray
        ]
        let pageSize = pageText.size(withAttributes: pageAttributes)
        let pageRect = CGRect(x: pageWidth - pageSize.width - 20, y: pageHeight - 30, width: pageSize.width, height: pageSize.height)
        pageText.draw(in: pageRect, withAttributes: pageAttributes)
        
        let yPosition: CGFloat = 100
        
        // Berechne Prognose-Daten
        let calendar = Calendar.current
        let today = Date()
        let range = calendar.range(of: .day, in: .month, for: today) ?? 1..<31
        let daysInMonth = range.count
        let currentDay = calendar.component(.day, from: today)
        
        // Durchschnittswerte
        let avgIncome = monthlyData.isEmpty ? 0 : monthlyData.reduce(0) { $0 + $1.income } / Double(monthlyData.count)
        let avgExpenses = monthlyData.isEmpty ? 0 : monthlyData.reduce(0) { $0 + $1.expenses } / Double(monthlyData.count)
        let dailyIncome = avgIncome / Double(daysInMonth)
        let dailyExpenses = avgExpenses / Double(daysInMonth)
        
        // Startsaldo: letzter bekannter Saldo
        let lastSaldo = monthlyData.last?.surplus ?? 0
        
        // Kumulierte Werte berechnen
        var cumIncome: [Double] = []
        var cumExpenses: [Double] = []
        var cumSaldo: [Double] = []
        var saldo = lastSaldo
        var incomeSum: Double = 0
        var expenseSum: Double = 0
        for _ in 1...daysInMonth {
            incomeSum += dailyIncome
            expenseSum += dailyExpenses
            saldo += dailyIncome - dailyExpenses
            cumIncome.append(incomeSum)
            cumExpenses.append(expenseSum)
            cumSaldo.append(saldo)
        }
        
        // Chart vorbereiten
        let chartRect = CGRect(x: 40, y: yPosition, width: pageWidth - 80, height: 300)
        UIColor.systemGray6.setFill()
        context.cgContext.fill(chartRect)
        context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
        context.cgContext.setLineWidth(1)
        context.cgContext.stroke(chartRect)
        
        // Max/Min für Y-Achse
        let maxY = max((cumIncome + cumExpenses + cumSaldo).max() ?? 1, 1)
        let minY = min((cumIncome + cumExpenses + cumSaldo).min() ?? 0, 0)
        let yRange = maxY - minY
        let xStep = (chartRect.width - 40) / CGFloat(daysInMonth - 1)
        let yScale = (chartRect.height - 40) / CGFloat(yRange == 0 ? 1 : yRange)
        
        // Hilfslinien
        let gridSteps = 5
        context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
        context.cgContext.setLineWidth(0.5)
        for i in 0...gridSteps {
            let y = chartRect.minY + 20 + CGFloat(i) * (chartRect.height - 40) / CGFloat(gridSteps)
            context.cgContext.move(to: CGPoint(x: chartRect.minX + 20, y: y))
            context.cgContext.addLine(to: CGPoint(x: chartRect.maxX - 20, y: y))
            // Wert
            let value = maxY - Double(i) * yRange / Double(gridSteps)
            let valueText = formatAmount(value)
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.gray
            ]
            valueText.draw(at: CGPoint(x: chartRect.minX + 5, y: y - 4), withAttributes: valueAttributes)
        }
        context.cgContext.strokePath()
        
        // Linien zeichnen
        func drawLine(_ values: [Double], color: UIColor) {
            context.cgContext.setStrokeColor(color.cgColor)
            context.cgContext.setLineWidth(2)
            let path = UIBezierPath()
            for (i, v) in values.enumerated() {
                let x = chartRect.minX + 20 + CGFloat(i) * xStep
                let y = chartRect.maxY - 20 - CGFloat(v - minY) * yScale
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            path.stroke()
        }
        drawLine(cumIncome, color: UIColor.systemGreen)
        drawLine(cumExpenses, color: UIColor.systemRed)
        drawLine(cumSaldo, color: UIColor.systemBlue)
        
        // Aktuellen Tag markieren
        let todayX = chartRect.minX + 20 + CGFloat(currentDay - 1) * xStep
        context.cgContext.setStrokeColor(UIColor.systemGray.cgColor)
        context.cgContext.setLineWidth(1.5)
        context.cgContext.move(to: CGPoint(x: todayX, y: chartRect.minY + 10))
        context.cgContext.addLine(to: CGPoint(x: todayX, y: chartRect.maxY - 10))
        context.cgContext.strokePath()
        
        // Legende
        let legendY = chartRect.maxY + 20
        let legendAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        let legends = [
            ("Kumulierte Einnahmen", UIColor.systemGreen),
            ("Kumulierte Ausgaben", UIColor.systemRed),
            ("Kumulierter Saldo", UIColor.systemBlue),
            ("Aktueller Tag", UIColor.systemGray)
        ]
        var legendX = chartRect.minX
        for (text, color) in legends {
            // Linie
            context.cgContext.setStrokeColor(color.cgColor)
            context.cgContext.setLineWidth(2)
            context.cgContext.move(to: CGPoint(x: legendX, y: legendY + 8))
            context.cgContext.addLine(to: CGPoint(x: legendX + 30, y: legendY + 8))
            context.cgContext.strokePath()
            // Text
            let size = text.size(withAttributes: legendAttributes)
            text.draw(at: CGPoint(x: legendX + 35, y: legendY), withAttributes: legendAttributes)
            legendX += 35 + size.width + 30
        }
        
        // Prognosewerte am Monatsende
        let endIncome = cumIncome.last ?? 0
        let endExpenses = cumExpenses.last ?? 0
        let endSaldo = cumSaldo.last ?? 0
        let summaryY = legendY + 25
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]
        let summary = "Prognose Monatsende: Einnahmen: \(formatAmount(endIncome)), Ausgaben: \(formatAmount(endExpenses)), Saldo: \(formatAmount(endSaldo))"
        let summaryRect = CGRect(x: chartRect.minX, y: summaryY, width: chartRect.width, height: 40)
        (summary as NSString).draw(with: summaryRect, options: .usesLineFragmentOrigin, attributes: summaryAttributes, context: nil)
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