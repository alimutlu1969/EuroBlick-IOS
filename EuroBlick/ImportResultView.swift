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
                        
                        // Verdächtige Transaktionen
                        if !importResult.suspicious.isEmpty {
                            SectionHeaderView(title: "Verdächtige Transaktionen (\(importResult.suspicious.count))")
                            ForEach(importResult.suspicious, id: \.self) { transaction in
                                SuspiciousTransactionInfoRow(transaction: transaction)
                            }
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

struct SuspiciousTransactionInfoRow: View {
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
                    .foregroundColor(.orange)
                    .font(.headline)
                Spacer()
                Text(formatAmount(transaction.amount))
                    .foregroundColor(transaction.amount >= 0 ? .green : .red)
                    .font(.headline)
            }
            
            Text("⚠️ Verdächtige Transaktion")
                .foregroundColor(.orange)
                .font(.caption)
                .fontWeight(.semibold)
            
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
            
            if let existing = transaction.existingTransaction {
                Text("Ähnliche Transaktion gefunden:")
                    .foregroundColor(.orange)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Betrag: \(formatAmount(existing.amount)), Kategorie: \(existing.categoryRelationship?.name ?? "Unbekannt")")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.orange.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange, lineWidth: 1)
        )
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
               lhs.category == rhs.category &&
               lhs.isSuspicious == rhs.isSuspicious
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(amount)
        hasher.combine(account)
        hasher.combine(usage)
        hasher.combine(category)
        hasher.combine(isSuspicious)
    }
}

#Preview {
    ImportResultView(
        importResult: TransactionViewModel.ImportResult(
            imported: [
                .init(date: "01.04.2025", amount: 100.0, account: "Giro", usage: "Test Einnahme", category: "Einnahmen", isSuspicious: false, existingTransaction: nil),
                .init(date: "02.04.2025", amount: -50.0, account: "Giro", usage: "Test Ausgabe", category: "Sonstiges", isSuspicious: false, existingTransaction: nil)
            ],
            skipped: [
                .init(date: "03.04.2025", amount: -20.0, account: "Giro", usage: "Duplikat", category: "Sonstiges", isSuspicious: false, existingTransaction: nil)
            ],
            suspicious: [
                .init(date: "04.04.2025", amount: 5000.0, account: "Giro", usage: "Sb-Einzahlung", category: "Geldautomat", isSuspicious: true, existingTransaction: nil)
            ]
        ),
        isPresented: .constant(true)
    )
}
