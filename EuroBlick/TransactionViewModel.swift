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
        
        // Verzögere die Initialisierung um sicherzustellen, dass Core Data bereit ist
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.initializeData()
        }
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
                "Reparatur", "Steuern", "Reservierung", "Internetkosten", 
                "Versicherungen", "Sonstiges"
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
            print("DEBUG: fetchAccountGroups gestartet")
            let request: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            request.returnsObjectsAsFaults = false
            request.relationshipKeyPathsForPrefetching = ["accounts", "accounts.transactions"]
            do {
                let fetchedGroups = try self.context.fetch(request)
                print("DEBUG: Core Data hat \(fetchedGroups.count) Kontogruppen zurückgegeben")
                for group in fetchedGroups {
                    print("DEBUG: - Gruppe: \(group.name ?? "nil") mit \(group.accounts?.count ?? 0) Konten")
                }
                DispatchQueue.main.async {
                    self.accountGroups = fetchedGroups
                    self.objectWillChange.send()
                    print("Fetched \(self.accountGroups.count) account groups: \(self.accountGroups.map { $0.name ?? "Unnamed" })")
                }
            } catch {
                print("FEHLER beim Abrufen der Kontogruppen: \(error)")
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

        // Schließe Reservierungen aus der Kontostand-Berechnung aus
        fetchRequest.predicate = NSPredicate(format: "account == %@ AND type != %@", account, "reservierung")
        fetchRequest.resultType = .dictionaryResultType

        let expressionDesc = NSExpressionDescription()
        expressionDesc.name = "totalAmount"
        expressionDesc.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "amount")])
        expressionDesc.expressionResultType = .doubleAttributeType

        fetchRequest.propertiesToGroupBy = ["type"]
        fetchRequest.propertiesToFetch = ["type", expressionDesc]

        do {
            let results = try context.fetch(fetchRequest)
            var totalBalance: Double = 0.0
            var summeEinnahmen: Double = 0.0
            var summeAusgaben: Double = 0.0
            var summeUmbuchungen: Double = 0.0
            
            for result in results {
                if let type = result["type"] as? String,
                   let amount = result["totalAmount"] as? Double {
                    if type == "einnahme" {
                        totalBalance += amount
                        summeEinnahmen += amount
                    } else if type == "ausgabe" {
                        totalBalance += amount // Korrigiert: addiere, da bereits negativ
                        summeAusgaben += amount
                    } else if type == "umbuchung" {
                        totalBalance += amount // Umbuchungen werden auch addiert
                        summeUmbuchungen += amount
                    }
                    // "reservierung" wird ignoriert
                }
            }
            print("getBalance: \(account.name ?? "-") | Einnahmen: \(summeEinnahmen) | Ausgaben: \(summeAusgaben) | Umbuchungen: \(summeUmbuchungen) | Bilanz: \(totalBalance) (Reservierungen ausgeschlossen)")
            return totalBalance
        } catch {
            print("Fehler beim Berechnen des Kontostands: \(error.localizedDescription)")
            return 0.0
        }
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
        print("DEBUG: addAccountGroup aufgerufen mit Name: '\(name)'")
        context.perform {
            print("DEBUG: Erstelle neue AccountGroup im Kontext")
            let newGroup = AccountGroup(context: self.context)
            newGroup.name = name
            print("DEBUG: AccountGroup erstellt mit Name: \(newGroup.name ?? "nil")")
            
            self.saveContext(self.context) { error in
                if let error = error {
                    print("FEHLER beim Speichern der neuen Kontogruppe: \(error.localizedDescription)")
                    print("FEHLER Details: \(error)")
                    completion?()
                    return
                }
                print("DEBUG: Kontogruppe erfolgreich gespeichert")
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
    func addAccount(name: String, group: AccountGroup, icon: String = "banknote.fill", color: Color = .blue, type: String = "offline") {
        print("DEBUG: TransactionViewModel.addAccount - Start")
        print("DEBUG: Name: \(name)")
        print("DEBUG: Gruppe: \(group.name ?? "unknown")")
        print("DEBUG: Gruppen-ID: \(group.objectID)")
        print("DEBUG: Kontext der Gruppe: \(String(describing: group.managedObjectContext))")
        print("DEBUG: Hauptkontext: \(context)")
        print("DEBUG: Kontotyp: \(type)")

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
            account.setValue(type, forKey: "type")
            
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
        // Automatische Erkennung des Transaktionstyps basierend auf dem Verwendungszweck
        let detectedType = detectTransactionType(usage: usage, amount: amount, sourceAccount: account, targetAccount: targetAccount)
        let finalType = (type == "einnahme" || type == "ausgabe") && detectedType == "umbuchung" ? detectedType : type
        
        guard !finalType.isEmpty, ["einnahme", "ausgabe", "umbuchung", "reservierung"].contains(finalType) else {
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
            if finalType == "umbuchung", let target = targetAccount {
                let sourceTransaction = Transaction(context: self.context)
                sourceTransaction.id = UUID()
                sourceTransaction.type = "umbuchung"
                sourceTransaction.amount = -amount
                sourceTransaction.date = date
                sourceTransaction.account = account
                sourceTransaction.targetAccount = target
                sourceTransaction.usage = usage
                self.setCategoryForTransaction(sourceTransaction, categoryName: category)

                // Lege IMMER die Zieltransaktion an
                let targetTransaction = Transaction(context: self.context)
                targetTransaction.id = UUID()
                targetTransaction.type = "umbuchung"
                targetTransaction.amount = amount
                targetTransaction.date = date
                targetTransaction.account = target
                targetTransaction.targetAccount = account
                targetTransaction.usage = usage
                self.setCategoryForTransaction(targetTransaction, categoryName: category)

                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern der Umbuchung: \(error)")
                        completion?(error)
                        return
                    }
                    self.cleanupInvalidTransactions()
                    self.fetchAccountGroups()
                    print("Umbuchung hinzugefügt: \(amount) von \(account.name ?? "unknown") zu \(target.name ?? "unknown")")
                    completion?(nil)
                }
            } else {
                let newTransaction = Transaction(context: self.context)
                newTransaction.id = UUID()
                newTransaction.type = finalType
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
                    print("Transaktion hinzugefügt: type=\(finalType), amount=\(amount), Kategorie=\(category), usage=\(usage ?? "nil")")
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
            // Vorab alle benötigten Properties sichern
            let transactionId = transaction.id
            let transactionAmount = transaction.amount
            let transactionDate = transaction.date
            let accountName = transaction.account?.name ?? "unknown"
            let targetName = transaction.targetAccount?.name ?? "unknown"
            let transactionType = transaction.type ?? "-"
            
            // Wenn Umbuchung: Gegenbuchung suchen und mitlöschen
            if transactionType == "umbuchung",
               let account = transaction.account,
               let target = transaction.targetAccount {
                print("[Umbuchung-Löschen] Suche Gegenbuchung für:")
                print("  - ID: \(transactionId)")
                print("  - Betrag: \(transactionAmount)")
                print("  - Von Konto: \(accountName)")
                print("  - Nach Konto: \(targetName)")
                print("  - Datum: \(transactionDate)")
                
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: transactionDate)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? transactionDate
                
                // Suche alle Umbuchungen am selben Tag mit vertauschten Konten
                let fetchRequest = NSFetchRequest<Transaction>(entityName: "Transaction")
                let predicates = [
                    NSPredicate(format: "type == %@", "umbuchung"),
                    NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate),
                    NSPredicate(format: "account == %@", target),
                    NSPredicate(format: "targetAccount == %@", account)
                ]
                fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                
                do {
                    let results = try self.context.fetch(fetchRequest)
                    print("[Umbuchung-Löschen] Gefundene potentielle Gegenbuchungen: \(results.count)")
                    for result in results {
                        let resultId = result.id
                        let resultAmount = result.amount
                        let resultAccount = result.account?.name ?? "unknown"
                        let resultTarget = result.targetAccount?.name ?? "unknown"
                        let resultDate = result.date
                        print("  - ID: \(resultId)")
                        print("  - Betrag: \(resultAmount)")
                        print("  - Von Konto: \(resultAccount)")
                        print("  - Nach Konto: \(resultTarget)")
                        print("  - Datum: \(resultDate)")
                    }
                    // Suche mit Toleranz beim Betrag
                    if let other = results.first(where: { abs($0.amount + transactionAmount) < 0.01 }) {
                        let otherId = other.id
                        print("[Umbuchung-Löschen] Lösche Gegenbuchung: \(otherId)")
                        self.context.delete(other)
                    } else {
                        print("[Umbuchung-Löschen] Keine passende Gegenbuchung mit passendem Betrag gefunden!")
                    }
                } catch {
                    print("[Umbuchung-Löschen] Fehler beim Suchen der Gegenbuchung: \(error)")
                }
            }
            
            // Lösche die eigentliche Transaktion
            print("[Umbuchung-Löschen] Lösche Haupttransaktion: \(transactionId)")
            self.context.delete(transaction)
            
            self.saveContext(self.context) { error in
                if let error = error {
                    print("Fehler beim Speichern nach Löschen der Transaktion: \(error)")
                    completion?()
                    return
                }
                self.fetchAccountGroups()
                print("Transaktion gelöscht: \(transactionId)")
                completion?()
            }
        }
    }
    
    // Aktualisiere eine bestehende Transaktion
    func updateTransaction(_ transaction: Transaction, type: String, amount: Double, category: String, account: Account, targetAccount: Account?, usage: String?, date: Date, completion: (() -> Void)? = nil) {
        guard !type.isEmpty, ["einnahme", "ausgabe", "umbuchung", "reservierung"].contains(type) else {
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
                // Finde die Gegenbuchung
                let fetchRequest = NSFetchRequest<Transaction>(entityName: "Transaction")
                fetchRequest.predicate = NSPredicate(format: "type == %@ AND date == %@ AND amount == %@ AND account == %@ AND targetAccount == %@", "umbuchung", transaction.date as NSDate, NSNumber(value: -transaction.amount), target, account)
                let results = try? self.context.fetch(fetchRequest)
                let other = results?.first

                // Aktualisiere beide Transaktionen
                transaction.amount = amount
                transaction.date = date
                transaction.account = account
                transaction.targetAccount = target
                transaction.usage = usage
                self.setCategoryForTransaction(transaction, categoryName: category)

                if let other = other {
                    other.amount = -amount
                    other.date = date
                    other.account = target
                    other.targetAccount = account
                    other.usage = usage
                    self.setCategoryForTransaction(other, categoryName: category)
                }

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
            // Filtere Reservierungen und Umbuchungen aus
            let filteredTransactions = transactions.filter { $0.type != "umbuchung" && $0.type != "reservierung" }
            var categoryTotals: [String: Double] = [:]
            for transaction in filteredTransactions {
                if transaction.type == "ausgabe", let category = transaction.categoryRelationship?.name {
                    categoryTotals[category, default: 0.0] += transaction.amount
                }
            }
            let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange]
            return categoryTotals.enumerated().map { (index, element) in
                CategoryData(name: element.key, value: element.value, color: colors[index % colors.count], transactions: filteredTransactions.filter { $0.categoryRelationship?.name == element.key })
            }
        }
    }
    
    // Berechne die monatliche Daten für das Balkendiagramm
    func buildMonthlyData(for account: Account) -> [MonthlyData] {
        context.performAndWait {
            let transactions = (account.transactions?.allObjects as? [Transaction]) ?? []
            // Filtere Reservierungen und Umbuchungen aus
            let filteredTransactions = transactions.filter { $0.type != "umbuchung" && $0.type != "reservierung" }
            var monthlyEinnahmen: [String: Double] = [:]
            var monthlyAusgaben: [String: Double] = [:]
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM yyyy"
            for transaction in filteredTransactions {
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
        // Filtere Reservierungen aus allen Transaktions-Listen aus
        let nonReservationTx = allTx.filter { $0.type != "reservierung" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMM yyyy"
        
        switch filterType {
        case "Alle Monate":
            return nonReservationTx
        case "Benutzerdefinierter Zeitraum":
            guard let range = customDateRange else { return [] }
            return nonReservationTx.filter { transaction in
                let date = transaction.date
                return date >= range.start && date <= range.end
            }
        default:
            return nonReservationTx.filter { transaction in
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
            // Reservierungen werden automatisch ignoriert, da sie bereits herausgefiltert wurden
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
    public func importBankCSV(contents: String, account: Account, context: NSManagedObjectContext) throws -> ImportResult {
        // Hole das Account-Objekt in den richtigen Kontext
        guard let accountInContext = try context.existingObject(with: account.objectID) as? Account else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Konto konnte nicht im Import-Kontext gefunden werden"])
        }
        
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
        var amountIndex: Int?
        var categoryIndex: Int?
        var nameIndex: Int?
        var purposeIndex: Int?

        for (index, column) in header.enumerated() {
            let trimmedColumn = column.lowercased()
            switch trimmedColumn {
            case "datum", "buchungsdatum", "valutadatum", "date":
                dateIndex = index
            case "betrag", "amount_eur", "amount", "summe":
                amountIndex = index
            case "hauptkategorie", "kategorie", "category":
                categoryIndex = index
            case "name", "empfänger", "empfaenger", "auftraggeber":
                nameIndex = index
            case "zweck", "verwendungszweck", "verwendung", "purpose", "beschreibung":
                purposeIndex = index
            default:
                break
            }
        }

        guard let dateIdx = dateIndex, let amountIdx = amountIndex else {
            print("Fehlende benötigte Spalten in der CSV-Datei (Datum, Betrag sind erforderlich)")
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Fehlende benötigte Spalten in der CSV-Datei (Datum, Betrag sind erforderlich)"])
        }

        // DateFormatter für verschiedene Datumsformate
        let dateFormatters: [DateFormatter] = [
            {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                formatter.dateFormat = "dd.MM.yyyy"
                return formatter
            }(),
            {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter
            }(),
            {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                formatter.dateFormat = "dd.MM.yy"
                return formatter
            }()
        ]

        // NumberFormatter für verschiedene Betragsformate
        let numberFormatters: [NumberFormatter] = [
            {
                let formatter = NumberFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                formatter.numberStyle = .decimal
                formatter.decimalSeparator = ","
                formatter.groupingSeparator = "."
                return formatter
            }(),
            {
                let formatter = NumberFormatter()
                formatter.locale = Locale(identifier: "en_US")
                formatter.numberStyle = .decimal
                formatter.decimalSeparator = "."
                formatter.groupingSeparator = ","
                return formatter
            }()
        ]

        // Kalender für Jahresvalidierung und Datumsnormalisierung
        let calendar = Calendar.current

        // Arrays für Import-Ergebnisse
        var importedTransactions: [ImportResult.TransactionInfo] = []
        let skippedTransactions: [ImportResult.TransactionInfo] = []
        var suspiciousTransactions: [ImportResult.TransactionInfo] = []

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
            let requiredMaxIndex = max(dateIdx, amountIdx, categoryIndex ?? 0, nameIndex ?? 0, purposeIndex ?? 0)
            if cleanedColumns.count <= requiredMaxIndex {
                print("Zeile \(lineNumber + 2): Ungültige Zeile (zu wenige Spalten: \(cleanedColumns.count), benötigt: \(requiredMaxIndex + 1)): \(row)")
                continue
            }

            // Extrahiere die relevanten Werte und repariere Unicode-Umlaute
            let raw = cleanedColumns[dateIdx]
            let amountString = cleanedColumns[amountIdx]
            let category = categoryIndex != nil ? fixUmlauts(cleanedColumns[categoryIndex!]) ?? cleanedColumns[categoryIndex!] : ""
            let nameFromCSV = nameIndex != nil ? fixUmlauts(cleanedColumns[nameIndex!]) ?? cleanedColumns[nameIndex!] : ""
            let purpose = purposeIndex != nil ? fixUmlauts(cleanedColumns[purposeIndex!]) ?? cleanedColumns[purposeIndex!] : ""

            // Verarbeite Lohn-Transaktionen und extrahiere Namen
            let payrollResult = processPayrollTransaction(purpose: purpose, nameFromCSV: nameFromCSV)
            let finalPurpose = payrollResult.usage.isEmpty ? purpose : payrollResult.usage
            let payrollCategory = payrollResult.category

            // Verarbeitet Reservierungs-Transaktionen und extrahiert den Namen
            let reservationResult = processReservationTransaction(purpose: finalPurpose, nameFromCSV: nameFromCSV)
            let finalUsage = reservationResult.isReservation ? reservationResult.usage : finalPurpose
            let reservationCategory = reservationResult.category
            let isReservation = reservationResult.isReservation

            // Verarbeitet Firmen-Transaktionen mit intelligenter Kategorisierung
            let companyResult = processCompanyTransaction(purpose: finalUsage, nameFromCSV: nameFromCSV)
            let companyUsage = companyResult.isSpecialCompany ? companyResult.usage : finalUsage
            let companyCategory = companyResult.category
            let isSpecialCompany = companyResult.isSpecialCompany
            
            // Bestimme den finalen Verwendungszweck (Priorität: Firma > Reservierung > Lohn > Original)
            let finalFinalUsage = isSpecialCompany ? companyUsage : finalUsage

            // Konvertiere den Betrag
            var amount: Double?
            for formatter in numberFormatters {
                if let number = formatter.number(from: amountString) {
                    amount = number.doubleValue
                    break
                }
            }
            
            guard let finalAmount = amount else {
                print("Zeile \(lineNumber + 2): Ungültiger Betrag: \(amountString)")
                continue
            }

            // Normalisiere das Datum
            var normalizedDate: Date?
            for formatter in dateFormatters {
                if let date = formatter.date(from: raw) {
                    normalizedDate = date
                    break
                }
            }
            
            guard var finalDate = normalizedDate else {
                print("Zeile \(lineNumber + 2): Ungültiges Datum: \(raw)")
                continue
            }
            
            // Korrigiere das Jahr, falls es falsch geparst wurde (z.B. 0025 statt 2025)
            let components = calendar.dateComponents([.year, .month, .day], from: finalDate)
            if let year = components.year, year < 100 {
                var correctedComponents = components
                correctedComponents.year = year + 2000
                if let correctedDate = calendar.date(from: correctedComponents) {
                    finalDate = correctedDate
                    print("Zeile \(lineNumber + 2): Jahr korrigiert von \(year) zu \(correctedComponents.year ?? year)")
                }
            }

            // Bestimme den finalen Verwendungszweck und Kategorie
            let finalUsageForTransaction: String
            let categoryName: String
            
            if !reservationCategory.isEmpty {
                // Reservierungs-Transaktion: verwende die automatisch bestimmte Kategorie
                categoryName = reservationCategory
                finalUsageForTransaction = finalFinalUsage
                print("Zeile \(lineNumber + 2): Reservierungs-Transaktion erkannt, Kategorie automatisch gesetzt: \(categoryName)")
            } else if !payrollCategory.isEmpty {
                // Lohn-Transaktion: verwende die automatisch bestimmte Kategorie
                categoryName = payrollCategory
                finalUsageForTransaction = finalFinalUsage
                print("Zeile \(lineNumber + 2): Lohn-Transaktion erkannt, Kategorie automatisch gesetzt: \(categoryName)")
            } else if !companyCategory.isEmpty {
                // Firma: verwende die automatisch bestimmte Kategorie
                categoryName = companyCategory
                finalUsageForTransaction = finalFinalUsage
                print("Zeile \(lineNumber + 2): Firma erkannt, Kategorie automatisch gesetzt: \(categoryName)")
            } else if let suggestedCategory = suggestCategory(for: finalFinalUsage, amount: finalAmount) {
                // Lernvorschlag verfügbar
                categoryName = suggestedCategory
                finalUsageForTransaction = finalFinalUsage
                print("Zeile \(lineNumber + 2): Kategorie vorgeschlagen: \(categoryName)")
            } else {
                // Unbekannte Transaktion: Verwende Namen aus CSV und CSV-Kategorie als Fallback
                let nameFromCSVCleaned = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !nameFromCSVCleaned.isEmpty {
                    finalUsageForTransaction = nameFromCSVCleaned
                    print("Zeile \(lineNumber + 2): Unbekannte Transaktion - verwende Namen aus CSV: '\(nameFromCSVCleaned)'")
                } else {
                    finalUsageForTransaction = finalFinalUsage
                    print("Zeile \(lineNumber + 2): Unbekannte Transaktion - kein Name in CSV, verwende Original-Zweck")
                }
                
                // Verwende CSV-Kategorie als Fallback, sonst Sonstiges
                categoryName = !category.isEmpty ? category : "Sonstiges"
                print("Zeile \(lineNumber + 2): Kategorie aus CSV verwendet: '\(categoryName)'")
            }

            let fetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "name == %@", categoryName)
            let categories = try context.fetch(fetchRequest)
            let categoryObject: Category
            if let existingCategory = categories.first {
                categoryObject = existingCategory
            } else {
                categoryObject = Category(context: context)
                categoryObject.name = categoryName
            }

            // Prüfe auf verdächtige Transaktionen (nicht für Reservierungen)
            let isSuspiciousTransaction = !isReservation && (categoryName == "SB-Einzahlung" || 
                                        categoryName == "Geldautomat" ||
                                        (finalUsageForTransaction.lowercased().contains("sb-einzahlung")) ||
                                        (finalUsageForTransaction.lowercased().contains("einzahlung")) || 
                                        (finalUsageForTransaction.lowercased().contains("bargeld")))
            
            print("Zeile \(lineNumber + 2): Prüfe verdächtige Transaktion - Kategorie: '\(categoryName)', Zweck: '\(finalUsageForTransaction)', Reservierung: \(isReservation), verdächtig: \(isSuspiciousTransaction)")
            
            if isSuspiciousTransaction {
                print("Zeile \(lineNumber + 2): Verdächtige Transaktion erkannt - starte Duplikatsuche")
                
                // Suche nach ähnlichen Transaktionen
                let transactionFetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                var predicates: [NSPredicate] = [
                    NSPredicate(format: "abs(amount - %f) < 0.01", finalAmount),
                    NSPredicate(format: "account == %@", accountInContext)
                ]
                
                // Erweiterte Suche nach ähnlichen Zwecken
                let usagePredicates = [
                    NSPredicate(format: "usage CONTAINS[cd] %@", "sb-einzahlung"),
                    NSPredicate(format: "usage CONTAINS[cd] %@", "einzahlung"),
                    NSPredicate(format: "usage CONTAINS[cd] %@", "bargeld"),
                    NSPredicate(format: "categoryRelationship.name == %@", "Geldautomat"),
                    NSPredicate(format: "categoryRelationship.name == %@", "SB-Einzahlung")
                ]
                predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: usagePredicates))
                
                transactionFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                let existingTransactions = try context.fetch(transactionFetchRequest)
                
                print("Zeile \(lineNumber + 2): Gefundene ähnliche Transaktionen: \(existingTransactions.count)")
                for existing in existingTransactions {
                    print("  - Datum: \(existing.date), Betrag: \(existing.amount), Zweck: \(existing.usage ?? "nil"), Kategorie: \(existing.categoryRelationship?.name ?? "nil")")
                }
                
                if !existingTransactions.isEmpty {
                    print("Zeile \(lineNumber + 2): Transaktion als verdächtig markiert - wird zur manuellen Überprüfung hinzugefügt")
                    // Füge zur Liste der verdächtigen Transaktionen hinzu
                    suspiciousTransactions.append(ImportResult.TransactionInfo(
                        date: raw,
                        amount: finalAmount,
                        account: accountInContext.name ?? "",
                        usage: finalUsageForTransaction,
                        category: categoryName,
                        isSuspicious: true,
                        existingTransaction: existingTransactions.first
                    ))
                    continue
                }
            }

            // Erstelle die Transaktion
            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.date = finalDate
            
            // Bestimme den Transaktionstyp
            if isReservation {
                transaction.type = "reservierung"
                print("Zeile \(lineNumber + 2): Reservierungs-Transaktion erstellt")
            } else {
                transaction.type = finalAmount > 0 ? "einnahme" : "ausgabe"
            }
            
            transaction.amount = finalAmount
            transaction.categoryRelationship = categoryObject
            transaction.usage = finalUsageForTransaction
            transaction.account = accountInContext

            // Lerne aus der Kategorisierung (nicht für Reservierungen)
            if !isReservation {
                learnCategory(for: transaction)
            }

            print("Zeile \(lineNumber + 2): Neue Transaktion erstellt: id=\(transaction.id.uuidString), Datum=\(finalDate), Betrag=\(finalAmount), Typ=\(transaction.type ?? "nil"), Kategorie=\(categoryName), Usage=\(finalUsageForTransaction)")
            
            importedTransactions.append(ImportResult.TransactionInfo(
                date: raw,
                amount: finalAmount,
                account: accountInContext.name ?? "",
                usage: finalUsageForTransaction,
                category: categoryName,
                isSuspicious: false,
                existingTransaction: nil
            ))
        }

        // Speichere den Kontext
        try context.save()
        print("Bank CSV-Import erfolgreich abgeschlossen")

        return ImportResult(imported: importedTransactions, skipped: skippedTransactions, suspicious: suspiciousTransactions)
    }

    // Hilfsfunktionen für den CSV-Import

    // Bereinigt Firmennamen und entfernt Adressen
    private func cleanCompanyName(_ input: String) -> String {
        // Repariere zuerst Unicode-Umlaute
        let fixedInput = fixUmlauts(input) ?? input
        var cleaned = fixedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Bekannte Firmennamen-Muster (einschließlich Krankenkassen)
        let companyPatterns: [(pattern: String, replacement: String)] = [
            ("STRATO\\s+GmbH[^,]*?(?:,\\s*[^,]+)?", "STRATO GmbH"),
            ("Vodafone\\s+GmbH[^,]*?(?:,\\s*[^,]+)?", "Vodafone GmbH"),
            ("Wolt\\s+License\\s+Services\\s+Oy[^,]*", "Wolt"),
            ("Uber\\s+Payments\\s+B\\.V\\.[^,]*", "Uber"),
            ("SIGNAL\\s+IDUNA[^,]*", "SIGNAL IDUNA"),
            ("EK\\s+TECHNIKER\\s+KRANKENKASSE[^,]*", "EK Techniker Krankenkasse"),
            ("TECHNIKER\\s+KRANKENKASSE[^,]*", "Techniker Krankenkasse"),
            ("AOK\\s+NORDOST[^,]*", "AOK Nordost"),
            ("AOK[^,]*", "AOK Nordost"),
            ("BARMER[^,]*", "Barmer"),
            ("DAK\\s+GESUNDHEIT[^,]*", "DAK Gesundheit"),
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
        
        // Erweiterte Unicode-Ersetzungstabelle
        let umlautReplacements: [String: String] = [
            // Standard-Replacements
            "√ú": "Ü", "√ü": "ß", "√∂": "ö", "√§": "ä",
            "√Ñ": "Ä", "√Ö": "Ö", "√ñ": "Ö", "√º": "ü",
            "√©": "é", "√®": "è", "√†": "à", "√¢": "â",
            "√ª": "û", "√•": "å", "√´": "ë", "√¨": "ï",
            "√Æ": "î", "√≤": "ò", "√≥": "ó", "√¥": "ô",
            "√µ": "õ", "√∏": "ø", "√π": "ù", "√æ": "þ",
            "√ø": "ÿ", "√±": "ñ", "√ß": "ç",
            
            // Zusätzliche problematische Zeichen (spezifischere Ersetzungen)
            "√ºhren": "ühren",    // Für "Bankgeb√ºhren" → "Bankgebühren"
            "√úm√ºt": "Ümüt",     // Für "Mutlu √úm√ºt" → "Mutlu Ümüt"
            
            // Weitere problematische Kombinationen
            "geb√ºhren": "gebühren",
            "b√ºhren": "bühren",
            "f√ºr": "für",
            "Fr√ºh": "Früh",
            "M√ºnchen": "München",
            "D√ºsseldorf": "Düsseldorf",
            "K√∂ln": "Köln",
            "Sch√∂n": "Schön",
            "Gr√ºn": "Grün",
            
            // Problematische Ä, Ö Kombinationen
            "√Ñrger": "Ärger",
            "√Ñnderung": "Änderung",
            "√Ör": "Ör",
            "L√∂sung": "Lösung"
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
            let isSuspicious: Bool
            let existingTransaction: Transaction?
        }
        
        let imported: [TransactionInfo]
        let skipped: [TransactionInfo]
        let suspicious: [TransactionInfo]  // Neue Liste für verdächtige Transaktionen
        
        var summary: String {
            return "\(imported.count) Transaktionen importiert, \(skipped.count) übersprungene Duplikate, \(suspicious.count) verdächtige Transaktionen"
        }
    }

    func calculateAllBalances() -> [NSManagedObjectID: Double] {
        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: "Transaction")
        fetchRequest.resultType = .dictionaryResultType
        
        // Schließe Reservierungen aus allen Bilanz-Berechnungen aus
        fetchRequest.predicate = NSPredicate(format: "type != %@", "reservierung")

        let sumExpression = NSExpressionDescription()
        sumExpression.name = "totalAmount"
        sumExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "amount")])
        sumExpression.expressionResultType = .doubleAttributeType

        fetchRequest.propertiesToGroupBy = ["account", "type"]
        fetchRequest.propertiesToFetch = ["account", "type", sumExpression]

        do {
            let results = try context.fetch(fetchRequest)
            var balanceDict: [NSManagedObjectID: Double] = [:]
            var einnahmenDict: [NSManagedObjectID: Double] = [:]
            var ausgabenDict: [NSManagedObjectID: Double] = [:]
            var umbuchungenDict: [NSManagedObjectID: Double] = [:]
            
            // Initialisiere alle Konten mit 0
            let accountFetch = NSFetchRequest<Account>(entityName: "Account")
            if let accounts = try? context.fetch(accountFetch) {
                for account in accounts {
                    balanceDict[account.objectID] = 0.0
                    einnahmenDict[account.objectID] = 0.0
                    ausgabenDict[account.objectID] = 0.0
                    umbuchungenDict[account.objectID] = 0.0
                }
            }
            
            // Berechne die Bilanzen (ohne Reservierungen)
            for result in results {
                if let account = result["account"] as? NSManagedObjectID,
                   let balance = result["totalAmount"] as? Double,
                   let type = result["type"] as? String {
                    let currentBalance = balanceDict[account] ?? 0.0
                    if type == "einnahme" {
                        balanceDict[account] = currentBalance + balance
                        einnahmenDict[account] = (einnahmenDict[account] ?? 0.0) + balance
                    } else if type == "ausgabe" {
                        balanceDict[account] = currentBalance + balance // Korrigiert: addiere, da bereits negativ
                        ausgabenDict[account] = (ausgabenDict[account] ?? 0.0) + balance
                    } else if type == "umbuchung" {
                        balanceDict[account] = currentBalance + balance // Umbuchungen werden auch addiert
                        umbuchungenDict[account] = (umbuchungenDict[account] ?? 0.0) + balance
                    }
                    // "reservierung" wird automatisch ignoriert durch das Predicate
                }
            }
            print("Berechnete Kontostände (ohne Reservierungen):")
            for (accountID, balance) in balanceDict {
                var name = "-"
                let einnahmen = einnahmenDict[accountID] ?? 0.0
                let ausgaben = ausgabenDict[accountID] ?? 0.0
                let umbuchungen = umbuchungenDict[accountID] ?? 0.0
                if let account = try? context.existingObject(with: accountID) as? Account {
                    name = account.name ?? "-"
                }
                print("  Konto: \(name) | Einnahmen: \(einnahmen) | Ausgaben: \(ausgaben) | Umbuchungen: \(umbuchungen) | Bilanz: \(balance)")
            }
            return balanceDict
        } catch {
            print("Fehler beim Berechnen aller Kontostände: \(error.localizedDescription)")
            return [:]
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
            // Zuerst alle Umbuchungen löschen (mit Speziallogik)
            for transaction in transactions {
                if transaction.type == "umbuchung" {
                    print("DEBUG: Lösche Umbuchung: \(transaction.id) Typ: \(transaction.type ?? "nil")")
                    self.deleteTransaction(transaction)
                }
            }
            // Dann alle anderen Transaktionen löschen
            for transaction in transactions {
                if transaction.type != "umbuchung" {
                    print("DEBUG: Lösche normale Transaktion: \(transaction.id) Typ: \(transaction.type ?? "nil")")
                    self.context.delete(transaction)
                }
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

    /// Korrigiert alle Ausgaben, die fälschlicherweise als positiver Betrag gespeichert wurden
    func fixAllPositiveExpenses() {
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "type == %@ AND amount > 0", "ausgabe")
        do {
            let wrongTransactions = try context.fetch(fetchRequest)
            var changed = 0
            for tx in wrongTransactions {
                tx.amount = -abs(tx.amount)
                changed += 1
            }
            if changed > 0 {
                try context.save()
                print("Alle fehlerhaften Ausgaben korrigiert! (", changed, ")")
            } else {
                print("Keine fehlerhaften Ausgaben gefunden.")
            }
        } catch {
            print("Fehler bei der Korrektur der Ausgaben: \(error)")
        }
    }

    func uploadBackupToWebDAV(backupURL: URL) {
        let webdavURL = UserDefaults.standard.string(forKey: "webdavURL") ?? ""
        let webdavUser = UserDefaults.standard.string(forKey: "webdavUser") ?? ""
        let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") ?? ""
        
        guard !webdavURL.isEmpty, !webdavUser.isEmpty, !webdavPassword.isEmpty else {
            print("WebDAV-Zugangsdaten fehlen")
            NotificationCenter.default.post(
                name: Notification.Name("WebDAVError"),
                object: nil,
                userInfo: ["message": "WebDAV-Zugangsdaten fehlen. Bitte überprüfen Sie die Einstellungen."]
            )
            return
        }
        
        guard let serverURL = URL(string: webdavURL) else {
            print("Ungültige WebDAV-URL")
            NotificationCenter.default.post(
                name: Notification.Name("WebDAVError"),
                object: nil,
                userInfo: ["message": "Ungültige WebDAV-URL. Bitte überprüfen Sie die URL in den Einstellungen."]
            )
            return
        }
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "PUT"
        let authString = "\(webdavUser):\(webdavPassword)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let backupData = try Data(contentsOf: backupURL)
            request.httpBody = backupData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("WebDAV Upload Fehler: \(error)")
                    NotificationCenter.default.post(
                        name: Notification.Name("WebDAVError"),
                        object: nil,
                        userInfo: ["message": "Fehler beim Upload: \(error.localizedDescription)"]
                    )
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200, 201, 204: // 204 ist ein erfolgreicher Status (No Content)
                        print("WebDAV Backup erfolgreich hochgeladen (Status: \(httpResponse.statusCode))")
                        NotificationCenter.default.post(
                            name: Notification.Name("WebDAVSuccess"),
                            object: nil,
                            userInfo: ["message": "Backup erfolgreich gespeichert"]
                        )
                    case 401:
                        print("WebDAV Upload: Authentifizierung fehlgeschlagen")
                        NotificationCenter.default.post(
                            name: Notification.Name("WebDAVError"),
                            object: nil,
                            userInfo: ["message": "Authentifizierung fehlgeschlagen. Bitte überprüfen Sie Benutzername und Passwort."]
                        )
                    case 403:
                        print("WebDAV Upload: Zugriff verweigert")
                        NotificationCenter.default.post(
                            name: Notification.Name("WebDAVError"),
                            object: nil,
                            userInfo: ["message": "Zugriff verweigert. Bitte überprüfen Sie die Berechtigungen."]
                        )
                    case 404:
                        print("WebDAV Upload: Pfad nicht gefunden")
                        NotificationCenter.default.post(
                            name: Notification.Name("WebDAVError"),
                            object: nil,
                            userInfo: ["message": "Der angegebene Pfad wurde nicht gefunden. Bitte überprüfen Sie die WebDAV-URL."]
                        )
                    default:
                        print("WebDAV Upload fehlgeschlagen: Status \(httpResponse.statusCode)")
                        NotificationCenter.default.post(
                            name: Notification.Name("WebDAVError"),
                            object: nil,
                            userInfo: ["message": "Backup fehlgeschlagen (Status \(httpResponse.statusCode)). Bitte überprüfen Sie die Einstellungen."]
                        )
                    }
                }
            }
            task.resume()
        } catch {
            print("Fehler beim Lesen der Backup-Datei: \(error)")
            NotificationCenter.default.post(
                name: Notification.Name("WebDAVError"),
                object: nil,
                userInfo: ["message": "Fehler beim Lesen der Backup-Datei: \(error.localizedDescription)"]
            )
        }
    }

    func getAllAccounts() -> [Account] {
        let fetchRequest: NSFetchRequest<Account> = Account.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Account.name, ascending: true)]
        
        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("Fehler beim Laden der Konten: \(error)")
            return []
        }
    }

    // Struktur für die Lernfunktion der Kategorien
    struct CategoryLearningRule {
        let pattern: String
        let category: String
        let usage: String?
        var count: Int  // Mache count mutable
        
        static func saveRules(_ rules: [CategoryLearningRule]) {
            let rulesData = rules.map { rule -> [String: Any] in
                return [
                    "pattern": rule.pattern,
                    "category": rule.category,
                    "usage": rule.usage ?? "",
                    "count": rule.count
                ]
            }
            UserDefaults.standard.set(rulesData, forKey: "categoryLearningRules")
        }
        
        static func loadRules() -> [CategoryLearningRule] {
            guard let rulesData = UserDefaults.standard.array(forKey: "categoryLearningRules") as? [[String: Any]] else {
                return []
            }
            
            return rulesData.compactMap { data in
                guard let pattern = data["pattern"] as? String,
                      let category = data["category"] as? String,
                      let count = data["count"] as? Int else {
                    return nil
                }
                let usage = data["usage"] as? String
                return CategoryLearningRule(pattern: pattern, category: category, usage: usage, count: count)
            }
        }
    }

    // Hilfsfunktionen für die Kategorisierung
    private func learnCategory(for transaction: Transaction) {
        var rules = CategoryLearningRule.loadRules()
        
        // Erstelle einen Schlüssel basierend auf dem bereinigten Zweck
        guard let usage = transaction.usage, !usage.isEmpty else { return }
        
        // Bereinige den Zweck für bessere Kategorisierung
        let cleanedUsage = cleanUsageForLearning(usage)
        let pattern = cleanedUsage
        
        // Suche nach existierender Regel
        if let index = rules.firstIndex(where: { $0.pattern == pattern }) {
            // Erhöhe den Zähler der existierenden Regel
            rules[index].count += 1
            print("Lernregel aktualisiert: '\(pattern)' -> '\(rules[index].category)' (Anzahl: \(rules[index].count))")
        } else {
            // Erstelle neue Regel
            let newRule = CategoryLearningRule(
                pattern: pattern,
                category: transaction.categoryRelationship?.name ?? "Sonstiges",
                usage: usage,
                count: 1
            )
            rules.append(newRule)
            print("Neue Lernregel erstellt: '\(pattern)' -> '\(newRule.category)'")
        }
        
        // Speichere die aktualisierten Regeln
        CategoryLearningRule.saveRules(rules)
    }

    private func suggestCategory(for usage: String?, amount: Double) -> String? {
        guard let usage = usage, !usage.isEmpty else { return nil }
        
        let rules = CategoryLearningRule.loadRules()
        let cleanedUsage = cleanUsageForLearning(usage)
        
        // Suche nach exakter Übereinstimmung
        if let rule = rules.first(where: { $0.pattern == cleanedUsage }) {
            print("Kategorie-Vorschlag gefunden (exakt): '\(cleanedUsage)' -> '\(rule.category)' (Anzahl: \(rule.count))")
            return rule.category
        }
        
        // Suche nach ähnlichen Zwecken
        let similarRules = rules.filter { rule in
            let ruleUsage = rule.usage?.lowercased() ?? ""
            let searchUsage = usage.lowercased()
            return ruleUsage.contains(searchUsage) || searchUsage.contains(ruleUsage)
        }
        
        if let bestMatch = similarRules.max(by: { $0.count < $1.count }) {
            print("Kategorie-Vorschlag gefunden (ähnlich): '\(usage)' -> '\(bestMatch.category)' (Anzahl: \(bestMatch.count))")
            return bestMatch.category
        }
        
        return nil
    }

    // Bereinigt den Zweck für das Lernen von Kategorien
    private func cleanUsageForLearning(_ usage: String) -> String {
        var cleaned = usage.lowercased()
        
        // Entferne Datumsangaben
        let datePatterns = [
            "\\d{2}\\.\\d{2}\\.\\d{4}",
            "\\d{8}",
            "\\d{1,2}:\\d{2}",
            "datum.*?uhr"
        ]
        for pattern in datePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        // Entferne Nummern und Codes
        let numberPatterns = [
            "\\d{6,}",
            "rg\\.?\\s*\\d+",
            "inv\\s*\\d+",
            "nr\\.?\\s*\\d+",
            "betriebsnummer\\s*\\d+"
        ]
        for pattern in numberPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        // Bereinige Satzzeichen und mehrfache Leerzeichen
        cleaned = cleaned.replacingOccurrences(of: "[^a-zäöüß\\s]", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }

    // Verarbeitet Lohn-Transaktionen und extrahiert den Namen
    private func processPayrollTransaction(purpose: String, nameFromCSV: String) -> (usage: String, category: String) {
        let purposeLower = purpose.lowercased()
        
        // Erkenne Lohn-Transaktionen
        let salaryKeywords = ["lohn", "löhne", "gehalt", "vergütung", "entgelt", "arbeitsentgelt"]
        let isSalaryTransaction = salaryKeywords.contains { keyword in
            purposeLower.contains(keyword)
        }
        
        if isSalaryTransaction {
            // Extrahiere den Namen - zuerst aus CSV, dann aus Verwendungszweck
            var personName: String?
            
            // 1. Versuche Namen aus CSV-Spalte zu extrahieren
            if !nameFromCSV.isEmpty {
                personName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // 2. Falls kein Name in CSV, versuche aus Verwendungszweck zu extrahieren
            if personName == nil || personName!.isEmpty {
                // Muster für Namen im Verwendungszweck
                let namePatterns = [
                    // "LOHN FÜR HANS MÜLLER" oder ähnlich
                    "(?i)lohn\\s+(?:für|von|an)?\\s+([A-ZÄÖÜ][a-zäöüß]+(?:\\s+[A-ZÄÖÜ][a-zäöüß]+)*)",
                    // "GEHALT MARIA SCHMIDT" oder ähnlich
                    "(?i)gehalt\\s+([A-ZÄÖÜ][a-zäöüß]+(?:\\s+[A-ZÄÖÜ][a-zäöüß]+)*)",
                    // "VERGÜTUNG FÜR PETER WAGNER"
                    "(?i)vergütung\\s+(?:für|von|an)?\\s+([A-ZÄÖÜ][a-zäöüß]+(?:\\s+[A-ZÄÖÜ][a-zäöüß]+)*)"
                ]
                
                for pattern in namePatterns {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: purpose, options: [], range: NSRange(location: 0, length: purpose.utf16.count)),
                       let nameRange = Range(match.range(at: 1), in: purpose) {
                        personName = String(purpose[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
            
            // Formatiere den finalen Verwendungszweck
            let finalUsage: String
            if let name = personName, !name.isEmpty {
                finalUsage = "Lohn \(name)"
            } else {
                finalUsage = "Lohn"
            }
            
            print("Lohn-Transaktion erkannt: Original='\(purpose)', Name aus CSV='\(nameFromCSV)', Extrahierter Name='\(personName ?? "nil")', Final='\(finalUsage)'")
            
            return (usage: finalUsage, category: "Personal")
        }
        
        // Nicht-Lohn-Transaktion, gib Original zurück
        return (usage: purpose, category: "")
    }

    // Verarbeitet Reservierungs-Transaktionen und extrahiert den Namen
    private func processReservationTransaction(purpose: String, nameFromCSV: String) -> (usage: String, category: String, isReservation: Bool) {
        let purposeLower = purpose.lowercased()
        
        // Erkenne Reservierungs-Transaktionen
        let reservationKeywords = ["reservierung", "anzahlung", "kaution", "deposit", "vorauszahlung", "buchung", "reservation"]
        let isReservationTransaction = reservationKeywords.contains { keyword in
            purposeLower.contains(keyword)
        }
        
        if isReservationTransaction {
            // Extrahiere den Namen - zuerst aus CSV, dann aus Verwendungszweck
            var personName: String?
            
            // 1. Versuche Namen aus CSV-Spalte zu extrahieren
            if !nameFromCSV.isEmpty {
                personName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // 2. Falls kein Name in CSV, versuche aus Verwendungszweck zu extrahieren
            if personName == nil || personName!.isEmpty {
                // Muster für Namen im Verwendungszweck
                let namePatterns = [
                    // "RESERVIERUNG FÜR HANS MÜLLER" oder ähnlich
                    "(?i)reservierung\\s+(?:für|von|an)?\\s+([A-ZÄÖÜ][a-zäöüß]+(?:\\s+[A-ZÄÖÜ][a-zäöüß]+)*)",
                    // "ANZAHLUNG MARIA SCHMIDT" oder ähnlich
                    "(?i)anzahlung\\s+(?:für|von)?\\s+([A-ZÄÖÜ][a-zäöüß]+(?:\\s+[A-ZÄÖÜ][a-zäöüß]+)*)",
                    // "KAUTION FÜR PETER WAGNER"
                    "(?i)kaution\\s+(?:für|von|an)?\\s+([A-ZÄÖÜ][a-zäöüß]+(?:\\s+[A-ZÄÖÜ][a-zäöüß]+)*)",
                    // "BUCHUNG FAMILY NAME"
                    "(?i)buchung\\s+(?:für|von)?\\s+([A-ZÄÖÜ][a-zäöüß]+(?:\\s+[A-ZÄÖÜ][a-zäöüß]+)*)",
                    // Allgemeineres Muster: Namen nach bestimmten Wörtern
                    "(?i)(?:herr|frau|familie|family|mr|mrs|ms)\\s+([A-ZÄÖÜ][a-zäöüß]+(?:\\s+[A-ZÄÖÜ][a-zäöüß]+)*)"
                ]
                
                for pattern in namePatterns {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: purpose, options: [], range: NSRange(location: 0, length: purpose.utf16.count)),
                       let nameRange = Range(match.range(at: 1), in: purpose) {
                        personName = String(purpose[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
            
            // Formatiere den finalen Verwendungszweck
            let finalUsage: String
            if let name = personName, !name.isEmpty {
                finalUsage = "Reservierung \(name)"
            } else {
                finalUsage = "Reservierung"
            }
            
            print("Reservierungs-Transaktion erkannt: Original='\(purpose)', Name aus CSV='\(nameFromCSV)', Extrahierter Name='\(personName ?? "nil")', Final='\(finalUsage)'")
            
            return (usage: finalUsage, category: "Reservierung", isReservation: true)
        }
        
        // Nicht-Reservierungs-Transaktion, gib Original zurück
        return (usage: purpose, category: "", isReservation: false)
    }

    // Verarbeitet Firmen-Transaktionen mit intelligenter Kategorisierung
    private func processCompanyTransaction(purpose: String, nameFromCSV: String) -> (usage: String, category: String, isSpecialCompany: Bool) {
        let purposeLower = purpose.lowercased()
        let nameLower = nameFromCSV.lowercased()
        
        // 🏥 KRANKENKASSEN-ERKENNUNG (höchste Priorität)
        // Jede Betriebsnummer = KV-Beitrag, Name aus CSV-Spalte
        if purposeLower.contains("betriebsnummer") {
            let krankenkasseName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !krankenkasseName.isEmpty {
                let finalUsage = "KV-Beitrag \(krankenkasseName)"
                print("🏥 KV-Beitrag erkannt über Betriebsnummer: Name aus CSV='\(krankenkasseName)' -> '\(finalUsage)'")
                return (usage: finalUsage, category: "KV-Beiträge", isSpecialCompany: true)
            } else {
                print("🏥 KV-Beitrag erkannt über Betriebsnummer: Kein Name in CSV -> 'KV-Beitrag'")
                return (usage: "KV-Beitrag", category: "KV-Beiträge", isSpecialCompany: true)
            }
        }
        
        // 🏧 SB-EINZAHLUNG (spezielle Behandlung)
        if purposeLower.contains("sb-einzahlung") || purposeLower.contains("sb einzahlung") {
            // Extrahiere Datum aus dem Verwendungszweck
            let datePattern = "\\d{2}\\.\\d{2}\\.\\d{2,4}"
            if let regex = try? NSRegularExpression(pattern: datePattern, options: []),
               let match = regex.firstMatch(in: purpose, options: [], range: NSRange(location: 0, length: purpose.utf16.count)),
               let dateRange = Range(match.range, in: purpose) {
                let datum = String(purpose[dateRange])
                let cleanUsage = "SB-Einzahlung - \(datum)"
                print("🏧 SB-Einzahlung erkannt: Datum='\(datum)' -> '\(cleanUsage)'")
                return (usage: cleanUsage, category: "Geldautomat", isSpecialCompany: true)
            } else {
                print("🏧 SB-Einzahlung erkannt: Kein Datum gefunden -> 'SB-Einzahlung'")
                return (usage: "SB-Einzahlung", category: "Geldautomat", isSpecialCompany: true)
            }
        }
        
        // 🌐 INTERNETKOSTEN (suche sowohl in purpose als auch in nameFromCSV)
        if purposeLower.contains("strato") || nameLower.contains("strato") {
            let cleanedName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUsage = !cleanedName.isEmpty ? "\(cleanedName) - Internetkosten" : "STRATO - Internetkosten"
            print("🌐 STRATO erkannt: Name='\(cleanedName)' -> '\(finalUsage)'")
            return (usage: finalUsage, category: "Internetkosten", isSpecialCompany: true)
        }
        
        // 🛡️ VERSICHERUNGEN (nur nicht-Krankenversicherungen)
        if purposeLower.contains("signal iduna") || purposeLower.contains("signal-iduna") || 
           nameLower.contains("signal iduna") || nameLower.contains("signal-iduna") {
            let cleanedName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUsage = !cleanedName.isEmpty ? "\(cleanedName) - Versicherung" : "Signal Iduna - Versicherung"
            print("🛡️ Signal Iduna erkannt: Name='\(cleanedName)' -> '\(finalUsage)'")
            return (usage: finalUsage, category: "Versicherungen", isSpecialCompany: true)
        }
        
        // 🛒 WARENEINKAUF
        if purposeLower.contains("acai") || nameLower.contains("acai") {
            let cleanedName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUsage = !cleanedName.isEmpty ? "\(cleanedName) - Wareneinkauf" : "Acai - Wareneinkauf"
            print("🛒 Acai erkannt: Name='\(cleanedName)' -> '\(finalUsage)'")
            return (usage: finalUsage, category: "Wareneinkauf", isSpecialCompany: true)
        }
        
        // 💰 EINNAHMEN (Lieferdienste)
        if purposeLower.contains("uber") || purposeLower.contains("wolt") ||
           nameLower.contains("uber") || nameLower.contains("wolt") {
            let service = purposeLower.contains("uber") || nameLower.contains("uber") ? "Uber" : "Wolt"
            let cleanedName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUsage = !cleanedName.isEmpty ? "\(cleanedName) - Einnahme" : "\(service) - Einnahme"
            print("💰 \(service) erkannt: Name='\(cleanedName)' -> '\(finalUsage)'")
            return (usage: finalUsage, category: "Einnahmen", isSpecialCompany: true)
        }
        
        // 🏢 RAUMKOSTEN
        if purposeLower.contains("miete") || purposeLower.contains("nebenkosten") ||
           nameLower.contains("miete") || nameLower.contains("nebenkosten") {
            let cleanedName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUsage = !cleanedName.isEmpty ? "\(cleanedName) - Miete" : "Miete"
            print("🏢 Miete erkannt: Name='\(cleanedName)' -> '\(finalUsage)'")
            return (usage: finalUsage, category: "Raumkosten", isSpecialCompany: true)
        }
        
        // 🏛️ STEUERN
        if purposeLower.contains("finanzamt") || nameLower.contains("finanzamt") {
            let cleanedName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUsage = !cleanedName.isEmpty ? "\(cleanedName) - Steuer" : "Finanzamt - Steuer"
            print("🏛️ Finanzamt erkannt: Name='\(cleanedName)' -> '\(finalUsage)'")
            return (usage: finalUsage, category: "Steuern", isSpecialCompany: true)
        }
        
        // 📞 HANDY & INTERNET
        if purposeLower.contains("vodafone") || nameLower.contains("vodafone") {
            let cleanedName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUsage = !cleanedName.isEmpty ? "\(cleanedName) - Handy" : "Vodafone - Handy"
            print("📞 Vodafone erkannt: Name='\(cleanedName)' -> '\(finalUsage)'")
            return (usage: finalUsage, category: "Handy & Internet", isSpecialCompany: true)
        }
        
        // ⚡ STROM/GAS
        if purposeLower.contains("strom") || purposeLower.contains("gas") || purposeLower.contains("energie") ||
           nameLower.contains("strom") || nameLower.contains("gas") || nameLower.contains("energie") {
            let cleanedName = nameFromCSV.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUsage = !cleanedName.isEmpty ? "\(cleanedName) - Strom/Gas" : "Strom/Gas"
            print("⚡ Strom/Gas erkannt: Name='\(cleanedName)' -> '\(finalUsage)'")
            return (usage: finalUsage, category: "Strom/Gas", isSpecialCompany: true)
        }
        
        return (usage: purpose, category: "", isSpecialCompany: false)
    }

    // Bereinige alle Kategorienamen von Unicode-Problemen
    func fixAllCategoryNames() {
        context.perform {
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            guard let allCategories = try? self.context.fetch(request) else {
                print("Fehler beim Laden der Kategorien für Unicode-Bereinigung")
                return
            }
            
            var fixedCount = 0
            for category in allCategories {
                if let originalName = category.name {
                    if let fixedName = self.fixUmlauts(originalName), fixedName != originalName {
                        category.name = fixedName
                        fixedCount += 1
                        print("Kategorie bereinigt: '\(originalName)' -> '\(fixedName)'")
                    }
                }
            }
            
            if fixedCount > 0 {
                self.saveContext(self.context) { error in
                    if let error = error {
                        print("Fehler beim Speichern der bereinigten Kategorien: \(error)")
                        return
                    }
                    print("Unicode-Bereinigung abgeschlossen: \(fixedCount) Kategorien bereinigt")
                    self.fetchCategories()
                }
            } else {
                print("Keine Kategorien mit Unicode-Problemen gefunden")
            }
        }
    }

    // Bereinige die fehlerhafte Bankgebühren-Kategorie
    func cleanupBankgebuehrenCategory() {
        context.performAndWait {
            // Suche nach der fehlerhaften Kategorie
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", "Bankgeb√ºhren")
            
            guard let invalidCategory = try? context.fetch(request).first else {
                print("Fehlerhafte Bankgebühren-Kategorie nicht gefunden")
                return
            }
            
            // Suche nach der korrekten Kategorie
            let correctRequest: NSFetchRequest<Category> = Category.fetchRequest()
            correctRequest.predicate = NSPredicate(format: "name == %@", "Bankgebühren")
            
            let correctCategory: Category
            if let existing = try? context.fetch(correctRequest).first {
                correctCategory = existing
            } else {
                // Erstelle die korrekte Kategorie, falls sie noch nicht existiert
                correctCategory = Category(context: context)
                correctCategory.name = "Bankgebühren"
            }
            
            // Hole alle Transaktionen der fehlerhaften Kategorie
            if let transactions = invalidCategory.transactions?.allObjects as? [Transaction] {
                print("Verschiebe \(transactions.count) Transaktionen zur korrekten Kategorie")
                for transaction in transactions {
                    transaction.categoryRelationship = correctCategory
                }
            }
            
            // Lösche die fehlerhafte Kategorie
            context.delete(invalidCategory)
            
            // Speichere die Änderungen
            saveContext(context) { error in
                if let error = error {
                    print("Fehler beim Bereinigen der Bankgebühren-Kategorie: \(error)")
                    return
                }
                print("Bankgebühren-Kategorie erfolgreich bereinigt")
                self.fetchCategories()
            }
        }
    }
    
    // Bereinige SB-Zahlungen und markiere sie als Umbuchungen
    func cleanupSBZahlungen() {
        context.perform {
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            
            // Suche nach Transaktionen, die eigentlich Umbuchungen sind
            let orPredicates = [
                NSPredicate(format: "usage CONTAINS[cd] %@", "sb-zahlung"),
                NSPredicate(format: "usage CONTAINS[cd] %@", "bargeldauszahlung"),
                NSPredicate(format: "usage CONTAINS[cd] %@", "auszahlung geldautomat"),
                NSPredicate(format: "usage CONTAINS[cd] %@ AND usage CONTAINS[cd] %@", "übertrag", "konto"),
                NSPredicate(format: "usage CONTAINS[cd] %@ AND usage CONTAINS[cd] %@", "umbuchung", "konto")
            ]
            
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: orPredicates)
            
            do {
                let transactions = try self.context.fetch(request)
                var updated = 0
                
                for transaction in transactions {
                    if transaction.type != "umbuchung" {
                        print("Ändere Transaktion von '\(transaction.type ?? "nil")' zu 'umbuchung': \(transaction.usage ?? "")")
                        transaction.type = "umbuchung"
                        updated += 1
                    }
                }
                
                if updated > 0 {
                    try self.context.save()
                    print("✅ \(updated) Transaktionen als Umbuchungen markiert")
                    
                    // UI aktualisieren
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.fetchAccountGroups()
                        self.transactionsUpdated.toggle()
                    }
                }
            } catch {
                print("Fehler beim Bereinigen der SB-Zahlungen: \(error)")
            }
        }
    }
    
    // Automatische Erkennung von Umbuchungen beim Import
    func detectTransactionType(usage: String?, amount: Double, sourceAccount: Account?, targetAccount: Account?) -> String {
        guard let usage = usage?.lowercased() else {
            return amount >= 0 ? "einnahme" : "ausgabe"
        }
        
        // Muster für Umbuchungen
        let transferPatterns = [
            "sb-zahlung",
            "bargeldauszahlung",
            "auszahlung geldautomat",
            "übertrag",
            "umbuchung",
            "cash withdrawal",
            "atm"
        ]
        
        // Prüfe ob es eine Umbuchung ist
        for pattern in transferPatterns {
            if usage.contains(pattern) {
                return "umbuchung"
            }
        }
        
        // Wenn ein Zielkonto angegeben ist, ist es eine Umbuchung
        if targetAccount != nil && targetAccount != sourceAccount {
            return "umbuchung"
        }
        
        // Sonst basierend auf Betrag
        return amount >= 0 ? "einnahme" : "ausgabe"
    }
}

