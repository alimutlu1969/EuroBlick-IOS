import SwiftUI

struct ImportResultView: View {
    let importResult: TransactionViewModel.ImportResult
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    // Header
                    VStack(spacing: 10) {
                        Text("Import-Details")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(.top)
                        
                        // Summary
                        VStack(spacing: 8) {
                            HStack {
                                Text("Importiert:")
                                Spacer()
                                Text("\(importResult.imported.count)")
                                    .foregroundColor(.green)
                            }
                            
                            HStack {
                                Text("Übersprungen:")
                                Spacer()
                                Text("\(importResult.skipped.count)")
                                    .foregroundColor(.orange)
                            }
                            
                            HStack {
                                Text("Verdächtig:")
                                Spacer()
                                Text("\(importResult.suspicious.count)")
                                    .foregroundColor(.red)
                            }
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    // Details
                    ScrollView {
                        VStack(spacing: 20) {
                            // Imported Transactions
                            if !importResult.imported.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Importierte Transaktionen")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                        .padding(.horizontal)
                                    
                                    ForEach(importResult.imported, id: \.date) { transaction in
                                        TransactionDetailRow(transaction: transaction, type: .imported)
                                    }
                                }
                            }
                            
                            // Skipped Transactions
                            if !importResult.skipped.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Übersprungene Transaktionen")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal)
                                    
                                    ForEach(importResult.skipped, id: \.date) { transaction in
                                        TransactionDetailRow(transaction: transaction, type: .skipped)
                                    }
                                }
                            }
                            
                            // Suspicious Transactions
                            if !importResult.suspicious.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Verdächtige Transaktionen")
                                        .font(.headline)
                                        .foregroundColor(.red)
                                        .padding(.horizontal)
                                    
                                    ForEach(importResult.suspicious, id: \.date) { transaction in
                                        TransactionDetailRow(transaction: transaction, type: .suspicious)
                                    }
                                }
                            }
                        }
                        .padding(.bottom)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Schließen") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct TransactionDetailRow: View {
    let transaction: TransactionViewModel.ImportResult.TransactionInfo
    let type: TransactionType
    
    enum TransactionType {
        case imported, skipped, suspicious
        
        var color: Color {
            switch self {
            case .imported: return .green
            case .skipped: return .orange
            case .suspicious: return .red
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(transaction.date)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text(String(format: "%.2f €", transaction.amount))
                    .foregroundColor(transaction.amount >= 0 ? .green : .red)
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Konto:")
                        .foregroundColor(.gray)
                    Text(transaction.account)
                        .foregroundColor(.white)
                }
                
                HStack {
                    Text("Kategorie:")
                        .foregroundColor(.gray)
                    Text(transaction.category)
                        .foregroundColor(.white)
                }
                
                if let usage = transaction.usage, !usage.isEmpty {
                    HStack {
                        Text("Zweck:")
                            .foregroundColor(.gray)
                        Text(usage)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

#Preview {
    let sampleResult = TransactionViewModel.ImportResult(
        imported: [
            TransactionViewModel.ImportResult.TransactionInfo(
                date: "18.08.2025",
                amount: 50.0,
                account: "Giro-Kaffee",
                usage: "Reservierung Test",
                category: "Reservierung",
                isSuspicious: false,
                existingTransaction: nil
            )
        ],
        skipped: [],
        suspicious: []
    )
    
    return ImportResultView(importResult: sampleResult)
}
