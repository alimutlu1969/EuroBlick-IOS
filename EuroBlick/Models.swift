import SwiftUI
import CoreData

// MARK: - Chart Data Models
struct MonthlyData: Identifiable {
    let id = UUID()
    let month: String
    let income: Double
    let expenses: Double
    let surplus: Double
    let incomeTransactions: [Transaction]
    let expenseTransactions: [Transaction]
    
    init(
        month: String,
        income: Double,
        expenses: Double,
        surplus: Double,
        incomeTransactions: [Transaction],
        expenseTransactions: [Transaction]
    ) {
        self.month = month
        self.income = income
        self.expenses = expenses
        self.surplus = surplus
        self.incomeTransactions = incomeTransactions
        self.expenseTransactions = expenseTransactions
    }
}

struct CategoryData: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
    let transactions: [Transaction]
    
    init(
        name: String,
        value: Double,
        color: Color,
        transactions: [Transaction]
    ) {
        self.name = name
        self.value = value
        self.color = color
        self.transactions = transactions
    }
}

struct ForecastData: Identifiable {
    let id = UUID()
    let month: String
    let einnahmen: Double
    let ausgaben: Double
    let balance: Double
    
    init(
        month: String,
        einnahmen: Double,
        ausgaben: Double,
        balance: Double
    ) {
        self.month = month
        self.einnahmen = einnahmen
        self.ausgaben = ausgaben
        self.balance = balance
    }
}

struct SegmentData: Identifiable {
    let id: UUID
    let name: String
    let value: Double
    let startAngle: Double
    let endAngle: Double
    
    var percentage: Double {
        (endAngle - startAngle) / (2 * .pi) * 100
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        value: Double,
        startAngle: Double,
        endAngle: Double
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.startAngle = startAngle
        self.endAngle = endAngle
    }
} 