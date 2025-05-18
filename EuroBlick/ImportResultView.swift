import SwiftUI

struct ImportResultView: View {
    let importResult: TransactionViewModel.ImportResult
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Importierte Transaktionen
                        if !importResult.imported.isEmpty {
                            SectionHeaderView(title: "Importierte Transaktionen (\(importResult.imported.count))")
                            ForEach(importResult.imported, id: \.self) { transaction in
                                TransactionInfoRow(transaction: transaction)
                            }
                        } else {
                            Text("Keine Transaktionen importiert")
                                .foregroundColor(.white)
                                .padding()
                        }
                        
                        // Übersprungene Transaktionen
                        if !importResult.skipped.isEmpty {
                            SectionHeaderView(title: "Übersprungene Duplikate (\(importResult.skipped.count))")
                            ForEach(importResult.skipped, id: \.self) { transaction in
                                TransactionInfoRow(transaction: transaction)
                            }
                        } else {
                            Text("Keine Duplikate übersprungen")
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Import-Ergebnisse")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
}

struct SectionHeaderView: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 8)
    }
}

struct TransactionInfoRow: View {
    let transaction: TransactionViewModel.ImportResult.TransactionInfo
    
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(transaction.date)
                    .foregroundColor(.white)
                Spacer()
                Text(formatAmount(transaction.amount))
                    .foregroundColor(transaction.amount >= 0 ? .green : .red)
            }
            Text("Konto: \(transaction.account)")
                .foregroundColor(.gray)
                .font(.caption)
            Text("Kategorie: \(transaction.category)")
                .foregroundColor(.gray)
                .font(.caption)
            if let usage = transaction.usage {
                Text("Verwendungszweck: \(usage)")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}

// Hashable für TransactionInfo, um ForEach zu unterstützen
extension TransactionViewModel.ImportResult.TransactionInfo: Hashable {
    static func == (lhs: TransactionViewModel.ImportResult.TransactionInfo, rhs: TransactionViewModel.ImportResult.TransactionInfo) -> Bool {
        return lhs.date == rhs.date &&
               lhs.amount == rhs.amount &&
               lhs.account == rhs.account &&
               lhs.usage == rhs.usage &&
               lhs.category == rhs.category
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(amount)
        hasher.combine(account)
        hasher.combine(usage)
        hasher.combine(category)
    }
}

#Preview {
    ImportResultView(
        importResult: TransactionViewModel.ImportResult(
            imported: [
                .init(date: "01.04.2025", amount: 100.0, account: "Giro", usage: "Test Einnahme", category: "Einnahmen"),
                .init(date: "02.04.2025", amount: -50.0, account: "Giro", usage: "Test Ausgabe", category: "Sonstiges")
            ],
            skipped: [
                .init(date: "03.04.2025", amount: -20.0, account: "Giro", usage: "Duplikat", category: "Sonstiges")
            ]
        ),
        isPresented: .constant(true)
    )
}
