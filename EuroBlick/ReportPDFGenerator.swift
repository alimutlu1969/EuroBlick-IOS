import PDFKit
import SwiftUI
import Charts

class ReportPDFGenerator {
    private let monthlyData: [MonthlyData]
    private let categoryData: [CategoryData]
    private let usageData: [CategoryData]
    private let forecastData: [ForecastData]
    private let selectedMonth: String
    private let customDateRange: (start: Date, end: Date)?
    private let customDateRangeDisplay: String
    
    // Define colors array for pie chart segments
    private let colors: [UIColor] = [
        .systemBlue,
        .systemGreen,
        .systemPurple,
        .systemOrange,
        .systemPink,
        .systemYellow,
        .systemGray,
        .systemTeal,
        .systemIndigo,
        .systemRed,
        .systemBrown,
        .darkGray
    ]
    
    init(
        monthlyData: [MonthlyData],
        categoryData: [CategoryData],
        usageData: [CategoryData],
        forecastData: [ForecastData],
        selectedMonth: String,
        customDateRange: (start: Date, end: Date)?,
        customDateRangeDisplay: String
    ) {
        self.monthlyData = monthlyData
        self.categoryData = categoryData
        self.usageData = usageData
        self.forecastData = forecastData
        self.selectedMonth = selectedMonth
        self.customDateRange = customDateRange
        self.customDateRangeDisplay = customDateRangeDisplay
    }
    
    // Helper function to capture SwiftUI views as UIImage
    private func captureView<V: View>(_ view: V) -> UIImage {
        let controller = UIHostingController(rootView: view
            .frame(width: 500, height: 300)
            .padding()
        )
        let view = controller.view
        
        let targetSize = controller.view.intrinsicContentSize
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
    
    func generatePDF() -> URL {
        // Capture the current views as images
        let incomeExpensesImage = captureView(
            HStack {
                // Einnahmen (links, grün)
                VStack {
                    if let data = monthlyData.first {
                        let maxValue = max(abs(data.income), abs(data.expenses), abs(data.surplus))
                        let maxHeight: CGFloat = 150
                        let scaleFactor = maxValue > 0 ? maxHeight / maxValue : 1.0
                        
                        Spacer()
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 80, height: CGFloat(abs(data.income)) * scaleFactor)
                        Text("Einnahmen")
                            .foregroundColor(.black)
                            .font(.caption)
                            .padding(.top, 8)
                        Text("\(String(format: "%.2f €", data.income))")
                            .foregroundColor(.green)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                }
                Spacer()
                // Ausgaben (mitte, rot)
                VStack {
                    if let data = monthlyData.first {
                        let maxValue = max(abs(data.income), abs(data.expenses), abs(data.surplus))
                        let maxHeight: CGFloat = 150
                        let scaleFactor = maxValue > 0 ? maxHeight / maxValue : 1.0
                        
                        Spacer()
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 80, height: CGFloat(abs(data.expenses)) * scaleFactor)
                        Text("Ausgaben")
                            .foregroundColor(.black)
                            .font(.caption)
                            .padding(.top, 8)
                        Text("\(String(format: "%.2f €", data.expenses))")
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                }
                Spacer()
                // Überschuss (rechts, dynamische Farbe)
                VStack {
                    if let data = monthlyData.first {
                        let maxValue = max(abs(data.income), abs(data.expenses), abs(data.surplus))
                        let maxHeight: CGFloat = 150
                        let scaleFactor = maxValue > 0 ? maxHeight / maxValue : 1.0
                        
                        Spacer()
                        Rectangle()
                            .fill(data.surplus >= 0 ? Color.green : Color.red)
                            .frame(width: 80, height: CGFloat(abs(data.surplus)) * scaleFactor)
                        Text("Überschuss")
                            .foregroundColor(.black)
                            .font(.caption)
                            .padding(.top, 8)
                        Text("\(String(format: "%.2f €", data.surplus))")
                            .foregroundColor(data.surplus >= 0 ? .green : .red)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal)
            .frame(height: 200)
        )
        
        let categoryImage = captureView(
            CategoryChartView(
                categoryData: categoryData,
                totalExpenses: categoryData.reduce(0.0) { $0 + abs($1.value) },
                showTransactions: { _, _ in }
            )
        )
        
        let usageImage = captureView(
            UsageChartView(
                usageData: usageData,
                totalExpenses: usageData.reduce(0.0) { $0 + abs($1.value) },
                showTransactions: { _, _ in }
            )
        )
        
        // Generate PDF
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)) // A4
        let data = renderer.pdfData { context in
            context.beginPage()
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.white
            ]
            
            let sectionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.white
            ]
            
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
            
            let headerBackgroundColor = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0) // Dunkelgrau
            let borderColor = UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0) // Hellgrau
            
            // Common header attributes for all tables
            let categoryHeaderAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.white
            ]
            
            let pageRect = context.pdfContextBounds
            let margin: CGFloat = 40
            var currentY: CGFloat = margin
            
            // Titel mit Hintergrund
            let titleRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 30)
            context.cgContext.setFillColor(headerBackgroundColor.cgColor)
            context.cgContext.fill(titleRect)
            context.cgContext.setStrokeColor(borderColor.cgColor)
            context.cgContext.stroke(titleRect)
            
            let title = NSAttributedString(string: "EuroBlick Auswertungen", attributes: titleAttributes)
            title.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
            currentY += 40
            
            // Zeitraum mit Hintergrund
            let timeRangeRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 30)
            context.cgContext.setFillColor(headerBackgroundColor.cgColor)
            context.cgContext.fill(timeRangeRect)
            context.cgContext.setStrokeColor(borderColor.cgColor)
            context.cgContext.stroke(timeRangeRect)
            
            let timeRange = selectedMonth == "Benutzerdefinierter Zeitraum" ? customDateRangeDisplay : selectedMonth
            let timeRangeString = NSAttributedString(string: "Zeitraum: \(timeRange)", attributes: sectionAttributes)
            timeRangeString.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
            currentY += 40
            
            // Einnahmen/Ausgaben/Überschuss mit Diagramm
            if let data = monthlyData.first {
                let incomeHeaderRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 30)
                context.cgContext.setFillColor(headerBackgroundColor.cgColor)
                context.cgContext.fill(incomeHeaderRect)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(incomeHeaderRect)
                
                let incomeTitle = NSAttributedString(string: "Einnahmen/Ausgaben/Überschuss", attributes: sectionAttributes)
                incomeTitle.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
                currentY += 30
                
                // Zeichne das Balkendiagramm
                let chartRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 200)
                incomeExpensesImage.draw(in: chartRect)
                currentY += 220

                // Zusammenfassung
                let summaryRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 80)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(summaryRect)
                
                let summaryText = """
                Einkommen: \(String(format: "%.2f €", data.income))
                Kosten: \(String(format: "%.2f €", abs(data.expenses)))
                Cashflow: \(String(format: "%.2f €", data.surplus))
                """
                let summaryString = NSAttributedString(string: summaryText, attributes: textAttributes)
                summaryString.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
                currentY += 100

                // Neue Seite für die Tortendiagramme
                context.beginPage()
                currentY = margin

                // Total Credit Header
                let creditHeaderRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 30)
                context.cgContext.setFillColor(headerBackgroundColor.cgColor)
                context.cgContext.fill(creditHeaderRect)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(creditHeaderRect)
                
                let creditTitle = NSAttributedString(string: "Einnahmen nach Kategorie: \(String(format: "%.2f €", data.income))", attributes: sectionAttributes)
                creditTitle.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
                currentY += 40

                // Einnahmen Tortendiagramm und Tabelle
                let pieSize: CGFloat = 200
                let tableWidth = pageRect.width - (margin * 3) - pieSize
                var center = CGPoint(x: margin + pieSize/2, y: currentY + pieSize/2)

                // Gruppiere Einnahmen nach Kategorie
                let incomeByCategory = Dictionary(grouping: data.incomeTransactions) { $0.categoryRelationship?.name ?? "Unbekannt" }
                let incomeTotalAmount = data.income
                var incomeStartAngle: CGFloat = -(.pi / 2)

                // Tabellenkopf für Einnahmen
                let tableHeaderRect = CGRect(x: margin + pieSize + margin, y: currentY, width: tableWidth, height: 30)
                context.cgContext.setFillColor(UIColor.lightGray.cgColor)
                context.cgContext.fill(tableHeaderRect)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(tableHeaderRect)

                let kontoHeader = NSAttributedString(string: "Kategorie", attributes: categoryHeaderAttributes)
                let prozentHeader = NSAttributedString(string: "Anteil", attributes: categoryHeaderAttributes)
                let betragHeader = NSAttributedString(string: "Betrag", attributes: categoryHeaderAttributes)
                
                // Drei Spalten mit angepassten Breiten (50% - 20% - 30%)
                let categoryColumnWidth = tableWidth * 0.5  // Breiter für Kategorienamen
                let percentageColumnWidth = tableWidth * 0.2  // Schmaler für Prozentsatz
                let amountColumnWidth = tableWidth * 0.3  // Mittel für Betrag

                // Funktion zum Abkürzen langer Kategorienamen
                func abbreviateCategory(_ name: String) -> String {
                    let maxLength = 20
                    if name.count > maxLength {
                        switch name.lowercased() {
                        case let n where n.contains("finanzen") && n.contains("versicherungen"):
                            return "Finanzen"
                        case let n where n.contains("instandhaltung") && n.contains("reparatur"):
                            return "Instandhaltung"
                        default:
                            return String(name.prefix(maxLength - 3)) + "..."
                        }
                    }
                    return name
                }

                kontoHeader.draw(at: CGPoint(x: margin + pieSize + margin + 5, y: currentY + 5))
                prozentHeader.draw(at: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + 5, y: currentY + 5))
                betragHeader.draw(at: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth + 5, y: currentY + 5))

                // Vertikale Linien für drei Spalten
                context.cgContext.move(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth, y: currentY))
                context.cgContext.addLine(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth, y: currentY + 30))
                context.cgContext.move(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth, y: currentY))
                context.cgContext.addLine(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth, y: currentY + 30))
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.strokePath()
                
                currentY += 30

                // Zeichne Einnahmen-Tortendiagramm und Tabelle
                var rowY = currentY
                for (index, (category, transactions)) in incomeByCategory.sorted(by: { $0.1.reduce(0.0) { $0 + $1.amount } > $1.1.reduce(0.0) { $0 + $1.amount } }).enumerated() {
                    let amount = transactions.reduce(0.0) { $0 + $1.amount }
                    let percentage = amount / incomeTotalAmount
                    let endAngle = incomeStartAngle + (.pi * 2 * percentage)
                    
                    // Zeichne Tortenstück
                    let path = UIBezierPath()
                    path.move(to: center)
                    path.addArc(withCenter: center, radius: pieSize/2, startAngle: incomeStartAngle, endAngle: endAngle, clockwise: true)
                    path.close()
                    
                    // Wähle Farbe für die Kategorie
                    let categoryColor = colors[index % colors.count]
                    context.cgContext.setFillColor(categoryColor.cgColor)
                    path.fill()
                    
                    // Zeichne Tabellenzeile
                    let rowRect = CGRect(x: margin + pieSize + margin, y: rowY, width: tableWidth, height: 25)
                    context.cgContext.setStrokeColor(borderColor.cgColor)
                    context.cgContext.stroke(rowRect)
                    
                    // Vertikale Linien für Spalten
                    context.cgContext.move(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth, y: rowY))
                    context.cgContext.addLine(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth, y: rowY + 25))
                    context.cgContext.move(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth, y: rowY))
                    context.cgContext.addLine(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth, y: rowY + 25))
                    context.cgContext.setStrokeColor(borderColor.cgColor)
                    context.cgContext.strokePath()
                    
                    // Zeichne farbigen Punkt
                    let dotPath = UIBezierPath(arcCenter: CGPoint(x: margin + pieSize + margin + 10, y: rowY + 12.5),
                                             radius: 5,
                                             startAngle: 0,
                                             endAngle: .pi * 2,
                                             clockwise: true)
                    context.cgContext.setFillColor(categoryColor.cgColor)
                    dotPath.fill()
                    
                    // Kategoriename, Prozentsatz und Betrag in separaten Spalten
                    let categoryText = NSAttributedString(string: abbreviateCategory(category), attributes: textAttributes)
                    let percentageText = NSAttributedString(string: String(format: "%.1f%%", percentage * 100), attributes: textAttributes)
                    let amountText = NSAttributedString(string: String(format: "%.2f €", amount), attributes: textAttributes)
                    
                    categoryText.draw(at: CGPoint(x: margin + pieSize + margin + 25, y: rowY + 5))
                    percentageText.draw(at: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + 5, y: rowY + 5))
                    
                    // Rechtsbündige Betragsdarstellung
                    let amountWidth = amountText.size().width
                    amountText.draw(at: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth + amountColumnWidth - amountWidth - 5, y: rowY + 5))
                    
                    incomeStartAngle = endAngle
                    rowY += 25
                }
                
                currentY = rowY + 40

                // Erhöhe den Abstand zwischen den Diagrammen
                currentY = max(rowY + 80, currentY + pieSize + 80)

                // Total Debit Header
                let debitHeaderRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 30)
                context.cgContext.setFillColor(headerBackgroundColor.cgColor)
                context.cgContext.fill(debitHeaderRect)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(debitHeaderRect)
                
                let debitTitle = NSAttributedString(string: "Ausgaben nach Kategorie: \(String(format: "%.2f €", abs(data.expenses)))", attributes: sectionAttributes)
                debitTitle.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
                currentY += 40

                // Ausgaben Tortendiagramm und Tabelle
                center = CGPoint(x: margin + pieSize/2, y: currentY + pieSize/2)

                // Gruppiere Ausgaben nach Kategorie
                let expensesByCategory = Dictionary(grouping: data.expenseTransactions) { $0.categoryRelationship?.name ?? "Unbekannt" }
                let expensesTotalAmount = abs(data.expenses)
                var expensesStartAngle: CGFloat = -(.pi / 2)

                // Tabellenkopf für Ausgaben
                let expensesTableHeaderRect = CGRect(x: margin + pieSize + margin, y: currentY, width: tableWidth, height: 30)
                context.cgContext.setFillColor(UIColor.lightGray.cgColor)
                context.cgContext.fill(expensesTableHeaderRect)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(expensesTableHeaderRect)

                kontoHeader.draw(at: CGPoint(x: margin + pieSize + margin + 5, y: currentY + 5))
                prozentHeader.draw(at: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + 5, y: currentY + 5))
                betragHeader.draw(at: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth + 5, y: currentY + 5))

                // Vertikale Linien für drei Spalten
                context.cgContext.move(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth, y: currentY))
                context.cgContext.addLine(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth, y: currentY + 30))
                context.cgContext.move(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth, y: currentY))
                context.cgContext.addLine(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth, y: currentY + 30))
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.strokePath()
                
                currentY += 30

                // Zeichne Ausgaben-Tortendiagramm und Tabelle
                rowY = currentY
                for (index, (category, transactions)) in expensesByCategory.sorted(by: { abs($0.1.reduce(0.0) { $0 + $1.amount }) > abs($1.1.reduce(0.0) { $0 + $1.amount }) }).enumerated() {
                    let amount = abs(transactions.reduce(0.0) { $0 + $1.amount })
                    let percentage = amount / expensesTotalAmount
                    let endAngle = expensesStartAngle + (.pi * 2 * percentage)
                    
                    // Zeichne Tortenstück
                    let path = UIBezierPath()
                    path.move(to: center)
                    path.addArc(withCenter: center, radius: pieSize/2, startAngle: expensesStartAngle, endAngle: endAngle, clockwise: true)
                    path.close()
                    
                    // Wähle Farbe für die Kategorie
                    let categoryColor = colors[index % colors.count]
                    context.cgContext.setFillColor(categoryColor.cgColor)
                    path.fill()
                    
                    // Zeichne Tabellenzeile
                    let rowRect = CGRect(x: margin + pieSize + margin, y: rowY, width: tableWidth, height: 25)
                    context.cgContext.setStrokeColor(borderColor.cgColor)
                    context.cgContext.stroke(rowRect)
                    
                    // Vertikale Linien für Spalten
                    context.cgContext.move(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth, y: rowY))
                    context.cgContext.addLine(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth, y: rowY + 25))
                    context.cgContext.move(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth, y: rowY))
                    context.cgContext.addLine(to: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth, y: rowY + 25))
                    context.cgContext.setStrokeColor(borderColor.cgColor)
                    context.cgContext.strokePath()
                    
                    // Zeichne farbigen Punkt
                    let dotPath = UIBezierPath(arcCenter: CGPoint(x: margin + pieSize + margin + 10, y: rowY + 12.5),
                                             radius: 5,
                                             startAngle: 0,
                                             endAngle: .pi * 2,
                                             clockwise: true)
                    context.cgContext.setFillColor(categoryColor.cgColor)
                    dotPath.fill()
                    
                    // Kategoriename, Prozentsatz und Betrag in separaten Spalten
                    let categoryText = NSAttributedString(string: abbreviateCategory(category), attributes: textAttributes)
                    let percentageText = NSAttributedString(string: String(format: "%.1f%%", percentage * 100), attributes: textAttributes)
                    let amountText = NSAttributedString(string: String(format: "%.2f €", amount), attributes: textAttributes)
                    
                    categoryText.draw(at: CGPoint(x: margin + pieSize + margin + 25, y: rowY + 5))
                    percentageText.draw(at: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + 5, y: rowY + 5))
                    
                    // Rechtsbündige Betragsdarstellung
                    let amountWidth = amountText.size().width
                    amountText.draw(at: CGPoint(x: margin + pieSize + margin + categoryColumnWidth + percentageColumnWidth + amountColumnWidth - amountWidth - 5, y: rowY + 5))
                    
                    expensesStartAngle = endAngle
                    rowY += 25
                }
                
                currentY = rowY + 40
            }
            
            // Kategorien
            context.beginPage()
            currentY = margin
            
            // Überschrift mit Hintergrund und Rahmen
            let headerRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 30)
            context.cgContext.setFillColor(headerBackgroundColor.cgColor)
            context.cgContext.fill(headerRect)
            context.cgContext.setStrokeColor(borderColor.cgColor)
            context.cgContext.stroke(headerRect)
            
            let categoriesTitle = NSAttributedString(string: "Ausgaben nach Kategorie", attributes: sectionAttributes)
            categoriesTitle.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
            currentY += 40
            
            // Tabellenkopf
            let columnWidth = (pageRect.width - (margin * 2)) / 2
            let headerHeight: CGFloat = 25
            
            // Zeichne Tabellenkopf mit Hintergrund
            let tableHeaderRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: headerHeight)
            context.cgContext.setFillColor(headerBackgroundColor.cgColor)
            context.cgContext.fill(tableHeaderRect)
            context.cgContext.setStrokeColor(borderColor.cgColor)
            context.cgContext.stroke(tableHeaderRect)
            
            // Spaltenüberschriften
            let categoryHeader = NSAttributedString(string: "Kategorie", attributes: categoryHeaderAttributes)
            let amountHeader = NSAttributedString(string: "Betrag", attributes: categoryHeaderAttributes)
            
            categoryHeader.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
            amountHeader.draw(at: CGPoint(x: margin + columnWidth + 5, y: currentY + 5))
            
            // Vertikale Linie zwischen den Spalten
            context.cgContext.move(to: CGPoint(x: margin + columnWidth, y: currentY))
            context.cgContext.addLine(to: CGPoint(x: margin + columnWidth, y: currentY + headerHeight))
            context.cgContext.setStrokeColor(borderColor.cgColor)
            context.cgContext.strokePath()
            
            currentY += headerHeight
            
            // Tabelleninhalt
            let rowHeight: CGFloat = 20
            var totalExpenses: Double = 0
            
            for category in categoryData {
                if currentY + rowHeight > pageRect.height - margin {
                    context.beginPage()
                    currentY = margin
                }
                
                // Zeichne Zeilenrahmen
                let rowRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: rowHeight)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(rowRect)
                
                // Vertikale Linie
                context.cgContext.move(to: CGPoint(x: margin + columnWidth, y: currentY))
                context.cgContext.addLine(to: CGPoint(x: margin + columnWidth, y: currentY + rowHeight))
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.strokePath()
                
                // Kategoriename
                let categoryText = NSAttributedString(string: category.name, attributes: textAttributes)
                categoryText.draw(at: CGPoint(x: margin + 5, y: currentY + 2))
                
                // Betrag (rechtsbündig)
                let amount = abs(category.value)
                totalExpenses += amount
                let amountString = String(format: "%.2f €", amount)
                let amountText = NSAttributedString(string: amountString, attributes: textAttributes)
                let amountWidth = amountText.size().width
                amountText.draw(at: CGPoint(x: margin + columnWidth * 2 - amountWidth - 5, y: currentY + 2))
                
                currentY += rowHeight
            }
            
            // Summenzeile
            let totalRowRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: rowHeight)
            context.cgContext.setFillColor(headerBackgroundColor.cgColor)
            context.cgContext.fill(totalRowRect)
            context.cgContext.setStrokeColor(borderColor.cgColor)
            context.cgContext.stroke(totalRowRect)
            
            // Vertikale Linie für Summenzeile
            context.cgContext.move(to: CGPoint(x: margin + columnWidth, y: currentY))
            context.cgContext.addLine(to: CGPoint(x: margin + columnWidth, y: currentY + rowHeight))
            context.cgContext.setStrokeColor(borderColor.cgColor)
            context.cgContext.strokePath()
            
            let totalText = NSAttributedString(string: "Gesamt", attributes: categoryHeaderAttributes)
            totalText.draw(at: CGPoint(x: margin + 5, y: currentY + 2))
            
            let totalAmountString = String(format: "%.2f €", totalExpenses)
            let totalAmountText = NSAttributedString(string: totalAmountString, attributes: categoryHeaderAttributes)
            let totalAmountWidth = totalAmountText.size().width
            totalAmountText.draw(at: CGPoint(x: margin + columnWidth * 2 - totalAmountWidth - 5, y: currentY + 2))
            
            currentY += rowHeight + 30
            
            // Zeichne das Kategorien-Diagramm
            let categoryChartRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 300)
            categoryImage.draw(in: categoryChartRect)
            currentY += 320
            
            // Verwendungszweck
            context.beginPage()
            currentY = margin
            
            let usageTitle = NSAttributedString(string: "Ausgaben nach Verwendungszweck", attributes: sectionAttributes)
            usageTitle.draw(at: CGPoint(x: margin, y: currentY))
            currentY += 30
            
            // Zeichne das Verwendungszweck-Diagramm
            let usageChartRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 300)
            usageImage.draw(in: usageChartRect)
            currentY += 320
            
            // Transaktionslisten
            if let data = monthlyData.first {
                context.beginPage()
                currentY = margin
                
                // Einnahmen-Transaktionen Überschrift
                let incomeHeaderRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 30)
                context.cgContext.setFillColor(headerBackgroundColor.cgColor)
                context.cgContext.fill(incomeHeaderRect)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(incomeHeaderRect)
                
                let incomeTransactionsTitle = NSAttributedString(string: "Einnahmen-Transaktionen", attributes: sectionAttributes)
                incomeTransactionsTitle.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
                currentY += 40
                
                // Erstelle einen DateFormatter für das gewünschte Format
                let transactionDateFormatter = DateFormatter()
                transactionDateFormatter.dateFormat = "dd. MMMM yyyy"
                transactionDateFormatter.locale = Locale(identifier: "de_DE")
                
                // Attribute für Einnahmen (grün) und Ausgaben (rot)
                let incomeAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.systemGreen
                ]
                
                let expenseAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.systemRed
                ]
                
                // Tabellenkopf für Einnahmen
                let columnWidth = (pageRect.width - (margin * 2)) / 3
                let headerHeight: CGFloat = 25
                
                // Zeichne Tabellenkopf mit Hintergrund
                let tableHeaderRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: headerHeight)
                context.cgContext.setFillColor(headerBackgroundColor.cgColor)
                context.cgContext.fill(tableHeaderRect)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(tableHeaderRect)
                
                // Spaltenüberschriften
                let headerAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 12),
                    .foregroundColor: UIColor.white
                ]
                
                let dateHeader = NSAttributedString(string: "Datum", attributes: headerAttributes)
                let categoryHeader = NSAttributedString(string: "Kategorie", attributes: headerAttributes)
                let amountHeader = NSAttributedString(string: "Betrag", attributes: headerAttributes)
                
                dateHeader.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
                categoryHeader.draw(at: CGPoint(x: margin + columnWidth + 5, y: currentY + 5))
                amountHeader.draw(at: CGPoint(x: margin + columnWidth * 2 + 5, y: currentY + 5))
                
                // Vertikale Linien
                context.cgContext.move(to: CGPoint(x: margin + columnWidth, y: currentY))
                context.cgContext.addLine(to: CGPoint(x: margin + columnWidth, y: currentY + headerHeight))
                context.cgContext.move(to: CGPoint(x: margin + columnWidth * 2, y: currentY))
                context.cgContext.addLine(to: CGPoint(x: margin + columnWidth * 2, y: currentY + headerHeight))
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.strokePath()
                
                currentY += headerHeight
                
                // Einnahmen-Transaktionen
                let rowHeight: CGFloat = 20
                for tx in data.incomeTransactions {
                    if currentY + rowHeight > pageRect.height - margin {
                        context.beginPage()
                        currentY = margin
                    }
                    
                    // Zeichne Zeilenrahmen
                    let rowRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: rowHeight)
                    context.cgContext.stroke(rowRect)
                    
                    // Vertikale Linien
                    context.cgContext.move(to: CGPoint(x: margin + columnWidth, y: currentY))
                    context.cgContext.addLine(to: CGPoint(x: margin + columnWidth, y: currentY + rowHeight))
                    context.cgContext.move(to: CGPoint(x: margin + columnWidth * 2, y: currentY))
                    context.cgContext.addLine(to: CGPoint(x: margin + columnWidth * 2, y: currentY + rowHeight))
                    context.cgContext.setStrokeColor(borderColor.cgColor)
                    context.cgContext.strokePath()
                    
                    let dateString = transactionDateFormatter.string(from: tx.date)
                    let categoryString = tx.categoryRelationship?.name ?? "Unbekannt"
                    let amountString = String(format: "%.2f €", tx.amount)
                    
                    let dateText = NSAttributedString(string: dateString, attributes: incomeAttributes)
                    let categoryText = NSAttributedString(string: categoryString, attributes: incomeAttributes)
                    let amountText = NSAttributedString(string: amountString, attributes: incomeAttributes)
                    
                    dateText.draw(at: CGPoint(x: margin + 5, y: currentY + 2))
                    categoryText.draw(at: CGPoint(x: margin + columnWidth + 5, y: currentY + 2))
                    
                    // Rechtsbündige Betragsdarstellung
                    let amountWidth = amountText.size().width
                    amountText.draw(at: CGPoint(x: margin + columnWidth * 3 - amountWidth - 5, y: currentY + 2))
                    
                    currentY += rowHeight
                }
                
                currentY += 30
                
                // Ausgaben-Transaktionen Überschrift
                let expenseHeaderRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: 30)
                context.cgContext.setFillColor(headerBackgroundColor.cgColor)
                context.cgContext.fill(expenseHeaderRect)
                context.cgContext.stroke(expenseHeaderRect)
                
                let expensesTransactionsTitle = NSAttributedString(string: "Ausgaben-Transaktionen", attributes: sectionAttributes)
                expensesTransactionsTitle.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
                currentY += 40
                
                // Tabellenkopf für Ausgaben
                let expenseTableHeaderRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: headerHeight)
                context.cgContext.setFillColor(headerBackgroundColor.cgColor)
                context.cgContext.fill(expenseTableHeaderRect)
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.stroke(expenseTableHeaderRect)
                
                // Spaltenüberschriften wiederholen
                dateHeader.draw(at: CGPoint(x: margin + 5, y: currentY + 5))
                categoryHeader.draw(at: CGPoint(x: margin + columnWidth + 5, y: currentY + 5))
                amountHeader.draw(at: CGPoint(x: margin + columnWidth * 2 + 5, y: currentY + 5))
                
                // Vertikale Linien
                context.cgContext.move(to: CGPoint(x: margin + columnWidth, y: currentY))
                context.cgContext.addLine(to: CGPoint(x: margin + columnWidth, y: currentY + headerHeight))
                context.cgContext.move(to: CGPoint(x: margin + columnWidth * 2, y: currentY))
                context.cgContext.addLine(to: CGPoint(x: margin + columnWidth * 2, y: currentY + headerHeight))
                context.cgContext.setStrokeColor(borderColor.cgColor)
                context.cgContext.strokePath()
                
                currentY += headerHeight
                
                // Ausgaben-Transaktionen
                for tx in data.expenseTransactions {
                    if currentY + rowHeight > pageRect.height - margin {
                        context.beginPage()
                        currentY = margin
                    }
                    
                    // Zeichne Zeilenrahmen
                    let rowRect = CGRect(x: margin, y: currentY, width: pageRect.width - (margin * 2), height: rowHeight)
                    context.cgContext.stroke(rowRect)
                    
                    // Vertikale Linien
                    context.cgContext.move(to: CGPoint(x: margin + columnWidth, y: currentY))
                    context.cgContext.addLine(to: CGPoint(x: margin + columnWidth, y: currentY + rowHeight))
                    context.cgContext.move(to: CGPoint(x: margin + columnWidth * 2, y: currentY))
                    context.cgContext.addLine(to: CGPoint(x: margin + columnWidth * 2, y: currentY + rowHeight))
                    context.cgContext.setStrokeColor(borderColor.cgColor)
                    context.cgContext.strokePath()
                    
                    let dateString = transactionDateFormatter.string(from: tx.date)
                    let categoryString = tx.categoryRelationship?.name ?? "Unbekannt"
                    let amountString = String(format: "%.2f €", tx.amount)
                    
                    let dateText = NSAttributedString(string: dateString, attributes: expenseAttributes)
                    let categoryText = NSAttributedString(string: categoryString, attributes: expenseAttributes)
                    let amountText = NSAttributedString(string: amountString, attributes: expenseAttributes)
                    
                    dateText.draw(at: CGPoint(x: margin + 5, y: currentY + 2))
                    categoryText.draw(at: CGPoint(x: margin + columnWidth + 5, y: currentY + 2))
                    
                    // Rechtsbündige Betragsdarstellung
                    let amountWidth = amountText.size().width
                    amountText.draw(at: CGPoint(x: margin + columnWidth * 3 - amountWidth - 5, y: currentY + 2))
                    
                    currentY += rowHeight
                }
            }
        }
        
        // Save PDF to temporary directory
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let pdfFileURL = temporaryDirectory.appendingPathComponent("EuroBlickAuswertungen.pdf")
        try? data.write(to: pdfFileURL)
        return pdfFileURL
    }
}
