import SwiftUI
import UIKit
import CoreData
import Foundation
import Dispatch

struct TransactionView: View {
    let account: Account
    @ObservedObject var viewModel: TransactionViewModel
    @State private var showAddTransactionSheet = false
    @State private var showEditTransactionSheet = false
    @State private var showDatePickerSheet = false
    @State private var showCustomDateRangeSheet = false
    @State private var showCategoryManagementSheet = false
    @State private var selectedTransactionID: UUID?
    @State private var transactions: [Transaction] = []
    @State private var filteredTransactions: [Transaction] = []
    @State private var filterMode: FilterMode = .all
    @State private var selectedCategory: String = ""
    @State private var selectedUsage: String = ""
    @State private var selectedMonth: String = "Alle Monate"
    @State private var customDateRange: (start: Date, end: Date)?
    @State private var tempStartDate: Date
    @State private var tempEndDate: Date
    @State private var showDocumentPicker = false
    @State private var showImportAlert = false
    @State private var importMessage = ""
    @State private var showImportResultSheet = false
    @State private var importResult: TransactionViewModel.ImportResult?
    @State private var refreshID = UUID()
    @State private var searchText: String = ""
    @State private var isLoading: Bool = true
    @State private var transactionToEdit: Transaction?
    @State private var isLoadingTransaction = false
    @State private var loadingError: String? = nil
    @State private var transactionCache: [UUID: Transaction] = [:]

    private var isGiroAccount: Bool {
        return account.name?.lowercased().contains("giro") ?? false
    }

    private var availableMonths: [String] {
        let transactionsWithDates = transactions.map { $0.date }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "de_DE")
        dateFormatter.dateFormat = "MMMM yyyy"
        let monthStrings = transactionsWithDates.map { dateFormatter.string(from: $0) }
        let uniqueMonths = Set(monthStrings)
        let sortedMonths = uniqueMonths.sorted(by: compareMonths)
        return ["Alle Monate", "Benutzerdefinierter Zeitraum"] + sortedMonths
    }

    private func compareMonths(_ month1: String, _ month2: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        if let date1 = formatter.date(from: month1), let date2 = formatter.date(from: month2) {
            return date1 > date2
        }
        return isGreaterThan(month1, month2)
    }

    private func isGreaterThan(_ month1: String, _ month2: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        if month1 == "Alle Monate" || month1 == "Benutzerdefinierter Zeitraum" {
            return true
        }
        if month2 == "Alle Monate" || month2 == "Benutzerdefinierter Zeitraum" {
            return false
        }
        guard let date1 = formatter.date(from: month1),
              let date2 = formatter.date(from: month2) else {
            return false
        }
        return date1 > date2
    }

    private var categorySum: Double {
        filteredTransactions.filter { $0.categoryRelationship?.name == selectedCategory }.reduce(0.0) { $0 + $1.amount }
    }

    private var customDateRangeDisplay: String {
        guard let range = customDateRange else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
    }

    private var searchTotalAmount: Double {
        let total = filteredTransactions.reduce(0.0) { $0 + $1.amount }
        return total.isNaN ? 0.0 : total
    }

    private var groupedTransactions: [TransactionGroup] {
        var cumulativeBalance: Double = viewModel.getBalance(for: account)
        if cumulativeBalance.isNaN {
            cumulativeBalance = 0.0
            print("Warnung: Kumulativer Kontostand ist NaN, auf 0.0 gesetzt")
        }
        
        let validTransactions = filteredTransactions.filter { transaction in
            guard !transaction.isFault, !transaction.isDeleted else {
                print("Ungültige Transaktion (gelöscht oder Fault): Transaktion ist ungültig")
                return false
            }
            
            let date = transaction.date
            let timestamp = date.timeIntervalSince1970
            if timestamp.isNaN || timestamp <= 0 {
                print("Ungültige Transaktion (ungültiges Datum): id=\(transaction.id.uuidString), date=\(date)")
                return false
            }
            
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            guard components.isValidDate(in: Calendar.current),
                  let year = components.year, year >= 1970,
                  let month = components.month, month >= 1, month <= 12,
                  let day = components.day, day >= 1, day <= 31 else {
                print("Ungültige Transaktion (ungültige Datumsbestandteile): id=\(transaction.id.uuidString), date=\(date), year=\(components.year ?? 0), month=\(components.month ?? 0), day=\(components.day ?? 0)")
                return false
            }
            
            return true
        }
        
        let grouped = Dictionary(grouping: validTransactions, by: { transaction -> Date in
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day], from: transaction.date)
            guard let groupedDate = calendar.date(from: components) else {
                print("Warnung: Ungültige Datumsgruppe für Transaktion: id=\(transaction.id.uuidString), date=\(transaction.date)")
                return Date()
            }
            return groupedDate
        })
        
        return grouped.map { (date, transactions) -> TransactionGroup in
            let dailyTransactions = transactions.sorted { $0.date > $1.date }
            var dailyBalance = dailyTransactions.reduce(0.0) { $0 + $1.amount }
            if dailyBalance.isNaN {
                dailyBalance = 0.0
                print("Warnung: Tagesbilanz ist NaN, auf 0.0 gesetzt für Datum: \(date)")
            }
            
            let group = TransactionGroup(
                date: date,
                transactions: dailyTransactions,
                dailyBalance: dailyBalance,
                cumulativeBalance: cumulativeBalance
            )
            
            cumulativeBalance -= dailyBalance
            if cumulativeBalance.isNaN {
                cumulativeBalance = 0.0
                print("Warnung: Kumulativer Kontostand ist NaN nach Update, auf 0.0 gesetzt")
            }
            return group
        }.sorted { $0.date > $1.date }
    }
    
    private var selectedTransaction: Transaction? {
        guard let id = selectedTransactionID else { 
            print("❌ Kein selectedTransactionID vorhanden")
            return nil 
        }
        
        // Versuche zuerst aus dem Cache zu laden
        if let cachedTransaction = transactionCache[id] {
            print("✅ Transaktion aus Cache geladen: id=\(id)")
            return cachedTransaction
        }
        
        // Versuche aus der aktuellen Liste zu laden
        if let transaction = transactions.first(where: { $0.id == id }) {
            print("✅ Transaktion aus Liste geladen: id=\(id)")
            // Speichere im Cache
            DispatchQueue.main.async {
                self.transactionCache[id] = transaction
            }
            return transaction
        }
        
        // Fallback: Direktes Abrufen aus Core Data
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            let results = try viewModel.getContext().fetch(fetchRequest)
            if let transaction = results.first {
                print("✅ Transaktion aus Core Data geladen: id=\(id)")
                // Speichere im Cache
                DispatchQueue.main.async {
                    self.transactionCache[id] = transaction
                }
                return transaction
            }
        } catch {
            print("🚫 Fehler beim Abrufen der Transaktion aus Core Data: \(error.localizedDescription)")
        }
        
        print("❌ Keine Transaktion gefunden für id=\(id)")
        return nil
    }

    enum FilterMode: String, CaseIterable, Identifiable {
        case all = "Alle"
        case category = "Kategorie"
        case usage = "V-Zweck"
        var id: String { self.rawValue }
    }

    init(account: Account, viewModel: TransactionViewModel) {
        self.account = account
        self.viewModel = viewModel
        let calendar = Calendar.current
        let currentDate = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) ?? currentDate
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? currentDate
        _tempStartDate = State(initialValue: startOfMonth)
        _tempEndDate = State(initialValue: endOfMonth)
        _customDateRange = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {
                    FilterSectionView(
                        filterMode: $filterMode,
                        selectedCategory: $selectedCategory,
                        selectedUsage: $selectedUsage,
                        uniqueCategories: uniqueCategories,
                        uniqueUsages: uniqueUsages,
                        categorySum: categorySum,
                        onFilterChange: applyFilter
                    )
                    
                    if !searchText.isEmpty {
                        Text("Gesamtbetrag: \(String(format: searchTotalAmount >= 0 ? "+%.2f €" : "%.2f €", searchTotalAmount))")
                            .foregroundColor(searchTotalAmount >= 0 ? .green : .red)
                            .font(.subheadline)
                            .padding(4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                    
                    ZStack(alignment: .center) {
                        if searchText.isEmpty {
                            Text("Suche nach Kategorie, V-Zweck oder Betrag...")
                                .foregroundColor(.gray.opacity(0.8))
                                .font(.system(size: 14))
                                .padding(.leading, 8)
                        }
                        TextField("", text: $searchText)
                            .font(.system(size: 16))
                            .padding(8)
                            .frame(height: 40)
                            .background(Color.gray.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .onChange(of: searchText) { oldValue, newValue in
                                applyFilter()
                            }
                    }
                    
                    TransactionListView(
                        filteredTransactions: filteredTransactions,
                        groupedTransactions: groupedTransactions,
                        isLoading: isLoading,
                        onDelete: deleteTransactions,
                        onEdit: { transaction in
                            loadTransactionForEditing(transaction)
                        }
                    )
                    .id(refreshID)
                    
                    Spacer()
                    
                    BottomBarView(
                        isGiroAccount: isGiroAccount,
                        onExport: exportToCSV,
                        onImport: {
                            print("Import-Button gedrückt")
                            showDocumentPicker = true
                        },
                        onDateFilter: { showDatePickerSheet = true },
                        onAddTransaction: { showAddTransactionSheet = true }
                    )
                    .padding(.bottom, 5)
                }
            }
            .navigationTitle(account.name ?? "Unbekanntes Konto")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        Button(action: {}) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.blue)
                        }
                        Text("Konten: ")
                            .foregroundColor(.white)
                        Text(account.name ?? "Unbekanntes Konto")
                            .foregroundColor(.blue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showCategoryManagementSheet = true
                    }) {
                        Image(systemName: "list.bullet")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showAddTransactionSheet) {
                AddTransactionView(viewModel: viewModel, account: account)
                    .onDisappear {
                        fetchTransactions()
                        print("AddTransactionSheet geschlossen")
                    }
            }
            .sheet(isPresented: $showEditTransactionSheet, onDismiss: {
                viewModel.getContext().performAndWait {
                    if let updatedTransaction = selectedTransaction {
                        viewModel.getContext().refresh(updatedTransaction, mergeChanges: true)
                    }
                }
                fetchTransactions()
                DispatchQueue.main.async {
                    applyFilter()
                    refreshID = UUID()
                }
                selectedTransactionID = nil
                isLoadingTransaction = false
                loadingError = nil
                showEditTransactionSheet = false
                print("EditTransactionSheet geschlossen")
            }) {
                if let transaction = selectedTransaction {
                    EditTransactionView(viewModel: viewModel, transaction: transaction)
                        .environment(\.managedObjectContext, viewModel.getContext())
                } else {
                    VStack {
                        Text("Fehler beim Laden der Transaktion")
                            .foregroundColor(.red)
                            .padding()
                        Button("Schließen") {
                            showEditTransactionSheet = false
                            selectedTransactionID = nil
                        }
                        .foregroundColor(.white)
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
            .sheet(isPresented: $showDatePickerSheet) {
                DatePickerSheetView(
                    selectedMonth: $selectedMonth,
                    showDatePickerSheet: $showDatePickerSheet,
                    showCustomDateRangeSheet: $showCustomDateRangeSheet,
                    availableMonths: availableMonths,
                    onFilter: applyFilter
                )
            }
            .sheet(isPresented: $showCustomDateRangeSheet) {
                CustomDateRangeSheetView(
                    tempStartDate: $tempStartDate,
                    tempEndDate: $tempEndDate,
                    customDateRange: $customDateRange,
                    selectedMonth: $selectedMonth,
                    showCustomDateRangeSheet: $showCustomDateRangeSheet,
                    onFilter: applyFilter
                )
            }
            .sheet(isPresented: $showCategoryManagementSheet) {
                CategoryManagementView(viewModel: viewModel)
            }
            .fileImporter(
                isPresented: $showDocumentPicker,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        print("Ausgewählte Datei: \(url.path)")
                        importFromCSV(url: url)
                    } else {
                        print("Keine Datei ausgewählt")
                        importMessage = "Keine Datei ausgewählt"
                        showImportAlert = true
                    }
                case .failure(let error):
                    print("Fehler beim Datei-Picker: \(error.localizedDescription)")
                    importMessage = "Fehler beim Öffnen der Datei: \(error.localizedDescription)"
                    showImportAlert = true
                }
            }
            .alert("Import abgeschlossen", isPresented: $showImportAlert) {
                Button("OK") {
                    showImportAlert = false
                }
                if importResult != nil {
                    Button("Details anzeigen") {
                        showImportResultSheet = true
                    }
                }
            } message: {
                Text(importMessage)
            }
            .onAppear {
                fetchTransactions()
            }
            .onChange(of: viewModel.transactionsUpdated) { oldValue, newValue in
                fetchTransactions()
            }
        }
    }

    private var uniqueCategories: [String] {
        let categories = transactions.compactMap { $0.categoryRelationship?.name }
        return Array(Set(categories)).sorted()
    }

    private var uniqueUsages: [String] {
        let usages = transactions.compactMap { $0.usage }
        return Array(Set(usages)).sorted()
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private func applyFilter() {
        var tempFiltered = transactions.filter { transaction in
            let date = transaction.date
            if selectedMonth == "Benutzerdefinierter Zeitraum", let range = customDateRange {
                return date >= range.start && date <= range.end
            } else if selectedMonth != "Alle Monate" {
                let transactionMonth = monthFormatter.string(from: date)
                if transactionMonth != selectedMonth {
                    return false
                }
            }
            
            switch filterMode {
            case .all:
                return true
            case .category:
                if selectedCategory.isEmpty {
                    return true
                } else {
                    return transaction.categoryRelationship?.name == selectedCategory
                }
            case .usage:
                if selectedUsage.isEmpty {
                    return true
                } else {
                    return transaction.usage == selectedUsage
                }
            }
        }

        if !searchText.isEmpty {
            let searchLowercased = searchText.lowercased()
            tempFiltered = tempFiltered.filter { transaction in
                let categoryMatch = (transaction.categoryRelationship?.name ?? "").lowercased().contains(searchLowercased)
                let usageMatch = (transaction.usage ?? "").lowercased().contains(searchLowercased)
                let amountMatch = String(format: "%.2f", transaction.amount).contains(searchLowercased)
                return categoryMatch || usageMatch || amountMatch
            }
        }

        filteredTransactions = tempFiltered
    }

    private func fetchTransactions() {
        let backgroundContext = viewModel.getBackgroundContext()
        backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "account == %@", self.account)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            fetchRequest.returnsObjectsAsFaults = false

            do {
                let fetchedInBackground = try backgroundContext.fetch(fetchRequest)
                let objectIDs = fetchedInBackground.map { $0.objectID }

                DispatchQueue.main.async {
                    let mainContext = viewModel.getContext()
                    self.clearTransactionCache() // Cache leeren bei Aktualisierung
                    self.transactions = objectIDs.compactMap { mainContext.object(with: $0) as? Transaction }
                    self.applyFilter()
                    self.isLoading = false
                    print("✅ Transaktionen erfolgreich geladen: \(self.transactions.count)")
                }
            } catch {
                print("🚫 Fehler beim Laden der Transaktionen: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }

    private func clearTransactionCache() {
        transactionCache.removeAll()
        print("🧹 Transaktions-Cache geleert")
    }

    func deleteTransactions(at offsets: IndexSet) {
        let sortedOffsets = offsets.sorted(by: >)
        
        var transactionsToDelete: [(index: Int, transaction: Transaction)] = []
        for index in sortedOffsets {
            guard index >= 0 && index < transactions.count else {
                print("Ungültiger Index \(index) für transactions mit Länge \(transactions.count)")
                continue
            }
            let transaction = transactions[index]
            transactionsToDelete.append((index: index, transaction: transaction))
        }
        
        for (index, transaction) in transactionsToDelete {
            viewModel.deleteTransaction(transaction) {
                guard index >= 0 && index < transactions.count else {
                    print("Index \(index) ist nach dem asynchronen Löschen ungültig")
                    return
                }
                
                transactions.remove(at: index)
            }
        }
    }

    private func exportToCSV() {
        var csvText = "Buchungstag,Kategorie,V-Zweck,Betrag\n"
        for transaction in filteredTransactions {
            let dateString = dateFormatter.string(from: transaction.date)
            let category = transaction.categoryRelationship?.name ?? "Unbekannt"
            let usage = transaction.usage ?? "Unbekannt"
            let amount = transaction.amount.isNaN ? "0.00 €" : String(format: "%.2f €", transaction.amount)
            csvText += "\(dateString),\(category),\(usage),\(amount)\n"
        }

        let fileName = "Transactions_\(Date().timeIntervalSince1970).csv"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csvText.write(to: path, atomically: true, encoding: .utf8)
            share(url: path)
        } catch {
            importMessage = "Fehler beim Exportieren: \(error.localizedDescription)"
            showImportAlert = true
        }
    }

    private func share(url: URL) {
        let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityController, animated: true, completion: nil)
        }
    }

    private func importFromCSV(url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            print("CSV-Datei erfolgreich geladen: \(url.path)")

            let importResult = try viewModel.importBankCSV(contents: content, context: viewModel.getBackgroundContext())
            
            viewModel.saveContext(viewModel.getBackgroundContext()) { error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.importMessage = "Fehler beim Speichern des Hintergrundkontexts: \(error.localizedDescription)"
                        self.showImportAlert = true
                        print("Fehler beim Speichern des Hintergrundkontexts: \(error)")
                    }
                    return
                }
                viewModel.saveContext(viewModel.getContext()) { error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.importMessage = "Fehler beim Speichern des Hauptkontexts: \(error.localizedDescription)"
                            self.showImportAlert = true
                            print("Fehler beim Speichern des Hauptkontexts: \(error)")
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self.importResult = importResult
                        self.importMessage = importResult.summary
                        self.showImportAlert = true
                        self.fetchTransactions()
                        self.applyFilter()
                        self.refreshID = UUID()
                        print("CSV-Import abgeschlossen: \(importResult.summary)")
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.importMessage = "Fehler beim CSV-Import: \(error.localizedDescription)"
                self.showImportAlert = true
                print("Fehler beim CSV-Import: \(error.localizedDescription)")
            }
        }
    }

    private func loadTransactionForEditing(_ transaction: Transaction) {
        selectedTransactionID = transaction.id
        viewModel.loadTransaction(transaction) { loadedTransaction in
            if let loadedTransaction = loadedTransaction {
                DispatchQueue.main.async {
                    self.selectedTransactionID = loadedTransaction.id
                    self.showEditTransactionSheet = true
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let onEdit: (Transaction) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(transaction.type?.capitalized ?? "Unbekannt")
                    .foregroundColor({
                        switch transaction.type {
                        case "einnahme":
                            return .green
                        case "ausgabe":
                            return .red
                        default:
                            return .white
                        }
                    }())
                    .font(.subheadline)
                    .padding(.leading, 8)
                Spacer()
                Text(transaction.amount.isNaN ? "0.00 €" : "\(String(format: "%.2f €", transaction.amount))")
                    .foregroundColor({
                        switch transaction.type {
                        case "einnahme":
                            return .green
                        case "ausgabe":
                            return .red
                        default:
                            return .white
                        }
                    }())
                    .font(.caption)
                    .padding(.trailing, 8)
            }
            Text(transaction.categoryRelationship?.name ?? "")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.leading, 8)
            if let usage = transaction.usage, !usage.isEmpty {
                Text(usage)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.leading, 8)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit(transaction)
        }
    }
}

struct TransactionGroup: Identifiable {
    let id = UUID()
    let date: Date
    let transactions: [Transaction]
    let dailyBalance: Double
    let cumulativeBalance: Double
}

struct FilterSectionView: View {
    @Binding var filterMode: TransactionView.FilterMode
    @Binding var selectedCategory: String
    @Binding var selectedUsage: String
    let uniqueCategories: [String]
    let uniqueUsages: [String]
    let categorySum: Double
    let onFilterChange: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            CustomSegmentedPicker(selectedSegment: $filterMode, segments: TransactionView.FilterMode.allCases.map { $0.rawValue })
                .padding(.horizontal)
                .padding(.vertical, 2)
                .onChange(of: filterMode) {
                    onFilterChange()
                }

            if filterMode == .category {
                Picker("Kategorie", selection: $selectedCategory) {
                    Text("Alle").tag("")
                    ForEach(uniqueCategories, id: \.self) { category in
                        if selectedCategory == category {
                            Text("\(category) (\(String(format: "%.2f €", categorySum)))").tag(category)
                        } else {
                            Text(category).tag(category)
                        }
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal)
                .padding(.vertical, 2)
                .foregroundColor(.white)
                .onChange(of: selectedCategory) {
                    onFilterChange()
                }
            } else if filterMode == .usage {
                Picker("V-Zweck", selection: $selectedUsage) {
                    Text("Alle").tag("")
                    ForEach(uniqueUsages, id: \.self) { usage in
                        Text(usage).tag(usage)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal)
                .padding(.vertical, 2)
                .foregroundColor(.white)
                .onChange(of: selectedUsage) {
                    onFilterChange()
                }
            }
        }
    }
}

struct TransactionListView: View {
    let filteredTransactions: [Transaction]
    let groupedTransactions: [TransactionGroup]
    let isLoading: Bool
    let onDelete: (IndexSet) -> Void
    let onEdit: (Transaction) -> Void

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM yyyy"
        return formatter
    }()

    var body: some View {
        if isLoading {
            Text("Lade Transaktionen...")
                .foregroundColor(.white)
                .padding()
        } else if filteredTransactions.isEmpty {
            Text("Keine Transaktion ausgewählt")
                .foregroundColor(.white)
        } else {
            List {
                ForEach(groupedTransactions, id: \.id) { group in
                    Section(header: HStack {
                        Text(dateFormatter.string(from: group.date))
                            .foregroundColor(.white)
                            .font(.system(size: 12))
                        Spacer()
                        Text(group.dailyBalance.isNaN ? "(0.00 €)" : "(\(String(format: group.dailyBalance >= 0 ? "+%.2f €" : "%.2f €", group.dailyBalance)))")
                            .foregroundColor(group.dailyBalance >= 0 ? .green : .red)
                            .font(.system(size: 12))
                        Text(group.cumulativeBalance.isNaN ? "0.00 €" : "\(String(format: "%.2f €", group.cumulativeBalance))")
                            .foregroundColor(group.cumulativeBalance >= 0 ? .green : .red)
                            .font(.system(size: 12))
                    }) {
                        ForEach(group.transactions, id: \.id) { transaction in
                            transactionRowView(transaction: transaction)
                        }
                    }
                }
            }
            .foregroundColor(.white)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func transactionRowView(transaction: Transaction) -> some View {
        TransactionRow(transaction: transaction, onEdit: onEdit)
            .listRowBackground(Color.gray.opacity(0.2))
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            .swipeActions(edge: .leading) {
                Button(action: {
                    onEdit(transaction)
                }) {
                    Label("Bearbeiten", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive, action: {
                    if let index = filteredTransactions.firstIndex(where: { $0.id == transaction.id }) {
                        let indexSet = IndexSet(integer: index)
                        onDelete(indexSet)
                    }
                }) {
                    Label("Löschen", systemImage: "trash")
                }
            }
    }
}

struct BottomBarView: View {
    let isGiroAccount: Bool
    let onExport: () -> Void
    let onImport: () -> Void
    let onDateFilter: () -> Void
    let onAddTransaction: () -> Void

    var body: some View {
        HStack {
            if isGiroAccount {
                Button(action: onExport) {
                    Image("csv_export")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .padding(5)
                        .background(
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 20, height: 20)
                                .cornerRadius(8)
                        )
                }
                Spacer()
                Button(action: onImport) {
                    Image("csv_import")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .padding(5)
                        .background(
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 20, height: 20)
                                .cornerRadius(8)
                        )
                }
                Spacer()
            }
            Button(action: onDateFilter) {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                    .font(.system(size: 30))
                    .padding(5)
                    .background(
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 20, height: 20)
                            .cornerRadius(8)
                    )
            }
            Spacer()
            Button(action: onAddTransaction) {
                Image(systemName: "plus")
                    .foregroundColor(.blue)
                    .font(.system(size: 30))
                    .padding(5)
                    .background(
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 20, height: 20)
                            .cornerRadius(8)
                    )
            }
        }
        .padding()
        .background(Color.black)
    }
}

struct DatePickerSheetView: View {
    @Binding var selectedMonth: String
    @Binding var showDatePickerSheet: Bool
    @Binding var showCustomDateRangeSheet: Bool
    let availableMonths: [String]
    let onFilter: () -> Void

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack {
                Text("Monat auswählen")
                    .foregroundColor(.white)
                    .font(.headline)
                    .padding()
                Picker("Monat auswählen", selection: $selectedMonth) {
                    ForEach(availableMonths, id: \.self) { month in
                        Text(month).tag(month)
                            .foregroundColor(.white)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding()
                .foregroundColor(.white)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                .onChange(of: selectedMonth) { oldValue, newValue in
                    if newValue == "Benutzerdefinierter Zeitraum" {
                        showDatePickerSheet = false
                        showCustomDateRangeSheet = true
                    }
                }
                Button(action: {
                    onFilter()
                    showDatePickerSheet = false
                }) {
                    Text("Filtern")
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 20)
        }
    }
}

struct CustomDateRangeSheetView: View {
    @Binding var tempStartDate: Date
    @Binding var tempEndDate: Date
    @Binding var customDateRange: (start: Date, end: Date)?
    @Binding var selectedMonth: String
    @Binding var showCustomDateRangeSheet: Bool
    let onFilter: () -> Void

    @State private var startDateString: String
    @State private var endDateString: String
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    init(tempStartDate: Binding<Date>,
         tempEndDate: Binding<Date>,
         customDateRange: Binding<(start: Date, end: Date)?>,
         selectedMonth: Binding<String>,
         showCustomDateRangeSheet: Binding<Bool>,
         onFilter: @escaping () -> Void) {
        self._tempStartDate = tempStartDate
        self._tempEndDate = tempEndDate
        self._customDateRange = customDateRange
        self._selectedMonth = selectedMonth
        self._showCustomDateRangeSheet = showCustomDateRangeSheet
        self.onFilter = onFilter
        self._startDateString = State(initialValue: dateFormatter.string(from: tempStartDate.wrappedValue))
        self._endDateString = State(initialValue: dateFormatter.string(from: tempEndDate.wrappedValue))
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack {
                Text("Benutzerdefinierten Zeitraum auswählen")
                    .foregroundColor(.white)
                    .font(.headline)
                    .padding()

                VStack(alignment: .leading) {
                    Text("Startdatum")
                        .foregroundColor(.white)
                        .font(.subheadline)
                    DatePicker("Startdatum", selection: $tempStartDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .foregroundColor(.white)
                        .accentColor(.blue)
                        .padding(.horizontal)
                        .onChange(of: startDateString) {
                            updateStartDateFromString()
                        }
                    TextField("dd.MM.yyyy", text: $startDateString, onEditingChanged: { isEditing in
                        if !isEditing {
                            updateStartDateFromString()
                        }
                    })
                        .padding(8)
                        .background(Color.gray.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .keyboardType(.numbersAndPunctuation)
                }

                VStack(alignment: .leading) {
                    Text("Enddatum")
                        .foregroundColor(.white)
                        .font(.subheadline)
                    DatePicker("Enddatum", selection: $tempEndDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .foregroundColor(.white)
                        .accentColor(.blue)
                        .padding(.horizontal)
                        .onChange(of: endDateString) {
                            updateEndDateFromString()
                        }
                    TextField("dd.MM.yyyy", text: $endDateString, onEditingChanged: { isEditing in
                        if !isEditing {
                            updateEndDateFromString()
                        }
                    })
                        .padding(8)
                        .background(Color.gray.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .keyboardType(.numbersAndPunctuation)
                }

                Button(action: {
                    customDateRange = (start: tempStartDate, end: tempEndDate)
                    onFilter()
                    showCustomDateRangeSheet = false
                }) {
                    Text("Bestätigen")
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                Button(action: {
                    customDateRange = nil
                    selectedMonth = monthFormatter.string(from: Date())
                    onFilter()
                    showCustomDateRangeSheet = false
                }) {
                    Text("Abbrechen")
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 20)
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Fehler"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func updateStartDateFromString() {
        if let newDate = dateFormatter.date(from: startDateString) {
            tempStartDate = newDate
        } else {
            alertMessage = "Ungültiges Startdatum. Bitte im Format dd.MM.yyyy eingeben (z. B. 01.05.2025)."
            showAlert = true
            startDateString = dateFormatter.string(from: tempStartDate)
        }
    }

    private func updateEndDateFromString() {
        if let newDate = dateFormatter.date(from: endDateString) {
            tempEndDate = newDate
        } else {
            alertMessage = "Ungültiges Enddatum. Bitte im Format dd.MM.yyyy eingeben (z. B. 01.06.2025)."
            showAlert = true
            endDateString = dateFormatter.string(from: tempEndDate)
        }
    }
}

struct CustomSegmentedPicker: UIViewRepresentable {
    @Binding var selectedSegment: TransactionView.FilterMode
    let segments: [String]

    func makeUIView(context: Context) -> UISegmentedControl {
        let segmentedControl = UISegmentedControl(items: segments)
        segmentedControl.selectedSegmentIndex = TransactionView.FilterMode.allCases.firstIndex(of: selectedSegment) ?? 0
        segmentedControl.selectedSegmentTintColor = UIColor.orange
        segmentedControl.backgroundColor = UIColor.gray.withAlphaComponent(0.5)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 14, weight: .medium)
        ]
        segmentedControl.setTitleTextAttributes(textAttributes, for: .normal)
        segmentedControl.setTitleTextAttributes(textAttributes, for: .selected)
        segmentedControl.addTarget(context.coordinator, action: #selector(Coordinator.segmentChanged(_:)), for: .valueChanged)
        
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            segmentedControl.heightAnchor.constraint(equalToConstant: 35)
        ])
        
        for index in 0..<segments.count {
            segmentedControl.setWidth(140, forSegmentAt: index)
        }
        
        return segmentedControl
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        uiView.selectedSegmentIndex = TransactionView.FilterMode.allCases.firstIndex(of: selectedSegment) ?? 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: CustomSegmentedPicker

        init(_ parent: CustomSegmentedPicker) {
            self.parent = parent
        }

        @objc func segmentChanged(_ sender: UISegmentedControl) {
            let index = sender.selectedSegmentIndex
            parent.selectedSegment = TransactionView.FilterMode.allCases[index]
        }
    }
}

struct CategoryManagementView: View {
    @ObservedObject var viewModel: TransactionViewModel
    @Environment(\.dismiss) var dismiss
    @State private var editingCategory: Category?
    @State private var newCategoryName: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {
                    List {
                        ForEach(viewModel.categories, id: \.self) { category in
                            CategoryRowView(
                                category: category,
                                isEditing: editingCategory == category,
                                newCategoryName: $newCategoryName,
                                onEdit: {
                                    editingCategory = category
                                    newCategoryName = category.name ?? ""
                                },
                                onSave: { saveEditedCategory(category) },
                                onCancel: {
                                    editingCategory = nil
                                    newCategoryName = ""
                                },
                                onDelete: { deleteCategory(category) }
                            )
                        }
                    }
                    .scrollContentBackground(.hidden)
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Schließen")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Kategorien verwalten")
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Fehler"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        alertMessage = ""
                    }
                )
            }
        }
    }

    private func saveEditedCategory(_ category: Category) {
        guard !newCategoryName.isEmpty else {
            alertMessage = "Der Kategoriename darf nicht leer sein."
            showAlert = true
            return
        }
        viewModel.updateCategory(category, newName: newCategoryName) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.alertMessage = "Fehler beim Bearbeiten der Kategorie: \(error.localizedDescription)"
                    self.showAlert = true
                    print("Fehler beim Bearbeiten der Kategorie: \(error)")
                } else {
                    self.editingCategory = nil
                    self.newCategoryName = ""
                    print("Kategorie erfolgreich bearbeitet: \(category.name ?? "Unbekannt")")
                }
            }
        }
    }

    private func deleteCategory(_ category: Category) {
        viewModel.deleteCategory(category) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.alertMessage = "Fehler beim Löschen der Kategorie: \(error.localizedDescription)"
                    self.showAlert = true
                    print("Fehler beim Löschen der Kategorie: \(error)")
                } else {
                    print("Kategorie erfolgreich gelöscht: \(category.name ?? "Unbekannt")")
                }
            }
        }
    }
}

struct CategoryRowView: View {
    let category: Category
    let isEditing: Bool
    @Binding var newCategoryName: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            if isEditing {
                CategoryEditView(
                    category: category,
                    newCategoryName: $newCategoryName,
                    onSave: onSave,
                    onCancel: onCancel
                )
            } else {
                CategoryDisplayView(
                    category: category,
                    onTap: onEdit
                )
            }
        }
        .listRowBackground(isEditing ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Löschen", systemImage: "trash")
            }
        }
    }
}

struct CategoryDisplayView: View {
    let category: Category
    let onTap: () -> Void

    var body: some View {
        Text(category.name ?? "Unbekannt")
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .onTapGesture {
                onTap()
            }
    }
}

struct CategoryEditView: View {
    let category: Category
    @Binding var newCategoryName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Neuer Name", text: $newCategoryName)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.4))
                .cornerRadius(8)
            HStack {
                Button(action: onSave) {
                    Text("Speichern")
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                Button(action: onCancel) {
                    Text("Abbrechen")
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}
