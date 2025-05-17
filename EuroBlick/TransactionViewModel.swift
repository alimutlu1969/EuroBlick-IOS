import Foundation
import CoreData
import SwiftUI
import Charts
import os.log

class TransactionViewModel: ObservableObject {
    @Published var accountGroups: [AccountGroup] = []
    @Published var categories: [Category] = []
    @Published var transactionsUpdated: Bool = false // Neue Property für Benachrichtigungen
    @Published var isLoadingTransaction: Bool = false
    @Published var loadingError: String? = nil
    private let context: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
        self.backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        self.backgroundContext.parent = context
        initializeData()
    }
    
    // Öffentliche Methode, um den Kontext bereitzustellen
    func getContext() -> NSManagedObjectContext {
        return context
    }
    
    // Öffentliche Methode, um den Hintergrundkontext bereitzustellen
    func getBackgroundContext() -> NSManagedObjectContext {
        return backgroundContext
    }
    
    // Zentrale Methode zum Speichern des Kontexts
    func saveContext(_ context: NSManagedObjectContext, completion: ((Error?) -> Void)? = nil) {
        context.perform {
            do {
                if context.hasChanges {
                    try context.save()
                    DispatchQueue.main.async {
                        self.transactionsUpdated.toggle() // Benachrichtige Views über Änderungen
                        completion?(nil)
                        print("Context saved successfully")
                    }
                } else {
                    DispatchQueue.main.async {
                        completion?(nil)
                        print("No changes to save in context")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("Error saving context: \(error)")
                    completion?(error)
                }
            }
        }
    }
    
    // Refreshe den Core Data-Kontext nur bei Bedarf
    func refreshContextIfNeeded() {
        context.performAndWait {
            context.refreshAllObjects()
            print("Core Data context refreshed")
        }
    }
    
    // Initialisiere die Daten (nur Kategorien, keine Kontogruppen/Konten)
    func initializeData() {
        context.perform {
            // Bereinige doppelte Kategorien zuerst
            self.removeDuplicateCategories()
            // Bereinige ungültige Transaktionen
            self.cleanupInvalidTransactions()
            // Korrigiere Jahreszahlen
            self.correctTransactionYears()
            
            self.fetchCategories()
            let defaultCategoryNames = [
                "Personal", "EC-Umbuchung", "Kasa", "KV-Beiträge", "Priv. KV",
                "Strom/Gas", "Verpackung", "Steuerberater", "Werbekosten",
                "Einnahmen", "Wareneinkauf", "Raumkosten", "Instandhaltung",
                "Reparatur", "Steuern", "Sonstiges"
            ]
            var addedCategories: Set<String> = []
            for name in defaultCategoryNames {
                if !addedCategories.contains(name) {
                    let request: NSFetchRequest<Category> = Category.fetchRequest()
                    request.predicate = NSPredicate(format: "name == %@", name)
                    let existing = try? self.context.fetch(request)
                    if existing?.isEmpty ?? true {
                        let newCategory = Category(context: self.context)
                        newCategory.name = name
                        addedCategories.insert(name)
                        print("Erstellte Kategorie: \(name)")
                    }
                }
            }
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Speichern der initialisierten Daten: \(error)")
                    return
                }
                self.fetchCategories()
                print("Initialisierte Standard-Kategorien: \(self.categories.count)")
                self.fetchAccountGroups()
            }
        }
    }
    
    // Bereinige doppelte Kategorien
    private func removeDuplicateCategories() {
        context.performAndWait {
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            guard let allCategories = try? self.context.fetch(request) else {
                print("Fehler beim Laden der Kategorien für Duplikatbereinigung")
                return
            }
            var seenNames: Set<String> = []
            var duplicatesDeleted = 0
            for category in allCategories {
                if let name = category.name, seenNames.contains(name) {
                    self.context.delete(category)
                    duplicatesDeleted += 1
                } else if let name = category.name {
                    seenNames.insert(name)
                }
            }
            if duplicatesDeleted > 0 {
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern nach Duplikatbereinigung: \(error)")
                        return
                    }
                    print("Entfernte \(duplicatesDeleted) doppelte Kategorien")
                }
            } else {
                print("Keine doppelten Kategorien gefunden")
            }
        }
    }
    
    // Bereinige ungültige Transaktionen (type=nil, amount=0.0, date=nil)
    private func cleanupInvalidTransactions() {
        context.performAndWait {
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            request.predicate = NSPredicate(format: "type == nil OR amount == 0 OR date == nil")
            guard let invalidTransactions = try? self.context.fetch(request) else {
                print("Fehler beim Laden ungültiger Transaktionen für Bereinigung")
                return
            }
            var deletedCount = 0
            for transaction in invalidTransactions {
                self.context.delete(transaction)
                deletedCount += 1
            }
            if deletedCount > 0 {
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern nach Bereinigung: \(error)")
                        return
                    }
                    print("Entfernte \(deletedCount) ungültige Transaktionen (type=nil, amount=0.0 oder date=nil)")
                }
            } else {
                print("Keine ungültigen Transaktionen gefunden")
            }
        }
    }
    
    // Hole alle Kontogruppen aus Core Data mit Beziehungen
    func fetchAccountGroups() {
        context.perform {
            let request: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            request.returnsObjectsAsFaults = false
            request.relationshipKeyPathsForPrefetching = ["accounts", "accounts.transactions"]
            do {
                let fetchedGroups = try self.context.fetch(request)
                DispatchQueue.main.async {
                    self.accountGroups = fetchedGroups
                    self.objectWillChange.send()
                    print("Fetched \(self.accountGroups.count) account groups: \(self.accountGroups.map { $0.name ?? "Unnamed" })")
                }
            } catch {
                print("Fetch account groups error: \(error)")
            }
        }
    }
    
    // Hole alle Kategorien aus Core Data
    func fetchCategories() {
        context.perform {
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            do {
                let fetchedCategories = try self.context.fetch(request)
                // Filtere leere Kategorien heraus
                let filteredCategories = fetchedCategories.filter { category in
                    guard let name = category.name else { return false }
                    return !name.isEmpty
                }
                DispatchQueue.main.async {
                    self.categories = filteredCategories
                    print("Fetched \(self.categories.count) categories: \(self.categories.map { $0.name ?? "Unnamed" })")
                }
            } catch {
                print("Fetch categories error: \(error)")
            }
        }
    }
    
    // Bereinige doppelte Transaktionen
    func removeDuplicateTransactions() {
        context.performAndWait {
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            guard let allTransactions = try? self.context.fetch(request) else {
                print("Fehler beim Laden der Transaktionen für Duplikatbereinigung")
                return
            }
            var seenIDs: Set<UUID> = []
            var duplicatesDeleted = 0
            for transaction in allTransactions {
                if seenIDs.contains(transaction.id) {
                    self.context.delete(transaction)
                    duplicatesDeleted += 1
                } else {
                    seenIDs.insert(transaction.id)
                }
            }
            if duplicatesDeleted > 0 {
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern nach Duplikatbereinigung: \(error)")
                        return
                    }
                    print("Entfernte \(duplicatesDeleted) doppelte Transaktionen")
                }
            } else {
                print("Keine doppelten Transaktionen gefunden")
            }
        }
    }
    
    // Berechne den Kontostand für ein Konto
    func getBalance(for account: Account) -> Double {
        let context = self.context
        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: "Transaction")

        fetchRequest.predicate = NSPredicate(format: "account == %@", account)
        fetchRequest.resultType = .dictionaryResultType

        let expressionDesc = NSExpressionDescription()
        expressionDesc.name = "totalAmount"
        expressionDesc.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "amount")])
        expressionDesc.expressionResultType = .doubleAttributeType

        fetchRequest.propertiesToFetch = [expressionDesc]

        do {
            if let result = try context.fetch(fetchRequest).first,
               let total = result["totalAmount"] as? Double {
                return total
            }
        } catch {
            print("Fehler beim Berechnen des Kontostands: \(error.localizedDescription)")
        }

        return 0.0
    }

    
    // Füge eine neue Kategorie hinzu
    func addCategory(name: String, completion: (() -> Void)? = nil) {
        context.perform {
            guard !name.isEmpty else {
                print("Fehler: Kategoriename darf nicht leer sein")
                completion?()
                return
            }
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", name)
            let existing = try? self.context.fetch(request)
            if existing?.isEmpty ?? true {
                let newCategory = Category(context: self.context)
                newCategory.name = name
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern der neuen Kategorie: \(error)")
                        completion?()
                        return
                    }
                    self.fetchCategories()
                    print("Kategorie \(name) hinzugefügt")
                    completion?()
                }
            } else {
                print("Kategorie \(name) existiert bereits")
                completion?()
            }
        }
    }
    
    // Bearbeite eine bestehende Kategorie
    func updateCategory(_ category: Category, newName: String, completion: ((Error?) -> Void)? = nil) {
        context.perform {
            guard !newName.isEmpty else {
                let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kategoriename darf nicht leer sein"])
                print("Fehler: Kategoriename darf nicht leer sein")
                completion?(error)
                return
            }
            // Prüfe, ob der neue Name bereits existiert
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@ AND self != %@", newName, category)
            let existing = try? self.context.fetch(request)
            if !(existing?.isEmpty ?? true) {
                let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kategorie mit diesem Namen existiert bereits"])
                print("Fehler: Kategorie mit Name \(newName) existiert bereits")
                completion?(error)
                return
            }
            category.name = newName
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Speichern der aktualisierten Kategorie: \(error)")
                    completion?(error)
                    return
                }
                self.fetchCategories()
                print("Kategorie auf \(newName) aktualisiert")
                completion?(nil)
            }
        }
    }
    
    // Lösche eine Kategorie und weise verknüpfte Transaktionen der Kategorie "Sonstiges" zu
    func deleteCategory(_ category: Category, completion: ((Error?) -> Void)? = nil) {
        context.perform {
            guard let categoryName = category.name, categoryName != "Sonstiges" else {
                let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kategorie 'Sonstiges' kann nicht gelöscht werden"])
                print("Fehler: Kategorie 'Sonstiges' kann nicht gelöscht werden")
                completion?(error)
                return
            }
            // Finde die Standardkategorie "Sonstiges"
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", "Sonstiges")
            guard let sonstigesCategory = try? self.context.fetch(request).first else {
                let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Standardkategorie 'Sonstiges' nicht gefunden"])
                print("Fehler: Standardkategorie 'Sonstiges' nicht gefunden")
                completion?(error)
                return
            }
            // Finde alle Transaktionen mit dieser Kategorie
            let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            transactionRequest.predicate = NSPredicate(format: "categoryRelationship == %@", category)
            if let transactions = try? self.context.fetch(transactionRequest) {
                for transaction in transactions {
                    transaction.categoryRelationship = sonstigesCategory
                }
                print("Umgestellt: \(transactions.count) Transaktionen auf Kategorie 'Sonstiges'")
            }
            // Lösche die Kategorie
            self.context.delete(category)
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Speichern nach Löschen der Kategorie: \(error)")
                    completion?(error)
                    return
                }
                self.fetchCategories()
                print("Kategorie \(categoryName) gelöscht")
                completion?(nil)
            }
        }
    }
    
    // Füge eine neue Kontogruppe hinzu
    func addAccountGroup(name: String, completion: (() -> Void)? = nil) {
        context.perform {
            let newGroup = AccountGroup(context: self.context)
            newGroup.name = name
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Speichern der neuen Kontogruppe: \(error)")
                    completion?()
                    return
                }
                self.fetchAccountGroups()
                print("Kontogruppe \(name) hinzugefügt")
                completion?()
            }
        }
    }
    
    // Lösche eine Kontogruppe
    func deleteAccountGroup(_ group: AccountGroup, completion: (() -> Void)? = nil) {
        context.perform {
            self.context.delete(group)
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Speichern nach Löschen der Kontogruppe: \(error)")
                    completion?()
                    return
                }
                self.fetchAccountGroups()
                print("Kontogruppe \(group.name ?? "unknown") gelöscht")
                completion?()
            }
        }
    }
    
    // Füge ein neues Konto zu einer Gruppe hinzu
    func addAccount(name: String, group: AccountGroup, icon: String = "banknote.fill", color: Color = .blue) {
        print("DEBUG: TransactionViewModel.addAccount - Start")
        print("DEBUG: Name: \(name)")
        print("DEBUG: Gruppe: \(group.name ?? "unknown")")
        print("DEBUG: Gruppen-ID: \(group.objectID)")
        print("DEBUG: Kontext der Gruppe: \(String(describing: group.managedObjectContext))")
        print("DEBUG: Hauptkontext: \(context)")

        do {
            // Hole die Gruppe in den richtigen Kontext
            guard let groupInContext = try self.context.existingObject(with: group.objectID) as? AccountGroup else {
                print("DEBUG: FEHLER - Konnte Gruppe nicht in Hauptkontext finden")
                return
            }
            
            print("DEBUG: Gruppe erfolgreich in Hauptkontext geholt")
            
            // Erstelle das Konto im richtigen Kontext
            let account = Account(context: self.context)
            account.name = name
            account.group = groupInContext
            account.setValue(icon, forKey: "icon")
            account.setValue(color.toHex(), forKey: "iconColor")
            
            print("DEBUG: Account erstellt und Eigenschaften gesetzt")
            
            // Speichere den Kontext
            try self.context.save()
            print("DEBUG: Kontext erfolgreich gespeichert")
            
            // Aktualisiere die UI sofort im Hauptthread
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.fetchAccountGroups()
                self.transactionsUpdated.toggle()
                print("DEBUG: UI aktualisiert")
                print("DEBUG: Account \(name) erfolgreich zur Gruppe \(groupInContext.name ?? "unknown") hinzugefügt")
                
                // Sende eine zusätzliche Änderungsbenachrichtigung
                NotificationCenter.default.post(name: NSNotification.Name("AccountsDidChange"), object: nil)
            }
        } catch {
            print("DEBUG: FEHLER beim Erstellen des Accounts: \(error)")
            // Versuche den Kontext zurückzusetzen
            self.context.rollback()
        }
    }
    
    // Aktualisiere eine bestehende Kontogruppe
    func updateAccountGroup(group: AccountGroup, name: String, completion: (() -> Void)? = nil) {
        context.perform {
            group.name = name
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Speichern der aktualisierten Kontogruppe: \(error)")
                    completion?()
                    return
                }
                self.fetchAccountGroups()
                print("Kontogruppe auf \(name) aktualisiert")
                completion?()
            }
        }
    }
    
    // Füge eine neue Transaktion hinzu
    func addTransaction(type: String, amount: Double, category: String, account: Account, targetAccount: Account?, usage: String?, date: Date, completion: ((Error?) -> Void)? = nil) {
        guard !type.isEmpty, ["einnahme", "ausgabe", "umbuchung"].contains(type) else {
            let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Transaktionstyp"])
            print("Fehler: Ungültiger Transaktionstyp")
            completion?(error)
            return
        }
        guard amount != 0 else {
            let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Betrag darf nicht 0 sein"])
            print("Fehler: Betrag darf nicht 0 sein")
            completion?(error)
            return
        }
        guard !category.isEmpty else {
            let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kategorie darf nicht leer sein"])
            print("Fehler: Kategorie darf nicht leer sein")
            completion?(error)
            return
        }
        context.perform {
            if type == "umbuchung", let target = targetAccount {
                let sourceTransaction = Transaction(context: self.context)
                sourceTransaction.id = UUID()
                sourceTransaction.type = "umbuchung"
                sourceTransaction.amount = -amount
                sourceTransaction.date = date
                sourceTransaction.account = account
                sourceTransaction.targetAccount = target
                sourceTransaction.usage = usage
                
                // Prüfe, ob es sich um eine Bargeld-zu-Giro Umbuchung handelt
                let isBarToGiro = account.name?.lowercased().contains("bargeld") ?? false &&
                                 target.name?.lowercased().contains("giro") ?? false
                
                // Nur wenn es KEINE Bargeld-zu-Giro Umbuchung ist, erstelle die Zieltransaktion
                if !isBarToGiro {
                    let targetTransaction = Transaction(context: self.context)
                    targetTransaction.id = UUID()
                    targetTransaction.type = "umbuchung"
                    targetTransaction.amount = amount
                    targetTransaction.date = date
                    targetTransaction.account = target
                    targetTransaction.targetAccount = account
                    targetTransaction.usage = usage
                    
                    self.setCategoryForTransaction(targetTransaction, categoryName: category)
                }
                
                self.setCategoryForTransaction(sourceTransaction, categoryName: category)
                
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern der Umbuchung: \(error)")
                        completion?(error)
                        return
                    }
                    self.cleanupInvalidTransactions()
                    self.fetchAccountGroups()
                    print("Umbuchung hinzugefügt: \(amount) von \(account.name ?? "unknown") zu \(target.name ?? "unknown")")
                    // Erstelle ein automatisches Backup nach der Umbuchung
                    if let backupURL = self.backupData() {
                        print("Automatisches Backup nach Umbuchung erstellt: \(backupURL)")
                    } else {
                        print("Fehler beim Erstellen des automatischen Backups nach Umbuchung")
                    }
                    completion?(nil)
                }
            } else {
                let newTransaction = Transaction(context: self.context)
                newTransaction.id = UUID()
                newTransaction.type = type
                newTransaction.amount = amount.isNaN ? 0.0 : amount
                newTransaction.date = date
                newTransaction.account = account
                newTransaction.targetAccount = targetAccount
                newTransaction.usage = usage
                
                self.setCategoryForTransaction(newTransaction, categoryName: category)
                
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern der Transaktion: \(error)")
                        completion?(error)
                        return
                    }
                    self.cleanupInvalidTransactions()
                    self.fetchAccountGroups()
                    print("Transaktion hinzugefügt: type=\(type), amount=\(amount), Kategorie=\(category), usage=\(usage ?? "nil")")
                    // Erstelle ein automatisches Backup nach der Transaktion
                    if let backupURL = self.backupData() {
                        print("Automatisches Backup nach Transaktion erstellt: \(backupURL)")
                    } else {
                        print("Fehler beim Erstellen des automatischen Backups nach Transaktion")
                    }
                    completion?(nil)
                }
            }
        }
    }
    
    // Hilfsmethode zum Setzen der Kategorie
    private func setCategoryForTransaction(_ transaction: Transaction, categoryName: String) {
        guard !categoryName.isEmpty else {
            print("Kategorie darf nicht leer sein")
            return
        }
        let categoryObject = categories.first { $0.name == categoryName } ?? Category(context: context)
        if categoryObject.name == nil {
            categoryObject.name = categoryName
        }
        transaction.categoryRelationship = categoryObject
    }
    
    // Lösche eine Transaktion
    func deleteTransaction(_ transaction: Transaction, completion: (() -> Void)? = nil) {
        context.perform {
            // Sicherheitsüberprüfung für transaction.id
            let transactionId = transaction.id.uuidString
            self.context.delete(transaction)
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Speichern nach Löschen der Transaktion: \(error)")
                    completion?()
                    return
                }
                self.fetchAccountGroups()
                print("Transaktion gelöscht: id=\(transactionId)")
                completion?()
            }
        }
    }
    
    // Aktualisiere eine bestehende Transaktion
    func updateTransaction(_ transaction: Transaction, type: String, amount: Double, category: String, account: Account, targetAccount: Account?, usage: String?, date: Date, completion: (() -> Void)? = nil) {
        guard !type.isEmpty, ["einnahme", "ausgabe", "umbuchung"].contains(type) else {
            print("Fehler: Ungültiger Transaktionstyp")
            return
        }
        guard amount != 0 else {
            print("Fehler: Betrag darf nicht 0 sein")
            return
        }
        guard !category.isEmpty else {
            print("Fehler: Kategorie darf nicht leer sein")
            return
        }
        context.perform {
            if type == "umbuchung", let target = targetAccount {
                self.context.delete(transaction)
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern nach Löschen der alten Transaktion: \(error)")
                        completion?()
                        return
                    }
                    
                    let sourceTransaction = Transaction(context: self.context)
                    sourceTransaction.id = UUID()
                    sourceTransaction.type = "umbuchung"
                    sourceTransaction.amount = -amount
                    sourceTransaction.date = date
                    sourceTransaction.account = account
                    sourceTransaction.targetAccount = target
                    sourceTransaction.usage = usage
                    
                    // Prüfe, ob es sich um eine Bargeld-zu-Giro Umbuchung handelt
                    let isBarToGiro = account.name?.lowercased().contains("bargeld") ?? false &&
                                     target.name?.lowercased().contains("giro") ?? false
                    
                    // Nur wenn es KEINE Bargeld-zu-Giro Umbuchung ist, erstelle die Zieltransaktion
                    if !isBarToGiro {
                        let targetTransaction = Transaction(context: self.context)
                        targetTransaction.id = UUID()
                        targetTransaction.type = "umbuchung"
                        targetTransaction.amount = amount
                        targetTransaction.date = date
                        targetTransaction.account = target
                        targetTransaction.targetAccount = account
                        targetTransaction.usage = usage
                        
                        self.setCategoryForTransaction(targetTransaction, categoryName: category)
                    }
                    
                    self.setCategoryForTransaction(sourceTransaction, categoryName: category)
                    
                    self.saveContext(self.context) { error in
                        if let error = error {
                            print("Fehler beim Speichern der aktualisierten Umbuchung: \(error)")
                            completion?()
                            return
                        }
                        self.cleanupInvalidTransactions()
                        self.fetchAccountGroups()
                        print("Umbuchung aktualisiert: \(amount) von \(account.name ?? "unknown") zu \(target.name ?? "unknown")")
                        completion?()
                    }
                }
            } else {
                transaction.id = transaction.id
                transaction.type = type
                transaction.amount = amount.isNaN ? 0.0 : amount
                transaction.date = date
                transaction.account = account
                transaction.targetAccount = targetAccount
                transaction.usage = usage
                
                self.setCategoryForTransaction(transaction, categoryName: category)
                
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern der aktualisierten Transaktion: \(error)")
                        completion?()
                        return
                    }
                    self.cleanupInvalidTransactions()
                    self.fetchAccountGroups()
                    print("Transaktion aktualisiert: type=\(type), amount=\(amount), Kategorie=\(category), usage=\(usage ?? "nil")")
                    completion?()
                }
            }
        }
    }
    
    // Berechne die Kategorien-Daten für das Tortendiagramm
    func buildCategoryData(for account: Account) -> [CategoryData] {
        context.performAndWait {
            let transactions = (account.transactions?.allObjects as? [Transaction]) ?? []
            var categoryTotals: [String: Double] = [:]
            for transaction in transactions {
                if transaction.type == "ausgabe", let category = transaction.categoryRelationship?.name {
                    categoryTotals[category, default: 0.0] += transaction.amount
                }
            }
            let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange]
            return categoryTotals.enumerated().map { (index, element) in
                CategoryData(name: element.key, value: element.value, color: colors[index % colors.count], transactions: transactions.filter { $0.categoryRelationship?.name == element.key })
            }
        }
    }
    
    // Berechne die monatliche Daten für das Balkendiagramm
    func buildMonthlyData(for account: Account) -> [MonthlyData] {
        context.performAndWait {
            let transactions = (account.transactions?.allObjects as? [Transaction]) ?? []
            var monthlyEinnahmen: [String: Double] = [:]
            var monthlyAusgaben: [String: Double] = [:]
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM yyyy"
            for transaction in transactions {
                let monthKey = dateFormatter.string(from: transaction.date)
                if transaction.type == "einnahme" {
                    monthlyEinnahmen[monthKey, default: 0.0] += transaction.amount
                } else if transaction.type == "ausgabe" {
                    monthlyAusgaben[monthKey, default: 0.0] += transaction.amount
                }
            }
            let allMonths = Set(monthlyEinnahmen.keys).union(monthlyAusgaben.keys)
            return allMonths.sorted().map { month in
                let einnahmen = monthlyEinnahmen[month] ?? 0.0
                let ausgaben = monthlyAusgaben[month] ?? 0.0
                return MonthlyData(
                    month: month,
                    income: einnahmen,
                    expenses: ausgaben,
                    surplus: einnahmen - ausgaben,
                    incomeTransactions: [],
                    expenseTransactions: []
                )
            }
        }
    }
    
    // Korrigiere Jahreszahlen von Transaktionen (z. B. 0025 zu 2025)
    func correctTransactionYears() {
        context.performAndWait {
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            guard let allTransactions = try? self.context.fetch(request) else {
                print("Fehler beim Laden der Transaktionen für Jahreskorrektur")
                return
            }
            
            let calendar = Calendar.current
            var correctedCount = 0
            
            for transaction in allTransactions {
                let date = transaction.date
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                if let year = components.year, year < 100 {
                    components.year = year + 2000 // Konvertiere z. B. 25 zu 2025
                    if let correctedDate = calendar.date(from: components) {
                        transaction.date = correctedDate
                        correctedCount += 1
                    }
                }
            }
            
            if correctedCount > 0 {
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern nach Jahreskorrektur: \(error)")
                        return
                    }
                    print("Korrigierte \(correctedCount) Transaktionen (Jahr von z. B. 0025 zu 2025)")
                    self.fetchAccountGroups() // Aktualisiere die Konten
                }
            } else {
                print("Keine Transaktionen zur Korrektur gefunden")
            }
        }
    }
    
    // Erstelle ein Backup der Daten als JSON-Datei im MeinDrive-Ordner
    func backupData() -> URL? {
        context.performAndWait {
            // Hole alle Kontogruppen, Konten, Transaktionen und Kategorien
            let groupsRequest: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
            let accountsRequest: NSFetchRequest<Account> = Account.fetchRequest()
            let transactionsRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            let categoriesRequest: NSFetchRequest<Category> = Category.fetchRequest()
            
            guard let groups = try? context.fetch(groupsRequest),
                  let accounts = try? context.fetch(accountsRequest),
                  let transactions = try? context.fetch(transactionsRequest),
                  let categories = try? context.fetch(categoriesRequest) else {
                print("Fehler beim Abrufen der Daten für Backup")
                return nil
            }
            
            // Erstelle ein Dictionary mit allen Daten
            var backupData: [String: Any] = [:]
            
            // Kontogruppen
            let groupsData = groups.map { group -> [String: Any] in
                return [
                    "name": group.name ?? "",
                    "accounts": (group.accounts?.allObjects as? [Account])?.map { $0.name ?? "" } ?? []
                ]
            }
            backupData["accountGroups"] = groupsData
            
            // Konten
            let accountsData = accounts.map { account -> [String: Any] in
                return [
                    "name": account.name ?? "",
                    "group": account.group?.name ?? "",
                    "transactions": (account.transactions?.allObjects as? [Transaction])?.map { $0.id.uuidString } ?? []
                ]
            }
            backupData["accounts"] = accountsData
            
            // Transaktionen
            let transactionsData = transactions.map { transaction -> [String: Any] in
                return [
                    "id": transaction.id.uuidString,
                    "type": transaction.type ?? "",
                    "amount": transaction.amount,
                    "date": transaction.date.timeIntervalSince1970, // Speichere Datum als Timestamp
                    "category": transaction.categoryRelationship?.name ?? "",
                    "account": transaction.account?.name ?? "",
                    "targetAccount": transaction.targetAccount?.name ?? "",
                    "usage": transaction.usage ?? ""
                ]
            }
            backupData["transactions"] = transactionsData
            
            // Kategorien
            let categoriesData = categories.map { category -> [String: Any] in
                return [
                    "name": category.name ?? ""
                ]
            }
            backupData["categories"] = categoriesData
            
            // Konvertiere in JSON
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: backupData, options: .prettyPrinted)
                
                // Speichere die JSON-Datei im MeinDrive-Ordner
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let meinDrivePath = documentsDirectory.appendingPathComponent("MeinDrive")
                
                // Erstelle den MeinDrive-Ordner, falls er nicht existiert
                try FileManager.default.createDirectory(at: meinDrivePath, withIntermediateDirectories: true, attributes: nil)
                
                // Erstelle die Backup-Datei mit einem Zeitstempel
                let backupURL = meinDrivePath.appendingPathComponent("EuroBlickBackup_\(Int(Date().timeIntervalSince1970)).json")
                try jsonData.write(to: backupURL)
                print("Backup erfolgreich erstellt: \(backupURL)")
                return backupURL
            } catch {
                print("Fehler beim Erstellen des Backups: \(error)")
                return nil
            }
        }
    }
    
    // Stelle die Daten aus einer JSON-Backup-Datei wieder her
    func restoreData(from url: URL) -> Bool {
        var success = false
        context.performAndWait {
            do {
                // Lese die JSON-Datei
                let jsonData = try Data(contentsOf: url)
                print("JSON-Datei erfolgreich geladen, Größe: \(jsonData.count) Bytes")
                guard let backupData = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                    print("Fehler: Ungültiges JSON-Format")
                    success = false
                    return
                }
                print("Backup-Daten geladen: \(backupData.keys)")

                // Lösche alle bestehenden Daten vor der Wiederherstellung
                let groupsRequest: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
                let accountsRequest: NSFetchRequest<Account> = Account.fetchRequest()
                let transactionsRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                let categoriesRequest: NSFetchRequest<Category> = Category.fetchRequest()

                // Lösche Gruppen
                if let groups = try? context.fetch(groupsRequest) {
                    print("Lösche \(groups.count) Kontogruppen")
                    for group in groups {
                        context.delete(group)
                    }
                } else {
                    print("Fehler beim Abrufen der Kontogruppen zum Löschen")
                }

                // Lösche Konten
                if let accounts = try? context.fetch(accountsRequest) {
                    print("Lösche \(accounts.count) Konten")
                    for account in accounts {
                        context.delete(account)
                    }
                } else {
                    print("Fehler beim Abrufen der Konten zum Löschen")
                }

                // Lösche Transaktionen
                if let transactions = try? context.fetch(transactionsRequest) {
                    print("Lösche \(transactions.count) Transaktionen")
                    for transaction in transactions {
                        context.delete(transaction)
                    }
                } else {
                    print("Fehler beim Abrufen der Transaktionen zum Löschen")
                }

                // Lösche Kategorien
                if let categories = try? context.fetch(categoriesRequest) {
                    print("Lösche \(categories.count) Kategorien")
                    for category in categories {
                        context.delete(category)
                    }
                } else {
                    print("Fehler beim Abrufen der Kategorien zum Löschen")
                }

                // Stelle sicher, dass alle Änderungen gespeichert werden, bevor neue Daten hinzugefügt werden
                do {
                    try context.save()
                    print("Alle bestehenden Daten erfolgreich gelöscht und gespeichert")
                } catch {
                    print("Fehler beim Speichern nach dem Löschen: \(error)")
                    success = false
                    return
                }

                // Wiederherstellung der Kategorien
                guard let categoriesData = backupData["categories"] as? [[String: Any]] else {
                    print("Fehler: Kategorien-Daten nicht gefunden")
                    success = false
                    return
                }
                var categoryMap: [String: Category] = [:]
                print("Wiederherstelle \(categoriesData.count) Kategorien")
                for categoryDict in categoriesData {
                    guard let name = categoryDict["name"] as? String, !name.isEmpty else {
                        print("Kategorie ohne Namen oder leer übersprungen: \(categoryDict)")
                        continue
                    }
                    let category = Category(context: context)
                    category.name = name
                    categoryMap[name] = category
                    print("Kategorie \(name) wiederhergestellt")
                }

                // Wiederherstellung der Kontogruppen
                guard let groupsData = backupData["accountGroups"] as? [[String: Any]] else {
                    print("Fehler: Kontogruppen-Daten nicht gefunden")
                    success = false
                    return
                }
                var groupMap: [String: AccountGroup] = [:]
                print("Wiederherstelle \(groupsData.count) Kontogruppen")
                for groupDict in groupsData {
                    guard let name = groupDict["name"] as? String else {
                        print("Kontogruppe ohne Namen übersprungen: \(groupDict)")
                        continue
                    }
                    let group = AccountGroup(context: context)
                    group.name = name
                    groupMap[name] = group
                    print("Kontogruppe \(name) wiederhergestellt")
                }

                // Wiederherstellung der Konten
                guard let accountsData = backupData["accounts"] as? [[String: Any]] else {
                    print("Fehler: Konten-Daten nicht gefunden")
                    success = false
                    return
                }
                var accountMap: [String: Account] = [:]
                print("Wiederherstelle \(accountsData.count) Konten")
                for accountDict in accountsData {
                    guard let name = accountDict["name"] as? String,
                          let groupName = accountDict["group"] as? String,
                          let group = groupMap[groupName] else {
                        print("Konto ohne Namen oder Gruppe übersprungen: \(accountDict)")
                        continue
                    }
                    let account = Account(context: context)
                    account.name = name
                    account.group = group
                    accountMap[name] = account
                    print("Konto \(name) wiederhergestellt, Gruppe: \(groupName)")
                }

                // Wiederherstellung der Transaktionen
                guard let transactionsData = backupData["transactions"] as? [[String: Any]] else {
                    print("Fehler: Transaktions-Daten nicht gefunden")
                    success = false
                    return
                }
                print("Wiederherstelle \(transactionsData.count) Transaktionen")
                for transactionDict in transactionsData {
                    guard let idString = transactionDict["id"] as? String,
                          let id = UUID(uuidString: idString),
                          let type = transactionDict["type"] as? String,
                          let amount = transactionDict["amount"] as? Double,
                          let dateTimestamp = transactionDict["date"] as? Double,
                          let accountName = transactionDict["account"] as? String,
                          let account = accountMap[accountName] else {
                        print("Transaktion übersprungen: \(transactionDict)")
                        continue
                    }

                    // Prüfe, ob das Datum gültig ist
                    let date = Date(timeIntervalSince1970: dateTimestamp)
                    if date.timeIntervalSince1970.isNaN || dateTimestamp <= 0 {
                        print("Transaktion übersprungen wegen ungültigem Datum: id=\(idString), dateTimestamp=\(dateTimestamp)")
                        continue
                    }

                    let transaction = Transaction(context: context)
                    transaction.id = id
                    transaction.type = type
                    transaction.amount = amount
                    transaction.date = date
                    transaction.account = account

                    if let categoryName = transactionDict["category"] as? String, let category = categoryMap[categoryName], !categoryName.isEmpty {
                        transaction.categoryRelationship = category
                        print("Transaktion \(idString) mit Kategorie \(categoryName) wiederhergestellt")
                    } else {
                        print("Kategorie nicht gefunden oder leer für Transaktion \(idString): \(String(describing: transactionDict["category"]))")
                    }
                    if let targetAccountName = transactionDict["targetAccount"] as? String, let targetAccount = accountMap[targetAccountName], !targetAccountName.isEmpty {
                        transaction.targetAccount = targetAccount
                        print("Transaktion \(idString) mit Zielkonto \(targetAccountName) wiederhergestellt")
                    }
                    if let usage = transactionDict["usage"] as? String, !usage.isEmpty {
                        transaction.usage = usage
                        print("Transaktion \(idString) mit Verwendungszweck \(usage) wiederhergestellt")
                    }
                }

                // Speichere die Änderungen
                do {
                    try context.save()
                    print("Daten erfolgreich gespeichert")
                } catch {
                    print("Fehler beim Speichern der wiederhergestellten Daten: \(error)")
                    success = false
                    return
                }

                // Aktualisiere die Daten im ViewModel
                self.fetchAccountGroups()
                self.fetchCategories()
                print("Daten erfolgreich wiederhergestellt, Kontogruppen: \(self.accountGroups.count)")
                success = true
                print("Wiederherstellung abgeschlossen, Erfolg: \(success)")
            } catch {
                print("Fehler beim Wiederherstellen der Daten: \(error)")
                success = false
            }
        }
        print("Wiederherstellung beendet, Rückgabewert: \(success)")
        return success
    }
    
    // Filtere Transaktionen basierend auf Datum, Monat oder benutzerdefiniertem Zeitraum
    func filterTransactions(accounts: [Account], filterType: String, selectedMonth: String, customDateRange: (start: Date, end: Date)?) -> [Transaction] {
        let allTx = accounts.flatMap { $0.transactions?.allObjects as? [Transaction] ?? [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMM yyyy"
        
        switch filterType {
        case "Alle Monate":
            return allTx
        case "Benutzerdefinierter Zeitraum":
            guard let range = customDateRange else { return [] }
            return allTx.filter { transaction in
                let date = transaction.date
                return date >= range.start && date <= range.end
            }
        default:
            return allTx.filter { transaction in
                formatter.string(from: transaction.date) == selectedMonth
            }
        }
    }

    // Aktualisierte Methode für monatliche Daten mit Filter
    func buildMonthlyData(accounts: [Account], filterType: String, selectedMonth: String, customDateRange: (start: Date, end: Date)?) -> [MonthlyData] {
        let filteredTransactions = filterTransactions(accounts: accounts, filterType: filterType, selectedMonth: selectedMonth, customDateRange: customDateRange)
        var monthlyEinnahmen: [String: Double] = [:]
        var monthlyAusgaben: [String: Double] = [:]
        var monthlyTransactions: [String: [Transaction]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"
        
        for transaction in filteredTransactions {
            let monthKey = dateFormatter.string(from: transaction.date)
            if transaction.type == "einnahme" {
                monthlyEinnahmen[monthKey, default: 0.0] += transaction.amount
            } else if transaction.type == "ausgabe" {
                monthlyAusgaben[monthKey, default: 0.0] += transaction.amount
            }
            monthlyTransactions[monthKey, default: []].append(transaction)
        }
        
        let allMonths = Set(monthlyEinnahmen.keys).union(monthlyAusgaben.keys)
        return allMonths.sorted().map { month in
            let txs = monthlyTransactions[month] ?? []
            let ins = txs.filter { $0.type == "einnahme" }
            let outs = txs.filter { $0.type == "ausgabe" }
            return MonthlyData(
                month: month,
                income: monthlyEinnahmen[month] ?? 0.0,
                expenses: monthlyAusgaben[month] ?? 0.0,
                surplus: (monthlyEinnahmen[month] ?? 0.0) - (monthlyAusgaben[month] ?? 0.0),
                incomeTransactions: ins,
                expenseTransactions: outs
            )
        }
    }

    // Aktualisierte Methode für Kategorien-Daten mit Filter
    func buildCategoryData(accounts: [Account], filterType: String, selectedMonth: String, customDateRange: (start: Date, end: Date)?) -> [CategoryData] {
        let filteredTransactions = filterTransactions(accounts: accounts, filterType: filterType, selectedMonth: selectedMonth, customDateRange: customDateRange)
        let expenseTransactions = filteredTransactions.filter { $0.type == "ausgabe" }
        let grouped = Dictionary(grouping: expenseTransactions) { $0.categoryRelationship?.name ?? "Unbekannt" }
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .yellow, .gray]
        return grouped.map { category, txs in
            let value = abs(txs.reduce(0.0) { $0 + $1.amount })
            let colorIndex = grouped.keys.sorted().firstIndex(of: category) ?? 0
            return CategoryData(
                name: category,
                value: value,
                color: colors[colorIndex % colors.count],
                transactions: txs
            )
        }.sorted { $0.value > $1.value }
    }
    
    // Bereinige Transaktionen mit ungültigen Daten
    func cleanInvalidTransactions() {
        context.performAndWait {
            let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            
            do {
                let allTransactions = try context.fetch(fetchRequest)
                var invalidTransactions: [Transaction] = []
                
                // Prüfe auf andere ungültige Daten, z. B. Transaktionen ohne Typ oder Betrag
                for transaction in allTransactions {
                    if transaction.type == nil || transaction.amount == 0 {
                        invalidTransactions.append(transaction)
                        print("Ungültige Transaktion gefunden: id=\(transaction.id.uuidString), type=\(String(describing: transaction.type)), amount=\(transaction.amount)")
                    }
                }
                
                for transaction in invalidTransactions {
                    context.delete(transaction)
                    print("Ungültige Transaktion gelöscht: id=\(transaction.id.uuidString)")
                }
                
                if !invalidTransactions.isEmpty {
                    self.saveContext(self.context) { error in
                        if let error = error {
                            print("Fehler beim Speichern nach Bereinigung: \(error)")
                            return
                        }
                        print("Datenbank bereinigt, \(invalidTransactions.count) Transaktionen gelöscht")
                    }
                } else {
                    print("Keine ungültigen Transaktionen gefunden")
                }
            } catch {
                print("Fehler beim Bereinigen der Datenbank: \(error.localizedDescription)")
            }
        }
    }
    
    // Temporäre Methode zum Bereinigen der Datenbank (einmalig ausführen)
    func forceCleanInvalidTransactions() {
        context.performAndWait {
            let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            
            do {
                let allTransactions = try context.fetch(fetchRequest)
                var invalidTransactions: [Transaction] = []
                
                // Prüfe auf ungültige Daten manuell
                for transaction in allTransactions {
                    // Da date nicht optional ist, greifen wir direkt darauf zu
                    let date = transaction.date
                    // Prüfe auf ungültige Datumswerte (z. B. sehr alte Daten oder ungültige Werte)
                    if date.timeIntervalSince1970 < 0 || date.timeIntervalSince1970.isNaN {
                        invalidTransactions.append(transaction)
                        print("Ungültige Transaktion gefunden (ungültiges Datum): id=\(transaction.id.uuidString), date=\(date)")
                    }
                }
                
                for transaction in invalidTransactions {
                    context.delete(transaction)
                    print("Ungültige Transaktion gelöscht: id=\(transaction.id.uuidString)")
                }
                
                if !invalidTransactions.isEmpty {
                    self.saveContext(self.context) { error in
                        if let error = error {
                            print("Fehler beim Speichern nach manueller Bereinigung: \(error)")
                            return
                        }
                        print("Datenbank manuell bereinigt, \(invalidTransactions.count) Transaktionen gelöscht")
                    }
                } else {
                    print("Keine ungültigen Transaktionen gefunden (manuelle Bereinigung)")
                }
            } catch {
                print("Fehler beim manuellen Bereinigen der Datenbank: \(error.localizedDescription)")
            }
        }
    }
    
    // Temporäre Methode zum Zurücksetzen der Datenbank (einmalig ausführen)
    func resetDatabase() {
        context.performAndWait {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Transaction.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            
            do {
                try context.execute(deleteRequest)
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern nach Zurücksetzen der Datenbank: \(error)")
                        return
                    }
                    print("Datenbank zurückgesetzt: Alle Transaktionen gelöscht")
                }
            } catch {
                print("Fehler beim Zurücksetzen der Datenbank: \(error.localizedDescription)")
            }
        }
    }

    // Hilfsfunktion zum Bereinigen der usage-Werte
    private func cleanUsage(_ input: String) -> String {
        var cleaned = input
        
        // Entferne Adressen (Straßen, Städte, PLZ)
        let addressPatterns = [
            "\\b\\w+\\s*(Strasse|Straße|Str\\.|Platz|Allee|Weg|Gasse)\\b[^,]*?(,\\s*\\d{5}\\s*[A-Za-z]+)?",
            "\\d{5}\\s*[A-Za-z]+"
        ]
        for pattern in addressPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count), withTemplate: "")
            }
        }
        
        // Entferne Datumsinformationen (z. B. "DATUM 25.04.2025, 11.53 UHR", "20250421 - 202", "04/2025")
        let datePatterns = [
            "DATUM\\s*\\d{2}\\.\\d{2}\\.\\d{4},\\s*\\d{1,2}\\.\\d{2}\\s*UHR",
            "\\d{8}\\s*-\\s*\\d{3}",
            "\\d{2}/\\d{4}",
            "\\d{2}\\.\\d{2}\\.\\d{4}"
        ]
        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count), withTemplate: "")
            }
        }
        
        // Entferne unnötige Codes und Nummern (z. B. "75173483", "Betriebsnummer 91022672", "Drp 138342904")
        let codePatterns = [
            "\\b(Betriebsnummer|Kd\\.Nr\\.|VK|Rg\\.Nr\\.|Revaler|Inv|Sr|Awv-Meldepflicht Beachten Hotline Bundesbank \\(0800\\) 1234-111|Drp|VERTRAGSNUMMER|Ga|Fi-|[A-Za-z0-9]+/[0-9]+/[0-9]+/[0-9]+/[0-9]+/[0-9]+|Steuernummer 14/450/|Recup Re340492,O401008)\\s*[^\\s]*",
            "\\b\\d{6,}\\b" // Entfernt lange Nummern wie "75173483", "138342904"
        ]
        for pattern in codePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count), withTemplate: "")
            }
        }
        
        // Entferne zusätzliche Beschreibungen (z. B. "Pop Svcs, Dob", "einschl. Ruecklastschriftgebuehr")
        let descriptionPatterns = [
            "Pop Svcs, Dob",
            "einschl\\. Ruecklastschriftgebuehr",
            "Vielen Dank f√ºr Ihren Besuch",
            "Wolt Auszahlung",
            "Basis-Rente",
            "Unfallversicherung",
            "Erstattung.*",
            "Reservierung.*",
            "Tisch.*",
            "Lohn.*",
            "Miete.*",
            "Abschlag.*",
            "Buchhaltung.*",
            "Umsatzsteuer.*",
            "Einkommenssteuer.*",
            "S√§umniszuschlag",
            "Abrechnung.*",
            "Entgeltabrechnung.*",
            "Falsch Buchung.*"
        ]
        for pattern in descriptionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count), withTemplate: "")
            }
        }
        
        // Entferne mehrfache Leerzeichen und trimme
        cleaned = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Begrenze die Länge der usage-Spalte auf maximal 50 Zeichen, um Speicherplatz zu sparen
        if cleaned.count > 50 {
            cleaned = String(cleaned.prefix(50))
        }
        
        return cleaned
    }

    // Neue Methode für flexiblen CSV-Import
    public func importBankCSV(contents: String, context: NSManagedObjectContext) throws -> ImportResult {
        // Teile den Inhalt in Zeilen auf
        let rows = contents.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        guard !rows.isEmpty else {
            print("CSV-Datei ist leer")
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "CSV-Datei ist leer"])
        }

        // Bestimme das Trennzeichen (Komma oder Semikolon)
        let firstRow = rows[0]
        let commaCount = firstRow.components(separatedBy: ",").count - 1
        let semicolonCount = firstRow.components(separatedBy: ";").count - 1
        let separator = semicolonCount > commaCount ? ";" : ","
        print("Erkanntes Trennzeichen: '\(separator)'")

        // Lese die Kopfzeile, um die Spaltennamen zu bestimden
        let header = firstRow.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        print("Kopfzeile der CSV-Datei: \(header)")

        // Finde die Positionen der relevanten Spalten
        var dateIndex: Int?
        var accountIndex: Int?
        var amountIndex: Int?
        var categoryIndex: Int?
        var nameIndex: Int?
        var purposeIndex: Int?

        for (index, column) in header.enumerated() {
            let trimmedColumn = column.lowercased()
            switch trimmedColumn {
            case "datum", "buchungsdatum", "valutadatum":
                dateIndex = index
            case "konto", "accountname":
                accountIndex = index
            case "betrag", "amount_eur":
                amountIndex = index
            case "hauptkategorie":
                categoryIndex = index
            case "kategorie" where categoryIndex == nil:
                categoryIndex = index
            case "name":
                nameIndex = index
            case "zweck", "verwendungszweck", "verwendung":
                purposeIndex = index
            default:
                break
            }
        }

        guard let dateIdx = dateIndex, let accountIdx = accountIndex, let amountIdx = amountIndex else {
            print("Fehlende benötigte Spalten in der CSV-Datei (Datum, Konto, Betrag sind erforderlich)")
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Fehlende benötigte Spalten in der CSV-Datei (Datum, Konto, Betrag sind erforderlich)"])
        }

        // DateFormatter für Parsing und Formatierung
        let dfLong = DateFormatter()
        dfLong.locale = Locale(identifier: "de_DE")
        dfLong.dateFormat = "dd.MM.yyyy"

        // NumberFormatter für korrekte Betragsumrechnung
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "de_DE")
        numberFormatter.numberStyle = .decimal
        numberFormatter.decimalSeparator = ","
        numberFormatter.groupingSeparator = "."

        // Kalender für Jahresvalidierung und Datumsnormalisierung
        let calendar = Calendar.current

        // Arrays für Import-Ergebnisse
        var importedTransactions: [ImportResult.TransactionInfo] = []
        var skippedTransactions: [ImportResult.TransactionInfo] = []

        for (lineNumber, row) in rows.dropFirst().enumerated() {
            // Manuelles Parsen der Zeile unter Berücksichtigung von Anführungszeichen
            var columns: [String] = []
            var currentColumn = ""
            var insideQuotes = false

            for char in row {
                if char == "\"" {
                    insideQuotes.toggle()
                } else if char == separator.first && !insideQuotes {
                    columns.append(currentColumn)
                    currentColumn = ""
                } else {
                    currentColumn.append(char)
                }
            }
            columns.append(currentColumn)

            // Entferne Anführungszeichen aus den Spalten
            let cleanedColumns = columns.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).trimmingCharacters(in: .whitespacesAndNewlines) }

            // Stelle sicher, dass die Zeile genug Spalten hat
            let requiredMaxIndex = max(dateIdx, accountIdx, amountIdx, categoryIndex ?? 0, nameIndex ?? 0, purposeIndex ?? 0)
            if cleanedColumns.count <= requiredMaxIndex {
                print("Zeile \(lineNumber + 2): Ungültige Zeile (zu wenige Spalten: \(cleanedColumns.count), benötigt: \(requiredMaxIndex + 1)): \(row)")
                continue
            }

            // Extrahiere die relevanten Werte
            let raw = cleanedColumns[dateIdx]
            var accountName = cleanedColumns[accountIdx]
            let amountString = cleanedColumns[amountIdx]
            _ = categoryIndex != nil ? cleanedColumns[categoryIndex!] : ""
            let name = nameIndex != nil ? cleanedColumns[nameIndex!] : ""
            let purpose = purposeIndex != nil ? cleanedColumns[purposeIndex!] : ""

            // Mappe die IBAN auf den Kontonamen "Giro"
            if accountName == "DE61100500000190696397" {
                accountName = "Giro"
            }

            // Normalisiere das Datum
            let parts = raw.split(separator: ".")
            let normalized: String
            if parts.count == 3 && parts[2].count == 2 {
                normalized = "\(parts[0]).\(parts[1]).20\(parts[2])"
            } else {
                normalized = raw
            }

            // Parse das normalisierte Datum
            guard let date = dfLong.date(from: normalized) else {
                print("Zeile \(lineNumber + 2): Ungültiges Datum: \(raw) → \(normalized)")
                continue
            }

            // Validierung des Jahres
            let year = calendar.component(.year, from: date)
            guard year >= 1970 else {
                print("Zeile \(lineNumber + 2): Jahr \(year) < 1970 – übersprungen")
                continue
            }

            // Normalisiere das Datum auf den Tag
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
            guard let normalizedDate = calendar.date(from: dateComponents) else {
                print("Zeile \(lineNumber + 2): Konnte Datum nicht normalisieren: \(date)")
                continue
            }

            // Validierung und Konvertierung des Betrags
            guard let amountNumber = numberFormatter.number(from: amountString) else {
                print("Zeile \(lineNumber + 2): Ungültiger Betrag: \(amountString)")
                continue
            }
            let amount = amountNumber.doubleValue
            print("Zeile \(lineNumber + 2): Betrag erfolgreich umgewandelt: \(amountString) -> \(amount)")

            // Bereinige und kombiniere "Name" und "Zweck" für "usage"
            let cleanedName = cleanCompanyName(name)
            let cleanedPurpose = cleanCompanyName(purpose)
            var usageComponents: [String] = []
            if !cleanedName.isEmpty {
                usageComponents.append(cleanedName)
            }
            if !cleanedPurpose.isEmpty && cleanedPurpose != cleanedName {
                usageComponents.append(cleanedPurpose)
            }
            let usage = usageComponents.joined(separator: " ")
            let finalUsage = fixUmlauts(usage.isEmpty ? nil : usage)

            // KATEGORISIERUNG DER TRANSAKTION
            var transactionType = "ausgabe"
            var finalCategory = ""
            
            // Hole den bereinigten Verwendungszweck
            let cleanedUsage = finalUsage?.lowercased() ?? ""
            print("Zeile \(lineNumber + 2): Bereinigter Verwendungszweck: \(cleanedUsage)")
            
            // 1. ERSTE PRIORITÄT: CategoryMatcher verwenden
            var categoryFound = false
            let (matchedCategory, _) = CategoryMatcher.shared.findBestCategory(for: cleanedUsage, amount: amount)
            if let category = matchedCategory {
                finalCategory = category
                categoryFound = true
                print("Zeile \(lineNumber + 2): ✓ Kategorie vom CategoryMatcher: '\(cleanedUsage)' → '\(category)' (Typ: \(transactionType))")
            }
            
            // 2. ZWEITE PRIORITÄT: Standard-Kategorisierung
            if !categoryFound {
                if amount >= 0 {
                    transactionType = "einnahme"
                    finalCategory = "Einnahmen"
                    print("Zeile \(lineNumber + 2): ✓ Als Einnahme kategorisiert")
                } else {
                    transactionType = "ausgabe"
                    finalCategory = "Sonstiges"
                    print("Zeile \(lineNumber + 2): ✓ Als Sonstige Ausgabe kategorisiert")
                }
            }
            
            print("Zeile \(lineNumber + 2): Finale Kategorie: '\(finalCategory)' (Typ: \(transactionType))")

            // Erstelle TransactionInfo für Protokollierung
            let transactionInfo = ImportResult.TransactionInfo(
                date: normalized,
                amount: amount,
                account: accountName,
                usage: finalUsage,
                category: finalCategory
            )

            // Suche oder erstelle die Kategorie
            let fetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "name == %@", finalCategory)
            let categories = try context.fetch(fetchRequest)
            let categoryObject: Category
            if let existingCategory = categories.first {
                categoryObject = existingCategory
            } else if !finalCategory.isEmpty {
                categoryObject = Category(context: context)
                categoryObject.name = finalCategory
            } else {
                // Standardkategorie, falls keine Kategorie angegeben ist
                let defaultFetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
                defaultFetchRequest.predicate = NSPredicate(format: "name == %@", "Sonstiges")
                let defaultCategories = try context.fetch(defaultFetchRequest)
                if let defaultCategory = defaultCategories.first {
                    categoryObject = defaultCategory
                } else {
                    categoryObject = Category(context: context)
                    categoryObject.name = "Sonstiges"
                }
            }

            // Suche das Konto
            let accountFetchRequest: NSFetchRequest<Account> = Account.fetchRequest()
            accountFetchRequest.predicate = NSPredicate(format: "name == %@", accountName)
            let accounts = try context.fetch(accountFetchRequest)
            guard let account = accounts.first else {
                print("Zeile \(lineNumber + 2): Konto \(accountName) nicht gefunden")
                continue
            }

            // Bei Umbuchungen (z.B. SB-Einzahlung) beide Konten prüfen
            if transactionType == "umbuchung" && finalCategory == "EC-Umbuchung" {
                let targetAccountRequest: NSFetchRequest<Account> = Account.fetchRequest()
                targetAccountRequest.predicate = NSPredicate(format: "name == %@", "Bargeld")
                if let targetAccount = try context.fetch(targetAccountRequest).first {
                    // Erstelle die Umbuchungstransaktion
                    let transaction = Transaction(context: context)
                    transaction.id = UUID()
                    transaction.type = transactionType
                    transaction.amount = amount
                    transaction.date = normalizedDate
                    transaction.account = account
                    transaction.targetAccount = targetAccount
                    transaction.categoryRelationship = categoryObject
                    transaction.usage = finalUsage
                    
                    print("Zeile \(lineNumber + 2): Umbuchung erstellt: \(amount) von \(accountName) nach Bargeld")
                    
                    // Erstelle die Gegenbuchung
                    let counterTransaction = Transaction(context: context)
                    counterTransaction.id = UUID()
                    counterTransaction.type = transactionType
                    counterTransaction.amount = -amount
                    counterTransaction.date = normalizedDate
                    counterTransaction.account = targetAccount
                    counterTransaction.targetAccount = account
                    counterTransaction.categoryRelationship = categoryObject
                    counterTransaction.usage = finalUsage
                    
                    importedTransactions.append(transactionInfo)
                    continue
                }
            }

            // Prüfe auf Duplikate
            let transactionFetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            let startOfDay = normalizedDate
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
                print("Zeile \(lineNumber + 2): Konnte Enddatum nicht berechnen")
                continue
            }
            
            var predicates: [NSPredicate] = [
                NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate),
                NSPredicate(format: "abs(amount - %f) < 0.01", amount),
                NSPredicate(format: "account == %@", account)
            ]
            
            if let usageValue = finalUsage {
                predicates.append(NSPredicate(format: "usage == %@", usageValue))
            } else {
                predicates.append(NSPredicate(format: "usage == nil"))
            }
            
            transactionFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            let existingTransactions = try context.fetch(transactionFetchRequest)

            if !existingTransactions.isEmpty {
                print("Zeile \(lineNumber + 2): Transaktion existiert bereits")
                skippedTransactions.append(transactionInfo)
                continue
            }

            // Erstelle die Transaktion
            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.date = normalizedDate
            transaction.type = transactionType
            transaction.amount = amount
            transaction.categoryRelationship = categoryObject
            transaction.account = account
            transaction.usage = finalUsage

            print("Zeile \(lineNumber + 2): Neue Transaktion erstellt: id=\(transaction.id.uuidString), Datum=\(normalized), Betrag=\(amount), Konto=\(accountName), Kategorie=\(finalCategory), Usage=\(finalUsage ?? "nil")")
            if let usageVal = finalUsage {
                let (suggestedCategory, _) = CategoryMatcher.shared.findBestCategory(for: usageVal, amount: amount)
                if let category = suggestedCategory, category != finalCategory {
                    print("Zeile \(lineNumber + 2): Kategorie basierend auf usage zugewiesen: \(usageVal) → \(finalCategory)")
                }
            }
            
            importedTransactions.append(transactionInfo)
        }

        // Speichere den Kontext
        try context.save()
        print("Bank CSV-Import erfolgreich abgeschlossen")
        
        // Erstelle ein automatisches Backup nach dem Import
        if let backupURL = self.backupData() {
            print("Automatisches Backup nach Import erstellt: \(backupURL)")
        } else {
            print("Fehler beim Erstellen des automatischen Backups nach Import")
        }

        return ImportResult(imported: importedTransactions, skipped: skippedTransactions)
    }

    // Hilfsfunktionen für den CSV-Import

    // Bereinigt Firmennamen und entfernt Adressen
    private func cleanCompanyName(_ input: String) -> String {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Bekannte Firmennamen-Muster
        let companyPatterns: [(pattern: String, replacement: String)] = [
            ("STRATO\\s+GmbH[^,]*?(?:,\\s*[^,]+)?", "STRATO GmbH"),
            ("Vodafone\\s+GmbH[^,]*?(?:,\\s*[^,]+)?", "Vodafone GmbH"),
            ("Wolt\\s+License\\s+Services\\s+Oy[^,]*", "Wolt"),
            ("Uber\\s+Payments\\s+B\\.V\\.[^,]*", "Uber"),
            ("SIGNAL\\s+IDUNA[^,]*", "SIGNAL IDUNA"),
            ("AOK[^,]*", "AOK Nordost"),
            ("Finanzamt\\s+[A-Za-zäöüÄÖÜß\\s-]+", "Finanzamt"),
            ("ALBA\\s+Berlin[^,]*", "ALBA Berlin"),
            ("SGB\\s+Energie[^,]*", "SGB Energie"),
            ("reCup\\s+GmbH[^,]*", "reCup GmbH"),
            ("ILLE\\s+Papier-Service[^,]*", "ILLE Papier-Service"),
            ("Bundesknappschaft[^,]*", "Bundesknappschaft")
        ]
        
        // Anwenden der Muster
        for (pattern, replacement) in companyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    options: [],
                    range: NSRange(location: 0, length: cleaned.utf16.count),
                    withTemplate: replacement
                )
            }
        }
        
        // Entfernung von Adressen, Zeiten, Codes, etc.
        let removePatterns = [
            "[0-9]{5}\\s+[A-Za-zäöüÄÖÜß\\s-]+",                       // PLZ mit Ort
            "[A-Za-zäöüÄÖÜß\\s-]+(str|straße|platz|weg|allee)\\s+\\d+", // Straßenname mit Hausnummer
            "\\d{2}\\.\\d{2}\\.\\d{2,4}\\s*(?:,\\s*\\d{1,2}[:.:]\\d{2})?\\s*(?:Uhr)?", // Datums- und Zeitangaben
            "Hotline\\s+Bundesbank[^)]+\\)",                          // Hotline-Info
            "(?:Beachten|sagt Danke)",                                // Hinweise
            "\\b[A-Z0-9]+/[0-9]+/[0-9]+(?:/[0-9]+)?\\b",             // Referenznummern
            "DATUM\\s*\\d{2}\\.\\d{2}\\.\\d{4}",                      // Datums-Header
            "\\d{6,}",                                                // Lange Zahlen
            "(?:-Meldepflicht)",                                      // Spezielle Hinweise
            "(?:Rg|Inv|Nr)\\.?\\s*\\d+",                              // Rechnungsnummern etc.
        ]
        
        // Anwenden der Entfernungsmuster
        for pattern in removePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    options: [],
                    range: NSRange(location: 0, length: cleaned.utf16.count),
                    withTemplate: ""
                )
            }
        }
        
        // Bereinigung mehrfacher Leerzeichen, Kommas und Sonderzeichen
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: ",+", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }

    // Repariert Unicode-Umlaute
    private func fixUmlauts(_ input: String?) -> String? {
        guard let text = input else { return nil }
        
        var fixed = text
        
        // Unicode-Ersetzungstabelle
        let umlautReplacements: [String: String] = [
            "√ú": "Ü", "√ü": "ß", "√∂": "ö", "√§": "ä",
            "√Ñ": "Ä", "√Ö": "Ö", "√ñ": "Ö", "√º": "ü",
            "√©": "é", "√®": "è", "√†": "à", "√¢": "â",
            "√ª": "û", "√•": "å", "√´": "ë", "√¨": "ï",
            "√Æ": "î", "√≤": "ò", "√≥": "ó", "√¥": "ô",
            "√µ": "õ", "√∏": "ø", "√π": "ù", "√æ": "þ",
            "√ø": "ÿ", "√±": "ñ", "√ß": "ç"
        ]
        
        // Wende alle Ersetzungen an
        for (encodedUmlaut, properUmlaut) in umlautReplacements {
            fixed = fixed.replacingOccurrences(of: encodedUmlaut, with: properUmlaut)
        }
        
        return fixed
    }

    // Struktur für Import-Ergebnisse
    struct ImportResult {
        struct TransactionInfo {
            let date: String
            let amount: Double
            let account: String
            let usage: String?
            let category: String
        }
        
        let imported: [TransactionInfo]
        let skipped: [TransactionInfo]
        
        var summary: String {
            return "\(imported.count) Transaktionen importiert, \(skipped.count) übersprungene Duplikate"
        }
    }

    func calculateAllBalances() -> [NSManagedObjectID: Double] {
        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: "Transaction")
        fetchRequest.resultType = .dictionaryResultType

        let sumExpression = NSExpressionDescription()
        sumExpression.name = "totalAmount"
        sumExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "amount")])
        sumExpression.expressionResultType = .doubleAttributeType

        fetchRequest.propertiesToGroupBy = ["account"]
        fetchRequest.propertiesToFetch = ["account", sumExpression]

        do {
            let results = try context.fetch(fetchRequest)
            var balanceDict: [NSManagedObjectID: Double] = [:]
            for result in results {
                if let account = result["account"] as? NSManagedObjectID,
                   let balance = result["totalAmount"] as? Double {
                    balanceDict[account] = balance
                }
            }
            return balanceDict
        } catch {
            print("Fehler beim Berechnen aller Kontostände: \(error.localizedDescription)")
            return [:]
        }
    }

    func importCSV(from fileURL: URL) throws {
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            print("CSV-Datei erfolgreich geladen: \(fileURL.path)")
            let firstLine = contents.components(separatedBy: "\n").first ?? ""
            print("Kopfzeile der CSV-Datei: \(firstLine)")
            
            // Verwende die neue flexible Import-Methode und überprüfe das Ergebnis
            let result = try importBankCSV(contents: contents, context: context)
            print("Import abgeschlossen: \(result.summary)")
        } catch {
            print("Fehler beim Laden der CSV-Datei \(fileURL.lastPathComponent): \(error.localizedDescription)")
            throw error
        }
    }

    // Lade eine einzelne Transaktion
    func loadTransaction(_ transaction: Transaction, completion: @escaping (Transaction?) -> Void) {
        isLoadingTransaction = true
        loadingError = nil
        
        context.perform {
            // Stelle sicher, dass die Transaktion im aktuellen Kontext ist
            let objectID = transaction.objectID
            guard let loadedTransaction = try? self.context.existingObject(with: objectID) as? Transaction else {
                DispatchQueue.main.async {
                    self.loadingError = "Transaktion konnte nicht geladen werden"
                    self.isLoadingTransaction = false
                    completion(nil)
                }
                return
            }
            
            DispatchQueue.main.async {
                self.isLoadingTransaction = false
                completion(loadedTransaction)
            }
        }
    }

    func generateMonthlyReport(for transactions: [Transaction]) -> [MonthlyData] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"
        dateFormatter.locale = Locale(identifier: "de_DE")
        
        // Group transactions by month
        let grouped = Dictionary(grouping: transactions) { transaction in
            dateFormatter.string(from: transaction.date)
        }
        
        return grouped.map { month, txs in
            let ins = txs.filter { $0.type == "einnahme" }
            let outs = txs.filter { $0.type == "ausgabe" }
            let einnahmen = ins.reduce(0.0) { $0 + $1.amount }
            let ausgaben = abs(outs.reduce(0.0) { $0 + $1.amount })
            return MonthlyData(
                month: month,
                income: einnahmen,
                expenses: ausgaben,
                surplus: einnahmen - ausgaben,
                incomeTransactions: ins,
                expenseTransactions: outs
            )
        }.sorted { $0.month < $1.month }
    }

    func generateCategoryReport(for transactions: [Transaction]) -> [CategoryData] {
        let expenseTransactions = transactions.filter { $0.type == "ausgabe" }
        let grouped = Dictionary(grouping: expenseTransactions) { $0.categoryRelationship?.name ?? "Unbekannt" }
        
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .yellow, .gray]
        
        return grouped.map { category, txs in
            let value = abs(txs.reduce(0.0) { $0 + $1.amount })
            let colorIndex = grouped.keys.sorted().firstIndex(of: category) ?? 0
            return CategoryData(
                name: category,
                value: value,
                color: colors[colorIndex % colors.count],
                transactions: txs
            )
        }.sorted { $0.value > $1.value }
    }

    func generateForecastReport(monthlyData: MonthlyData) -> [ForecastData] {
        // Calculate forecast based on current month's data
        let currentIncome = monthlyData.income
        let currentExpenses = monthlyData.expenses
        let currentBalance = currentIncome - currentExpenses
        
        // Simple forecast: project same income/expenses for next month
        return [
            ForecastData(
                month: monthlyData.month,
                einnahmen: currentIncome,
                ausgaben: currentExpenses,
                balance: currentBalance
            )
        ]
    }

    // Lösche ein Konto
    func deleteAccount(_ account: Account, completion: (() -> Void)? = nil) {
        context.perform {
            print("DEBUG: Beginne Löschung von Konto: \(account.name ?? "unknown")")
            
            // Lösche zuerst alle zugehörigen Transaktionen
            if let transactions = account.transactions as? Set<Transaction> {
                for transaction in transactions {
                    self.context.delete(transaction)
                    print("DEBUG: Lösche zugehörige Transaktion: \(transaction.id)")
                }
            }
            
            // Lösche das Konto selbst
            self.context.delete(account)
            
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Löschen des Kontos: \(error)")
                    completion?()
                    return
                }
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.fetchAccountGroups()
                    print("Konto \(account.name ?? "unknown") erfolgreich gelöscht")
                    completion?()
                }
            }
        }
    }

    // Lösche mehrere Transaktionen auf einmal
    func deleteTransactions(_ transactions: [Transaction], completion: (() -> Void)? = nil) {
        context.perform {
            print("DEBUG: Beginne Löschung von \(transactions.count) Transaktionen")
            
            for transaction in transactions {
                self.context.delete(transaction)
                print("DEBUG: Lösche Transaktion: \(transaction.id)")
            }
            
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Löschen der Transaktionen: \(error)")
                    completion?()
                    return
                }
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.fetchAccountGroups()
                    print("Alle \(transactions.count) Transaktionen erfolgreich gelöscht")
                    completion?()
                }
            }
        }
    }

    // Speichere eine manuelle Kategoriezuweisung und lerne daraus
    func saveCategory(_ category: Category, for transaction: Transaction) {
        context.perform {
            // Speichere die Kategorie
            transaction.categoryRelationship = category
            
            // Lerne aus der manuellen Zuweisung
            if let originalUsage = transaction.usage {
                // Erstelle eine gekürzte Version des Verwendungszwecks
                let shortForm = self.createShortForm(from: originalUsage)
                
                // Speichere die Zuordnung im CategoryMatcher
                CategoryMatcher.shared.learnShortForm(
                    originalText: originalUsage,
                    shortForm: shortForm,
                    category: category.name ?? "Unbekannt"
                )
            }
            
            self.saveContext(self.context)
        }
    }
    
    // Erstellt eine gekürzte Version eines Verwendungszwecks
    private func createShortForm(from usage: String) -> String {
        // Entferne häufige Zusätze und unwichtige Informationen
        var shortForm = usage
            .replacingOccurrences(of: "\\s+GmbH\\s+&\\s+Co\\.?\\s+KG", with: " GmbH", options: .regularExpression)
            .replacingOccurrences(of: "\\s+GmbH\\s+&\\s+Co", with: " GmbH", options: .regularExpression)
            .replacingOccurrences(of: "\\s+AG\\s+&\\s+Co\\.?\\s+KG", with: " AG", options: .regularExpression)
            .replacingOccurrences(of: "\\s+AG\\s+&\\s+Co", with: " AG", options: .regularExpression)
            .replacingOccurrences(of: "\\s+mbH", with: " GmbH", options: .regularExpression)
            .replacingOccurrences(of: "(?i)gesellschaft mit beschränkter haftung", with: "GmbH", options: .regularExpression)
            .replacingOccurrences(of: "(?i)aktiengesellschaft", with: "AG", options: .regularExpression)
        
        // Entferne Straßen, Hausnummern und PLZ
        shortForm = shortForm.replacingOccurrences(
            of: "\\s+(?:str\\.|strasse|straße)\\s+\\d+[a-z]?(?:[,-]\\s*\\d{5})?",
            with: "",
            options: .regularExpression
        )
        
        // Entferne PLZ und Orte
        shortForm = shortForm.replacingOccurrences(
            of: "\\s*,?\\s*\\d{5}\\s+[A-Za-zÄÖÜäöüß\\s]+(?:,\\s*[A-Za-z]+)?",
            with: "",
            options: .regularExpression
        )
        
        // Entferne mehrfache Leerzeichen und trimme
        shortForm = shortForm.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        
        return shortForm
    }
}

