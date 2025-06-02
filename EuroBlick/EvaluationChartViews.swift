import SwiftUI
import Charts

// MARK: - Bar Chart View for Income/Expenses

struct BarChartView: View {
    let data: MonthlyData
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Einnahmen / Ausgaben / Überschuss")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            let maxValue = max(abs(data.income), abs(data.expenses), abs(data.surplus))
            let maxHeight: CGFloat = 100
            let scaleFactor = maxValue > 0 ? (maxHeight / maxValue) * 0.7 : 1.0
            
            HStack {
                // Einnahmen (links, grün)
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: 80, height: max(CGFloat(abs(data.income)) * scaleFactor, 20))
                    Text("Einnahmen")
                        .foregroundColor(.white)
                        .font(.caption2)
                        .padding(.top, 8)
                    Text(formatAmount(data.income))
                        .foregroundColor(.green)
                        .font(.caption2)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    print("🔍 BarChartView: Einnahmen-Balken wurde angetippt")
                    print("🔍 BarChartView: \(data.incomeTransactions.count) Einnahme-Transaktionen gefunden")
                    DispatchQueue.main.async {
                        showTransactions(data.incomeTransactions, "Einnahmen")
                    }
                    print("🔍 BarChartView: showTransactions für Einnahmen aufgerufen")
                }
                Spacer()
                
                // Ausgaben (mitte, rot)
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 80, height: max(CGFloat(abs(data.expenses)) * scaleFactor, 20))
                    Text("Ausgaben")
                        .foregroundColor(.white)
                        .font(.caption2)
                        .padding(.top, 8)
                    Text(formatAmount(data.expenses))
                        .foregroundColor(.red)
                        .font(.caption2)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    print("🔍 BarChartView: Ausgaben-Balken wurde angetippt")
                    print("🔍 BarChartView: \(data.expenseTransactions.count) Ausgaben-Transaktionen gefunden")
                    DispatchQueue.main.async {
                        showTransactions(data.expenseTransactions, "Ausgaben")
                    }
                    print("🔍 BarChartView: showTransactions für Ausgaben aufgerufen")
                }
                
                // Überschuss (rechts, dynamische Farbe)
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(data.surplus >= 0 ? Color.green : Color.red)
                        .frame(width: 80, height: max(CGFloat(abs(data.surplus)) * scaleFactor, 20))
                    Text("Überschuss")
                        .foregroundColor(.white)
                        .font(.caption2)
                        .padding(.top, 8)
                    Text(formatAmount(data.surplus))
                        .foregroundColor(data.surplus >= 0 ? .green : .red)
                        .font(.caption2)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    print("🔍 BarChartView: Überschuss-Balken wurde angetippt")
                    let allTransactions = data.incomeTransactions + data.expenseTransactions
                    print("🔍 BarChartView: \(allTransactions.count) Gesamte Transaktionen gefunden")
                    DispatchQueue.main.async {
                        showTransactions(allTransactions, "Alle Transaktionen")
                    }
                    print("🔍 BarChartView: showTransactions für Alle Transaktionen aufgerufen")
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Category Chart View for Expenses

struct CategoryChartView: View {
    let categoryData: [CategoryData]
    let totalExpenses: Double
    let showTransactions: ([Transaction], String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Ausgaben nach Kategorie")
                .font(.subheadline)
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
                            print("🔍 CategoryChart: Segment '\(segment.name)' wurde angetippt")
                            if let categoryData = categoryData.first(where: { $0.name == segment.name }) {
                                print("🔍 CategoryChart: \(categoryData.transactions.count) Transaktionen gefunden für '\(segment.name)'")
                                showTransactions(categoryData.transactions, "Ausgaben: \(segment.name)")
                                print("🔍 CategoryChart: showTransactions aufgerufen")
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
        categoryData.first(where: { $0.name == name })?.color ?? .gray
    }
}

// MARK: - Table Views

struct ExpenseCategoryTableView: View {
    let categoryData: [CategoryData]
    let totalExpenses: Double
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
                    Text(String(format: "%.1f%%", (category.value / totalExpenses) * 100))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(.white)
                        .font(.caption2)
                    
                    // Betrag in Rot für Ausgaben
                    Text(formatAmount(category.value))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(.red)
                        .font(.caption2)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.clear)
                .font(.callout)
                .contentShape(Rectangle())
                .onTapGesture {
                    print("🔍 ExpenseCategoryTableView: Zeile für '\(category.name)' angetippt")
                    showTransactions(category.transactions, "Ausgaben: \(category.name)")
                    print("🔍 ExpenseCategoryTableView: showTransactions aufgerufen")
                }
                
                Divider()
                    .background(Color.gray.opacity(0.3))
            }
        }
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
    }
}

// MARK: - Overlay Annotations

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

// MARK: - Forecast View

struct ForecastView: View {
    let transactions: [Transaction]
    let colorForValue: (Double) -> Color

    private func calculateDailyAverages() -> (income: Double, expenses: Double, surplus: Double)? {
        let calendar = Calendar.current
        
        // Gruppiere Transaktionen nach Typ
        let incomeTransactions = transactions.filter { $0.type == "einnahme" }
        let expenseTransactions = transactions.filter { $0.type == "ausgabe" }
        
        // Berechne Summen
        let totalIncome = incomeTransactions.reduce(0.0) { $0 + $1.amount }
        let totalExpenses = expenseTransactions.reduce(0.0) { $0 + abs($1.amount) }
        
        // Berechne die Anzahl der Tage zwischen der ersten und letzten Transaktion
        if let firstIncomeDate = incomeTransactions.map({ $0.date }).min(),
           let lastIncomeDate = incomeTransactions.map({ $0.date }).max() {
            let daysIncome = max(1.0, Double(calendar.dateComponents([.day], from: firstIncomeDate, to: lastIncomeDate).day ?? 0) + 1)
            let dailyIncome = totalIncome / daysIncome
            
            let daysExpenses = if let firstExpenseDate = expenseTransactions.map({ $0.date }).min(),
                                 let lastExpenseDate = expenseTransactions.map({ $0.date }).max() {
                max(1.0, Double(calendar.dateComponents([.day], from: firstExpenseDate, to: lastExpenseDate).day ?? 0) + 1)
            } else {
                1.0
            }
            let dailyExpenses = totalExpenses / daysExpenses
            let dailySurplus = dailyIncome - dailyExpenses
            
            return (dailyIncome, dailyExpenses, dailySurplus)
        }
        
        return nil
    }

    private func calculateMonthEndProjection() -> (income: Double, expenses: Double, surplus: Double)? {
        guard let averages = calculateDailyAverages() else { return nil }
        
        let calendar = Calendar.current
        let today = Date()
        
        // Berechne die verbleibenden Tage im Monat
        guard let range = calendar.range(of: .day, in: .month, for: today) else { return nil }
        let daysInMonth = range.count
        let currentDay = calendar.component(.day, from: today)
        let remainingDays = daysInMonth - currentDay
        
        // Berechne die projizierten Werte für die verbleibenden Tage
        let projectedIncome = averages.income * Double(remainingDays)
        let projectedExpenses = averages.expenses * Double(remainingDays)
        let projectedSurplus = projectedIncome - projectedExpenses
        
        return (projectedIncome, projectedExpenses, projectedSurplus)
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Prognostizierter Kontostand am Monatsende")
                .foregroundColor(.white)
                .font(.subheadline)
                .padding(.horizontal)
            
            if let averages = calculateDailyAverages() {
                // Tägliche Durchschnittswerte
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tägliche Durchschnittswerte:")
                        .foregroundColor(.white)
                        .font(.caption)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Einnahmen: \(formatAmount(averages.income))")
                            .foregroundColor(.green)
                        Text("Ausgaben: \(formatAmount(-averages.expenses))")
                            .foregroundColor(.red)
                        Text("Überschuss: \(formatAmount(averages.surplus))")
                            .foregroundColor(colorForValue(averages.surplus))
                    }
                    .font(.caption2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
                .padding(.horizontal)

                // Prognose
                if let projection = calculateMonthEndProjection() {
                    HStack(spacing: 15) {
                        // Prognostizierte Einnahmen
                        VStack(spacing: 4) {
                            Spacer()
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: 70, height: barHeight(for: projection.income))
                            Text("Einnahmen")
                                .foregroundColor(.white)
                                .font(.caption2)
                                .padding(.top, 4)
                            Text(formatAmount(projection.income))
                                .foregroundColor(.green)
                                .font(.caption2)
                                .padding(.top, 2)
                        }
                        
                        // Prognostizierte Ausgaben
                        VStack(spacing: 4) {
                            Spacer()
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 70, height: barHeight(for: projection.expenses))
                            Text("Ausgaben")
                                .foregroundColor(.white)
                                .font(.caption2)
                                .padding(.top, 4)
                            Text(formatAmount(-projection.expenses))
                                .foregroundColor(.red)
                                .font(.caption2)
                                .padding(.top, 2)
                        }
                        
                        // Prognostizierter Überschuss
                        VStack(spacing: 4) {
                            Spacer()
                            Rectangle()
                                .fill(colorForValue(projection.surplus))
                                .frame(width: 70, height: barHeight(for: projection.surplus))
                            Text("Überschuss")
                                .foregroundColor(.white)
                                .font(.caption2)
                                .padding(.top, 4)
                            Text(formatAmount(projection.surplus))
                                .foregroundColor(colorForValue(projection.surplus))
                                .font(.caption2)
                                .padding(.top, 2)
                        }
                    }
                    .frame(height: 80)
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
    }

    private func barHeight(for value: Double) -> CGFloat {
        let maxHeight: CGFloat = 80 // Zurück zum ursprünglichen Wert
        let minHeight: CGFloat = 15  // Zurück zum ursprünglichen Wert
        
        // Sehr aggressive Skalierung: Pro 10.000€ nur 5 Pixel
        let pixelsPerTenThousand: CGFloat = 5  // Noch aggressiver als vorher
        let calculatedHeight = CGFloat(abs(value)) / 10000 * pixelsPerTenThousand
        
        return max(min(calculatedHeight, maxHeight), minHeight)
    }
}

// MARK: - Balance History Chart Component

struct BalanceHistoryChart: View {
    let dataPoints: [AccountBalanceHistoryView.BalanceDataPoint]
    let formatShortAmount: (Double) -> String
    
    var body: some View {
        Chart {
            // Nulllinie
            RuleMark(y: .value("Null", 0))
                .foregroundStyle(Color.gray.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            
            // Balken für jeden Datenpunkt
            ForEach(dataPoints) { dataPoint in
                BarMark(
                    x: .value("Datum", dataPoint.date),
                    y: .value("Saldo", dataPoint.balance)
                )
                .foregroundStyle(dataPoint.balance >= 0 ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
            }
            
            // Linie über den Balken
            ForEach(dataPoints) { dataPoint in
                LineMark(
                    x: .value("Datum", dataPoint.date),
                    y: .value("Saldo", dataPoint.balance)
                )
            }
            .foregroundStyle(Color.blue)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(formatShortAmount(amount))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.gray.opacity(0.2))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.day().month(.abbreviated))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.gray.opacity(0.2))
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.black.opacity(0.05))
                .border(Color.gray.opacity(0.2), width: 0.5)
        }
        .frame(height: 250)
        .padding()
    }
}

// MARK: - Account Balance History View

struct AccountBalanceHistoryView: View {
    let accounts: [Account]
    @ObservedObject var viewModel: TransactionViewModel
    let selectedMonth: String
    let customDateRange: (start: Date, end: Date)?
    
    @State private var selectedAccount: Account?
    @State private var showAccountPicker = false
    
    struct BalanceDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Double
        let accountName: String
    }
    
    private func calculateBalanceHistory() -> [BalanceDataPoint] {
        var dataPoints: [BalanceDataPoint] = []
        let calendar = Calendar.current
        
        // Verwende nur das ausgewählte Konto oder das erste Konto als Standard
        let accountsToShow = selectedAccount != nil ? [selectedAccount!] : (accounts.isEmpty ? [] : [accounts[0]])
        
        // Bestimme den Zeitraum basierend auf selectedMonth
        let dateRange: (start: Date, end: Date)
        if selectedMonth == "Benutzerdefinierter Zeitraum", let range = customDateRange {
            dateRange = range
        } else if selectedMonth == "Alle Monate" {
            // Finde die früheste und späteste Transaktion
            let allTransactions = accountsToShow.flatMap { $0.transactions?.allObjects as? [Transaction] ?? [] }
            let dates = allTransactions.map { $0.date }
            guard let minDate = dates.min(), let maxDate = dates.max() else {
                return []
            }
            dateRange = (minDate, maxDate)
        } else {
            // Spezifischer Monat
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = "MMM yyyy"
            guard let monthDate = formatter.date(from: selectedMonth) else {
                return []
            }
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)) ?? monthDate
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? monthDate
            dateRange = (startOfMonth, endOfMonth)
        }
        
        // Berechne tägliche Salden für das ausgewählte Konto
        for account in accountsToShow {
            var currentDate = dateRange.start
            var cumulativeBalance = 0.0
            
            // Hole alle Transaktionen bis zum Startdatum für den Anfangssaldo
            let allTransactions = account.transactions?.allObjects as? [Transaction] ?? []
            let transactionsBeforeStart = allTransactions.filter { $0.date < dateRange.start && $0.type != "reservierung" }
            cumulativeBalance = transactionsBeforeStart.reduce(0.0) { $0 + $1.amount }
            
            // Iteriere über jeden Tag im Zeitraum
            while currentDate <= dateRange.end {
                // Finde alle Transaktionen für diesen Tag
                let dayStart = calendar.startOfDay(for: currentDate)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? currentDate
                
                let dayTransactions = allTransactions.filter { 
                    $0.date >= dayStart && $0.date < dayEnd && $0.type != "reservierung"
                }
                
                // Addiere die Transaktionen des Tages zum Saldo
                let dayTotal = dayTransactions.reduce(0.0) { $0 + $1.amount }
                cumulativeBalance += dayTotal
                
                // Füge Datenpunkt hinzu
                dataPoints.append(BalanceDataPoint(
                    date: currentDate,
                    balance: cumulativeBalance,
                    accountName: account.name ?? "Unbekannt"
                ))
                
                // Gehe zum nächsten Tag
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }
        }
        
        return dataPoints.sorted { $0.date < $1.date }
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
    
    private func formatShortAmount(_ amount: Double) -> String {
        let absAmount = abs(amount)
        if absAmount >= 1000 {
            return String(format: "%.0fk", absAmount / 1000)
        } else {
            return String(format: "%.0f", absAmount)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header mit Kontoauswahl
            HStack {
                Text("Kontosaldenverlauf")
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    showAccountPicker = true
                }) {
                    HStack(spacing: 4) {
                        Text(selectedAccount?.name ?? (accounts.first?.name ?? "Konto wählen"))
                            .font(.caption)
                            .foregroundColor(.white)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            
            let dataPoints = calculateBalanceHistory()
            
            if !dataPoints.isEmpty {
                BalanceHistoryChart(
                    dataPoints: dataPoints,
                    formatShortAmount: formatShortAmount
                )
                
                // Zusammenfassung
                if let firstPoint = dataPoints.first, let lastPoint = dataPoints.last {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Startsaldo")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(formatAmount(firstPoint.balance))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(firstPoint.balance >= 0 ? .green : .red)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Endsaldo")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(formatAmount(lastPoint.balance))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(lastPoint.balance >= 0 ? .green : .red)
                            }
                        }
                        
                        Divider()
                            .background(Color.gray.opacity(0.3))
                        
                        let change = lastPoint.balance - firstPoint.balance
                        let changePercent = firstPoint.balance != 0 ? (change / abs(firstPoint.balance)) * 100 : 0
                        
                        HStack {
                            Text("Veränderung")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Text(formatAmount(change))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(change >= 0 ? .green : .red)
                                
                                Text("(\(String(format: "%.1f", changePercent))%)")
                                    .font(.caption)
                                    .foregroundColor(change >= 0 ? .green : .red)
                            }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
            } else {
                Text("Keine Daten für den ausgewählten Zeitraum")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .padding()
            }
        }
        .padding(.vertical)
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
        .onAppear {
            if selectedAccount == nil && !accounts.isEmpty {
                selectedAccount = accounts[0]
            }
        }
        .sheet(isPresented: $showAccountPicker) {
            AccountPickerSheet(
                accounts: accounts,
                selectedAccount: $selectedAccount,
                isPresented: $showAccountPicker
            )
        }
    }
}

// MARK: - Account Picker Sheet

struct AccountPickerSheet: View {
    let accounts: [Account]
    @Binding var selectedAccount: Account?
    @Binding var isPresented: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Gruppiere Konten nach Kontogruppe
                    let groupedAccounts = Dictionary(grouping: accounts, by: { $0.group })
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(Array(groupedAccounts.keys.compactMap { $0 }), id: \.self) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Gruppenname
                                    Text(group.name ?? "Unbenannte Gruppe")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                    
                                    // Konten in dieser Gruppe
                                    ForEach(groupedAccounts[group] ?? [], id: \.self) { account in
                                        Button(action: {
                                            selectedAccount = account
                                            dismiss()
                                        }) {
                                            HStack {
                                                // Konto-Icon
                                                Image(systemName: account.value(forKey: "icon") as? String ?? "banknote.fill")
                                                    .foregroundColor(Color(hex: account.value(forKey: "iconColor") as? String ?? "#007AFF") ?? .blue)
                                                    .frame(width: 30)
                                                
                                                Text(account.name ?? "Unbekannt")
                                                    .foregroundColor(.white)
                                                
                                                Spacer()
                                                
                                                if selectedAccount == account {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                            .padding()
                                            .background(selectedAccount == account ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                                            .cornerRadius(10)
                                            .contentShape(Rectangle())
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // Konten ohne Gruppe
                            let ungroupedAccounts = accounts.filter { $0.group == nil }
                            if !ungroupedAccounts.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Ohne Gruppe")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                    
                                    ForEach(ungroupedAccounts, id: \.self) { account in
                                        Button(action: {
                                            selectedAccount = account
                                            dismiss()
                                        }) {
                                            HStack {
                                                // Konto-Icon
                                                Image(systemName: account.value(forKey: "icon") as? String ?? "banknote.fill")
                                                    .foregroundColor(Color(hex: account.value(forKey: "iconColor") as? String ?? "#007AFF") ?? .blue)
                                                    .frame(width: 30)
                                                
                                                Text(account.name ?? "Unbekannt")
                                                    .foregroundColor(.white)
                                                
                                                Spacer()
                                                
                                                if selectedAccount == account {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                            .padding()
                                            .background(selectedAccount == account ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                                            .cornerRadius(10)
                                            .contentShape(Rectangle())
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Konto auswählen")
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