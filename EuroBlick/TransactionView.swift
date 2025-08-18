import SwiftUI
import UIKit
import CoreData
import Foundation
import Dispatch
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Definiere die erlaubten Dateitypen
        let supportedTypes: [UTType] = [.commaSeparatedText, .text, .plainText]
        
        // Erstelle den Document Picker
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.delegate = context.coordinator
        
        // Setze das Startverzeichnis auf iCloud Drive
        if let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.deletingLastPathComponent() {
            picker.directoryURL = iCloudURL
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        
        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

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
    @State private var showAccountSelectionSheet = false
    @State private var selectedImportAccount: Account?
    @State private var pendingCSVImport: URL?
    @State private var showSuspiciousTransactionSheet = false
    @State private var suspiciousTransaction: TransactionViewModel.ImportResult.TransactionInfo?
    @State private var selectedBookingType: String? = nil
    @State private var showBookingSheet: Bool = false
    @State private var addTransactionType: String = "einnahme"

    private var isCSVImportEnabled: Bool {
        return account.value(forKey: "type") as? String == "bankkonto"
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
        filteredTransactions
            .filter { $0.categoryRelationship?.name == selectedCategory && $0.type != "reservierung" }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var customDateRangeDisplay: String {
        guard let range = customDateRange else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
    }

    private var searchTotalAmount: Double {
        let total = filteredTransactions
            .filter { $0.type != "reservierung" }
            .reduce(0.0) { $0 + $1.amount }
        return total.isNaN ? 0.0 : total
    }

    private var groupedTransactions: [TransactionGroup] {
        let validTransactions = filteredTransactions.filter { transaction in
            guard !transaction.isFault, !transaction.isDeleted else { return false }
            let date = transaction.date
            let timestamp = date.timeIntervalSince1970
            if timestamp.isNaN || timestamp <= 0 { return false }
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            guard components.isValidDate(in: Calendar.current),
                  let year = components.year, year >= 1970,
                  let month = components.month, month >= 1, month <= 12,
                  let day = components.day, day >= 1, day <= 31 else { return false }
            return true
        }
        let grouped = Dictionary(grouping: validTransactions, by: { transaction -> Date in
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day], from: transaction.date)
            return calendar.date(from: components) ?? Date()
        })
        var cumulativeBalance: Double = 0.0
        let sortedGroups = grouped.sorted { $0.key < $1.key }
        var result: [TransactionGroup] = []
        for (date, transactions) in sortedGroups {
            // Tagesbilanz: ALLE Transaktionen (inkl. Reservierung)
            let dailyBalance = transactions.reduce(0.0) { $0 + $1.amount }
            cumulativeBalance += dailyBalance
            let group = TransactionGroup(
                date: date,
                transactions: transactions.sorted { $0.date > $1.date },
                dailyBalance: dailyBalance,
                cumulativeBalance: cumulativeBalance
            )
            result.append(group)
        }
        return result.sorted { $0.date > $1.date }
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
                        Text("Gesamtbetrag: \(formatAmount(searchTotalAmount))")
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
                            .multilineTextAlignment(.center)
                            .padding(8)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity, alignment: .center)
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
                        },
                        onToggleExcludeFromBalance: toggleExcludeFromBalance
                    )
                    .id(refreshID)
                    .padding(.horizontal, 25)
                    
                    Spacer()
                    
                    BottomBarView(
                        isCSVImportEnabled: isCSVImportEnabled,
                        onExport: exportToCSV,
                        onImport: {
                            print("Import-Button gedrückt")
                            showDocumentPicker = true
                        },
                        onDateFilter: { showDatePickerSheet = true },
                        onAddTransaction: { showAddTransactionSheet = true }
                    )
                    .padding(.bottom, 5)
                    
                    // Drei Buchungsbuttons: Umbuchung links, Einnahme Mitte, Ausgabe rechts. Alle gleich groß.
                    HStack(spacing: 24) {
                        Button(action: {
                            selectedBookingType = "umbuchung"
                            showBookingSheet = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 60, height: 60)
                                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        Button(action: {
                            selectedBookingType = "einnahme"
                            showBookingSheet = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 60, height: 60)
                                    .shadow(color: .green.opacity(0.7), radius: showBookingSheet && selectedBookingType == "einnahme" ? 16 : 8, x: 0, y: 0)
                                    .scaleEffect(showBookingSheet && selectedBookingType == "einnahme" ? 1.12 : 1.0)
                                    .animation(.easeInOut(duration: 0.25), value: showBookingSheet && selectedBookingType == "einnahme")
                                Image(systemName: "plus")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        Button(action: {
                            selectedBookingType = "ausgabe"
                            showBookingSheet = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 60, height: 60)
                                    .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                                Image(systemName: "minus")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(account.name ?? "Unbekanntes Konto")
            .toolbar {
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
                CategoryManagementView(viewModel: viewModel, accountGroup: account.group)
            }
            .sheet(isPresented: $showAccountSelectionSheet) {
                NavigationView {
                    List {
                        ForEach(viewModel.getAllAccounts(), id: \.id) { account in
                            Button(action: {
                                selectedImportAccount = account
                                showAccountSelectionSheet = false
                                if let url = pendingCSVImport {
                                    handleCSVImport(url: url)
                                }
                            }) {
                                HStack {
                                    Text(account.name ?? "Unbekanntes Konto")
                                    Spacer()
                                    if selectedImportAccount?.id == account.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Konto auswählen")
                    .navigationBarItems(trailing: Button("Abbrechen") {
                        showAccountSelectionSheet = false
                        pendingCSVImport = nil
                    })
                }
            }
            .sheet(isPresented: $showSuspiciousTransactionSheet) {
                suspiciousTransactionSheet
            }
            .onAppear {
                fetchTransactions()
            }
            .onChange(of: viewModel.transactionsUpdated) { oldValue, newValue in
                fetchTransactions()
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
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in
                    print("CSV-Datei ausgewählt: \(url.path)")
                    handleCSVImport(url: url)
                }
            }
            // Sheet für neue Buchung
            .sheet(isPresented: $showBookingSheet) {
                if let bookingType = selectedBookingType {
                    VStack(spacing: 0) {
                        AddTransactionView(viewModel: viewModel, account: account, initialType: bookingType)
                            .onDisappear {
                                fetchTransactions()
                                print("AddTransactionSheet geschlossen")
                            }
                    }
                    .presentationDetents([.medium, .large])
                }
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
        let accountObjectID = self.account.objectID
        
        backgroundContext.perform {
            // Konvertiere das Account-Objekt für den Background Context
            guard let backgroundAccount = try? backgroundContext.existingObject(with: accountObjectID) as? Account else {
                print("🚫 Fehler: Account-Objekt konnte nicht für Background Context konvertiert werden")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "account == %@", backgroundAccount)
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
        let transactionsToDelete = offsets.map { filteredTransactions[$0] }
        viewModel.deleteTransactions(transactionsToDelete) {
            DispatchQueue.main.async {
                self.fetchTransactions()
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

    private func handleCSVImport(url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            print("CSV-Datei erfolgreich geladen: \(url.path)")

            let importResult = try viewModel.importBankCSV(contents: content, account: account, context: viewModel.getBackgroundContext())
            
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
                        
                        // Prüfe auf verdächtige Transaktionen
                        if !importResult.suspicious.isEmpty {
                            self.suspiciousTransaction = importResult.suspicious.first
                            self.showSuspiciousTransactionSheet = true
                        } else {
                            self.showImportAlert = true
                        }
                        
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

    private func formatBalance(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = NSNumber(value: abs(amount))
        let formattedAmount = formatter.string(from: number) ?? String(format: "%.2f", abs(amount))
        return amount >= 0 ? "\(formattedAmount) €" : "-\(formattedAmount) €"
    }

    // Sheet für verdächtige Transaktionen
    private var suspiciousTransactionSheet: some View {
        NavigationView {
            VStack {
                if let transaction = suspiciousTransaction {
                    List {
                        Section(header: Text("Verdächtige Transaktion")) {
                            HStack {
                                Text("Datum")
                                Spacer()
                                Text(transaction.date)
                            }
                            HStack {
                                Text("Betrag")
                                Spacer()
                                Text(String(format: "%.2f €", transaction.amount))
                            }
                            if let usage = transaction.usage {
                                HStack {
                                    Text("Zweck")
                                    Spacer()
                                    Text(usage)
                                }
                            }
                            HStack {
                                Text("Kategorie")
                                Spacer()
                                Text(transaction.category)
                            }
                        }
                        
                        if let existing = transaction.existingTransaction {
                            Section(header: Text("Bereits existierende Transaktion")) {
                                HStack {
                                    Text("Datum")
                                    Spacer()
                                    Text(dateFormatter.string(from: existing.date))
                                }
                                HStack {
                                    Text("Betrag")
                                    Spacer()
                                    Text(String(format: "%.2f €", existing.amount))
                                }
                                if let usage = existing.usage {
                                    HStack {
                                        Text("Zweck")
                                        Spacer()
                                        Text(usage)
                                    }
                                }
                                if let category = existing.categoryRelationship?.name {
                                    HStack {
                                        Text("Kategorie")
                                        Spacer()
                                        Text(category)
                                    }
                                }
                            }
                        }
                    }
                    
                    HStack {
                        Button("Überspringen") {
                            showSuspiciousTransactionSheet = false
                            if let nextSuspicious = importResult?.suspicious.dropFirst().first {
                                suspiciousTransaction = nextSuspicious
                            } else {
                                showImportAlert = true
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Importieren") {
                            // Hier die Transaktion importieren
                            showSuspiciousTransactionSheet = false
                            if let nextSuspicious = importResult?.suspicious.dropFirst().first {
                                suspiciousTransaction = nextSuspicious
                            } else {
                                showImportAlert = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("Verdächtige Transaktion")
            .navigationBarItems(trailing: Button("Abbrechen") {
                showSuspiciousTransactionSheet = false
                showImportAlert = true
            })
        }
    }

    private func toggleExcludeFromBalance(_ transactions: [Transaction]) {
        let context = PersistenceController.shared.container.viewContext
        
        // Überprüfe, ob alle ausgewählten Transaktionen bereits ausgeschlossen sind
        let allExcluded = transactions.allSatisfy { $0.excludeFromBalance }
        
        // Setze den neuen Wert (wenn alle ausgeschlossen sind, schließe sie ein, sonst schließe sie aus)
        let newValue = !allExcluded
        
        for transaction in transactions {
            transaction.excludeFromBalance = newValue
        }
        
        do {
            try context.save()
            // Aktualisiere die Ansicht
            fetchTransactions()
        } catch {
            print("❌ Fehler beim Speichern der excludeFromBalance-Änderungen: \(error)")
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let onEdit: (Transaction) -> Void
    let isSelected: Bool
    let isSelectionMode: Bool
    let onToggleSelection: () -> Void
    
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = NSNumber(value: amount)
        let formattedAmount = formatter.string(from: number) ?? String(format: "%.2f", amount)
        return "\(formattedAmount) €"
    }

    var body: some View {
        HStack {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .gray)
                    .imageScale(.large)
                    .padding(.leading, 8)
                    .animation(.easeInOut, value: isSelected)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transaction.categoryRelationship?.name ?? "Unbekannt")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    
                    // Zeige Icon für ausgeschlossene Transaktionen
                    if transaction.excludeFromBalance {
                        Image(systemName: "eye.slash.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                    }
                    
                    Spacer()
                    Text(formatAmount(transaction.amount))
                        .font(.caption)
                        .foregroundStyle(transaction.amount >= 0 ? .green : .red)
                }
                if let usage = transaction.usage, !usage.isEmpty {
                    Text(usage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.leading, 8)
                }
            }
            .padding(.vertical, 6)
        }
        .opacity(transaction.excludeFromBalance ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
                // Füge haptisches Feedback hinzu
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } else {
                onEdit(transaction)
            }
        }
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .animation(.easeInOut, value: isSelected)
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
    let onToggleExcludeFromBalance: ([Transaction]) -> Void
    @State private var selectedTransactions: Set<UUID> = []
    @State private var isSelectionMode: Bool = false
    @State private var longPressTransaction: Transaction? = nil

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM yyyy"
        return formatter
    }()

    var body: some View {
        VStack {
            if isSelectionMode {
                HStack {
                    Button(action: {
                        selectedTransactions.removeAll()
                        isSelectionMode = false
                    }) {
                        Text("Abbrechen")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    
                        Button(action: {
                            let selectedTrans = filteredTransactions.filter { selectedTransactions.contains($0.id) }
                            onToggleExcludeFromBalance(selectedTrans)
                            selectedTransactions.removeAll()
                            isSelectionMode = false
                        }) {
                            let hasExcluded = filteredTransactions.filter { selectedTransactions.contains($0.id) }.contains { $0.excludeFromBalance }
                            Text(hasExcluded ? "Einschließen" : "Ausschließen")
                            .font(.caption)
                                .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(6)
                        }
                        
                        Button(action: {
                            let indexSet = IndexSet(filteredTransactions.enumerated()
                                .filter { selectedTransactions.contains($0.element.id) }
                                .map { $0.offset })
                            onDelete(indexSet)
                            selectedTransactions.removeAll()
                            isSelectionMode = false
                        }) {
                            Text("Löschen (\(selectedTransactions.count))")
                            .font(.caption)
                                .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal)
            }

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
                            Text(group.dailyBalance.isNaN ? "(0,00 €)" : "(\(formatAmount(group.dailyBalance)))")
                                .foregroundColor(group.dailyBalance >= 0 ? .green : .red)
                                .font(.system(size: 12))
                            Text(group.cumulativeBalance.isNaN ? "0,00 €" : formatBalance(group.cumulativeBalance))
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
    }

    @ViewBuilder
    private func transactionRowView(transaction: Transaction) -> some View {
        TransactionRow(
            transaction: transaction,
            onEdit: onEdit,
            isSelected: selectedTransactions.contains(transaction.id),
            isSelectionMode: isSelectionMode,
            onToggleSelection: {
                if selectedTransactions.contains(transaction.id) {
                    selectedTransactions.remove(transaction.id)
                } else {
                    selectedTransactions.insert(transaction.id)
                }
            }
        )
        .listRowBackground(Color.gray.opacity(0.2))
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        .if(!isSelectionMode) { view in
            view.swipeActions(edge: .leading) {
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
        .onLongPressGesture(minimumDuration: 0.5) {
            if !isSelectionMode {
                isSelectionMode = true
                selectedTransactions.insert(transaction.id)
                // Füge haptisches Feedback hinzu
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
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
        return amount >= 0 ? "+\(formattedAmount) €" : "-\(formattedAmount) €"
    }

    private func formatBalance(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = NSNumber(value: abs(amount))
        let formattedAmount = formatter.string(from: number) ?? String(format: "%.2f", abs(amount))
        return amount >= 0 ? "\(formattedAmount) €" : "-\(formattedAmount) €"
    }
}

// Helper view modifier for conditional modifiers
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct BottomBarView: View {
    let isCSVImportEnabled: Bool
    let onExport: () -> Void
    let onImport: () -> Void
    let onDateFilter: () -> Void
    let onAddTransaction: () -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack {
                if isCSVImportEnabled {
                    HStack(spacing: 0) {
                        // CSV Export Button
                        TransactionActionButton(
                            action: onExport,
                            icon: "csv_export",
                            label: "Export",
                            color: .blue,
                            accessibilityLabel: "CSV Export"
                        )
                        .frame(width: geometry.size.width / (isCSVImportEnabled ? 4 : 2))
                        
                        // CSV Import Button
                        TransactionActionButton(
                            action: onImport,
                            icon: "csv_import",
                            label: "Import",
                            color: .blue,
                            accessibilityLabel: "CSV Import"
                        )
                        .frame(width: geometry.size.width / (isCSVImportEnabled ? 4 : 2))
                    }
                }
                
                // Datum Filter Button
                TransactionActionButton(
                    action: onDateFilter,
                    systemIcon: "calendar",
                    label: "Datum",
                    color: .orange,
                    accessibilityLabel: "Datum Filter"
                )
                .frame(width: geometry.size.width / (isCSVImportEnabled ? 4 : 2))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 70)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.98),
                        Color.black.opacity(0.95)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Top border line
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 1)
                .offset(y: -6)
            }
        )
        .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: -8)
    }
}

struct DatePickerSheetView: View {
    @Binding var selectedMonth: String
    @Binding var showDatePickerSheet: Bool
    @Binding var showCustomDateRangeSheet: Bool
    let availableMonths: [String]
    let onFilter: () -> Void
    @State private var searchText = ""

    var filteredMonths: [String] {
        if searchText.isEmpty {
            return availableMonths
        }
        return availableMonths.filter { $0.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                VStack(spacing: 16) {
                    // Suchfeld
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Suchen...", text: $searchText)
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    // Schnellauswahl-Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            selectedMonth = "Alle Monate"
                            onFilter()
                            showDatePickerSheet = false
                        }) {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundColor(.white)
                                    .frame(width: 24)
                                Text("Alle Monate")
                                    .foregroundColor(.white)
                                Spacer()
                                if selectedMonth == "Alle Monate" {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(10)
                        }
                        
                        Button(action: {
                            selectedMonth = "Benutzerdefinierter Zeitraum"
                            showDatePickerSheet = false
                            showCustomDateRangeSheet = true
                        }) {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundColor(.white)
                                    .frame(width: 24)
                                Text("Benutzerdefinierter Zeitraum")
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Verfügbare Monate Überschrift
                    HStack {
                        Text("Verfügbare Monate")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .padding(.horizontal)
                        Spacer()
                    }
                    
                    // Liste der Monate
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                            ForEach(filteredMonths.filter { 
                                $0 != "Alle Monate" && $0 != "Benutzerdefinierter Zeitraum"
                            }, id: \.self) { month in
                                Button(action: {
                                    selectedMonth = month
                                    onFilter()
                                    showDatePickerSheet = false
                                }) {
                                    HStack {
                                        Text(month)
                                            .foregroundColor(.white)
                                        Spacer()
                                        if selectedMonth == month {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.blue.opacity(selectedMonth == month ? 0.3 : 0.1))
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .navigationTitle("Zeitraum wählen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Fertig") {
                            showDatePickerSheet = false
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
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
    let accountGroup: AccountGroup?
    @Environment(\.dismiss) var dismiss
    @State private var editingCategory: Category?
    @State private var newCategoryName: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var addingNewCategory: String = "" // Für neue Kategorie hinzufügen
    @State private var sortedCategories: [Category] = []
    @State private var draggedCategory: Category?
    @State private var hasUnsavedChanges: Bool = false
    @State private var showSaveSuccess: Bool = false
    
    private var categorySectionHeader: some View {
        Text(accountGroup != nil ? "Kategorien für \(accountGroup!.name ?? "Gruppe") (\(sortedCategories.count))" : "Bestehende Kategorien (\(sortedCategories.count))")
            .foregroundColor(.white)
            .font(.headline)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {
                    List {
                        // Sektion für neue Kategorie hinzufügen
                        Section(header: Text("Neue Kategorie hinzufügen")
                            .foregroundColor(.blue)
                            .font(.headline)) {
                            HStack {
                                TextField("Kategoriename eingeben...", text: $addingNewCategory)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.gray.opacity(0.4))
                                    .cornerRadius(8)
                                
                                Button(action: {
                                    addNewCategory()
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(addingNewCategory.isEmpty ? .gray : .green)
                                }
                                .disabled(addingNewCategory.isEmpty)
                            }
                            .listRowBackground(Color.gray.opacity(0.1))
                        }
                        
                        // Sektion für bestehende Kategorien
                        Section(header: categorySectionHeader) {
                            ForEach(sortedCategories, id: \.self) { category in
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
                                .onDrag {
                                    draggedCategory = category
                                    return NSItemProvider(object: category.name as NSString? ?? NSString())
                                }
                                .onDrop(of: [.text], delegate: CategoryDropDelegate(
                                    category: category,
                                    draggedCategory: $draggedCategory,
                                    sortedCategories: $sortedCategories,
                                    onMove: moveCategory
                                ))
                            }
                            .onMove(perform: moveCategories)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    
                    // Änderungen Speichern Button
                    if hasUnsavedChanges {
                        Button(action: {
                            saveChanges()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Änderungen Speichern")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    }
                    
                    Button(action: {
                        if hasUnsavedChanges {
                            // Zeige Bestätigungsdialog
                            alertMessage = "Möchten Sie die Änderungen verwerfen?"
                            showAlert = true
                        } else {
                            dismiss()
                        }
                    }) {
                        Text(hasUnsavedChanges ? "Verwerfen" : "Schließen")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(hasUnsavedChanges ? Color.orange : Color.red)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Kategorien verwalten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if !addingNewCategory.isEmpty {
                            addNewCategory()
                        }
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(addingNewCategory.isEmpty ? .gray : .blue)
                    }
                    .disabled(addingNewCategory.isEmpty)
                }
            }
            .onAppear {
                initializeSortedCategories()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataDidChange"))) { _ in
                // Aktualisiere Kategorien nur wenn keine ungespeicherten Änderungen vorhanden sind
                if !hasUnsavedChanges {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        initializeSortedCategories()
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                if alertMessage.contains("verwerfen") {
                    Alert(
                        title: Text("Änderungen verwerfen?"),
                        message: Text(alertMessage),
                        primaryButton: .destructive(Text("Verwerfen")) {
                            dismiss()
                        },
                        secondaryButton: .cancel(Text("Abbrechen")) {
                            alertMessage = ""
                        }
                    )
                } else {
                    Alert(
                        title: Text("Fehler"),
                        message: Text(alertMessage),
                        dismissButton: .default(Text("OK")) {
                            alertMessage = ""
                        }
                    )
                }
            }
            .overlay(
                Group {
                    if showSaveSuccess {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Änderungen gespeichert!")
                                    .foregroundColor(.green)
                                    .font(.headline)
                            }
                            .padding()
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(10)
                            .padding(.bottom, 100)
                        }
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showSaveSuccess = false
                                }
                            }
                        }
                    }
                }
            )
        }
    }
    
    // Drop Delegate für Drag & Drop Funktionalität
    struct CategoryDropDelegate: DropDelegate {
        let category: Category
        @Binding var draggedCategory: Category?
        @Binding var sortedCategories: [Category]
        let onMove: (Category, Category) -> Void
        
        func performDrop(info: DropInfo) -> Bool {
            guard let draggedCategory = draggedCategory else { return false }
            
            if draggedCategory != category {
                onMove(draggedCategory, category)
            }
            
            self.draggedCategory = nil
            return true
        }
        
        func dropEntered(info: DropInfo) {
            // Optional: Visuelles Feedback beim Drag
        }
        
        func dropExited(info: DropInfo) {
            // Optional: Visuelles Feedback beim Drag
        }
    }
    
    // Initialisiere die sortierten Kategorien beim Erscheinen der View
    private func initializeSortedCategories() {
        let loadedCategories = loadCategoryOrder()
        sortedCategories = loadedCategories
        print("🔄 Kategorien initialisiert: \(loadedCategories.count) Kategorien geladen")
        
        // Debug: Zeige die geladenen Kategorien
        for (index, category) in loadedCategories.enumerated() {
            print("  \(index + 1). \(category.name ?? "Unbekannt")")
        }
    }
    
    // Lade die gespeicherte Reihenfolge der Kategorien
    private func loadCategoryOrder() -> [Category] {
        if let accountGroup = accountGroup {
            let categories = viewModel.getSortedCategories(for: accountGroup)
            print("📋 Lade Kategorien für Gruppe '\(accountGroup.name ?? "Unknown")': \(categories.count) Kategorien")
            return categories
        } else {
            let categories = viewModel.getSortedCategories()
            print("📋 Lade globale Kategorien: \(categories.count) Kategorien")
            return categories
        }
    }
    
    // Speichere die neue Reihenfolge der Kategorien
    private func saveCategoryOrder() {
        let order = sortedCategories.compactMap { $0.name }
        let key = accountGroup != nil ? "categoryOrder_\(accountGroup!.name ?? "default")" : "categoryOrder"
        UserDefaults.standard.set(order, forKey: key)
        
        print("💾 Kategorie-Reihenfolge gespeichert für Key '\(key)': \(order)")
        
        // Keine Notification hier, da wir die Kategorien lokal verwalten
        // Notification wird nur bei echten Datenänderungen aus anderen Views gesendet
    }
    
    // Speichere alle Änderungen
    private func saveChanges() {
        saveCategoryOrder()
        hasUnsavedChanges = false
        
        // Zeige Erfolgsmeldung
        withAnimation {
            showSaveSuccess = true
        }
        
        print("✅ Kategorie-Reihenfolge gespeichert")
        
        // Keine Neuinitialisierung nötig, da die Kategorien bereits korrekt sortiert sind
    }
    
    // Bewege eine Kategorie an eine neue Position
    private func moveCategory(from source: Category, to destination: Category) {
        guard let sourceIndex = sortedCategories.firstIndex(of: source),
              let destinationIndex = sortedCategories.firstIndex(of: destination) else {
            return
        }
        
        let category = sortedCategories.remove(at: sourceIndex)
        sortedCategories.insert(category, at: destinationIndex)
        hasUnsavedChanges = true
        
        print("🔄 Kategorie '\(category.name ?? "Unknown")' von Position \(sourceIndex) nach \(destinationIndex) verschoben")
    }
    
    // Bewege Kategorien mit onMove
    private func moveCategories(from source: IndexSet, to destination: Int) {
        sortedCategories.move(fromOffsets: source, toOffset: destination)
        hasUnsavedChanges = true
        
        print("🔄 Kategorien verschoben: \(source) nach \(destination)")
        print("📋 Neue Reihenfolge:")
        for (index, category) in sortedCategories.enumerated() {
            print("  \(index + 1). \(category.name ?? "Unknown")")
        }
    }

    // Neue Methode zum Hinzufügen einer Kategorie
    private func addNewCategory() {
        guard !addingNewCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Der Kategoriename darf nicht leer sein."
            showAlert = true
            return
        }
        
        let trimmedName = addingNewCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Prüfe ob Kategorie bereits existiert
        if let accountGroup = accountGroup {
            // Prüfe nur in der aktuellen Gruppe
            let groupCategories = viewModel.getSortedCategories(for: accountGroup)
            if groupCategories.contains(where: { $0.name?.lowercased() == trimmedName.lowercased() }) {
                alertMessage = "Eine Kategorie mit diesem Namen existiert bereits in dieser Gruppe."
                showAlert = true
                return
            }
            viewModel.addCategory(name: trimmedName, for: accountGroup) {
                DispatchQueue.main.async {
                    self.addingNewCategory = ""
                    // Aktualisiere die sortierten Kategorien nur wenn keine ungespeicherten Änderungen vorhanden sind
                    if !self.hasUnsavedChanges {
                        self.initializeSortedCategories()
                    } else {
                        // Füge die neue Kategorie zur aktuellen Liste hinzu
                        let newCategory = self.viewModel.categories.first { $0.name == trimmedName }
                        if let newCategory = newCategory {
                            self.sortedCategories.append(newCategory)
                        }
                    }
                    print("Neue Kategorie '\(trimmedName)' erfolgreich hinzugefügt")
                }
            }
        } else {
            // Prüfe global
            if viewModel.categories.contains(where: { $0.name?.lowercased() == trimmedName.lowercased() }) {
                alertMessage = "Eine Kategorie mit diesem Namen existiert bereits."
                showAlert = true
                return
            }
            viewModel.addCategory(name: trimmedName) {
                DispatchQueue.main.async {
                    self.addingNewCategory = ""
                    // Aktualisiere die sortierten Kategorien nur wenn keine ungespeicherten Änderungen vorhanden sind
                    if !self.hasUnsavedChanges {
                        self.initializeSortedCategories()
                    } else {
                        // Füge die neue Kategorie zur aktuellen Liste hinzu
                        let newCategory = self.viewModel.categories.first { $0.name == trimmedName }
                        if let newCategory = newCategory {
                            self.sortedCategories.append(newCategory)
                        }
                    }
                    print("Neue Kategorie '\(trimmedName)' erfolgreich hinzugefügt")
                }
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
                    // Aktualisiere die sortierten Kategorien nur wenn keine ungespeicherten Änderungen vorhanden sind
                    if !self.hasUnsavedChanges {
                        self.initializeSortedCategories()
                    }
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
                    // Aktualisiere die sortierten Kategorien nur wenn keine ungespeicherten Änderungen vorhanden sind
                    if !self.hasUnsavedChanges {
                        self.initializeSortedCategories()
                    } else {
                        // Entferne die gelöschte Kategorie aus der aktuellen Liste
                        self.sortedCategories.removeAll { $0.name == category.name }
                    }
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
