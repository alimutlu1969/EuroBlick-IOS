import SwiftUI

struct EvaluationMenuView: View {
    let accounts: [Account]
    @ObservedObject var viewModel: TransactionViewModel
    
    struct MenuItem {
        let title: String
        let icon: String
        let colors: [Color]
        let destination: AnyView
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
                    // Einnahmen/Ausgaben
                    NavigationLink(destination: IncomeExpenseChartView(accounts: accounts, viewModel: viewModel)) {
                        MenuRow(
                            icon: "chart.bar.fill",
                            title: "Einnahmen / Ausgaben",
                            colors: [.orange, .red]
                        )
                    }
                    .listRowBackground(Color.gray.opacity(0.1))
                    
                    // Einnahmen nach Kategorie
                    NavigationLink(destination: IncomeCategoryChartView(accounts: accounts, viewModel: viewModel)) {
                        MenuRow(
                            icon: "chart.pie.fill",
                            title: "Einnahmen nach Kategorie",
                            colors: [.green, .mint]
                        )
                    }
                    .listRowBackground(Color.gray.opacity(0.1))
                    
                    // Ausgaben nach Kategorie
                    NavigationLink(destination: ExpenseCategoryChartView(accounts: accounts, viewModel: viewModel)) {
                        MenuRow(
                            icon: "chart.pie.fill",
                            title: "Ausgaben nach Kategorie",
                            colors: [.pink, .purple, .orange]
                        )
                    }
                    .listRowBackground(Color.gray.opacity(0.1))
                    
                    // Prognose
                    NavigationLink(destination: ForecastChartView(accounts: accounts, viewModel: viewModel)) {
                        MenuRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Prognostizierter Kontostand",
                            colors: [.blue, .cyan]
                        )
                    }
                    .listRowBackground(Color.gray.opacity(0.1))
                    
                    // Kontosaldenverlauf
                    NavigationLink(destination: BalanceHistoryView(accounts: accounts, viewModel: viewModel)) {
                        MenuRow(
                            icon: "chart.xyaxis.line",
                            title: "Kontosaldenverlauf",
                            colors: [.yellow, .orange]
                        )
                    }
                    .listRowBackground(Color.gray.opacity(0.1))
                    
                    // PDF Export
                    NavigationLink(destination: PDFExportView(accounts: accounts, viewModel: viewModel)) {
                        MenuRow(
                            icon: "doc.text.fill",
                            title: "PDF Export",
                            colors: [.red, .pink]
                        )
                    }
                    .listRowBackground(Color.gray.opacity(0.1))
                }
                .listStyle(PlainListStyle())
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Auswertungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("Auswertungen")
                            .font(.headline)
                        if let accountGroupName = accounts.first?.group?.name {
                            Text("•")
                                .foregroundColor(.gray)
                            Text(accountGroupName)
                                .foregroundColor(.gray)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }
}

struct MenuRow: View {
    let icon: String
    let title: String
    let colors: [Color]
    
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: colors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .font(.title2)
            }
            
            Text(title)
                .foregroundColor(.white)
                .font(.body)
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let vm = TransactionViewModel(context: ctx)
    let acc = Account(context: ctx)
    acc.name = "Test"
    return EvaluationMenuView(accounts: [acc], viewModel: vm)
} 