import SwiftUI

struct BalanceHistoryView: View {
    let accounts: [Account]
    @ObservedObject var viewModel: TransactionViewModel
    
    @State private var selectedMonth: String = "Alle Monate"
    @State private var customDateRange: (start: Date, end: Date)?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                AccountBalanceHistoryView(
                    accounts: accounts,
                    viewModel: viewModel,
                    selectedMonth: selectedMonth,
                    customDateRange: customDateRange
                )
            }
        }
        .navigationTitle("Kontosaldenverlauf")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let vm = TransactionViewModel(context: ctx)
    let acc = Account(context: ctx)
    acc.name = "Test"
    return NavigationStack {
        BalanceHistoryView(accounts: [acc], viewModel: vm)
    }
} 