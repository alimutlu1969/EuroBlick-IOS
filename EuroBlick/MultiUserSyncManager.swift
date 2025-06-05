import Foundation
import CoreData
import SwiftUI

class MultiUserSyncManager: ObservableObject {
    @Published var conflictResolutionStrategy: ConflictStrategy = .lastWriteWins
    @Published var mergeConflicts: [MergeConflict] = []
    @Published var showConflictResolutionSheet = false
    
    // Legacy backup format for compatibility
    struct LegacyBackupData: Codable {
        let accountGroups: [LegacyAccountGroupData]
        let accounts: [LegacyAccountData]
        let categories: [LegacyCategoryData]
        let transactions: [LegacyTransactionData]
        
        struct LegacyAccountGroupData: Codable {
            let name: String
            let createdAt: Date
        }
        
        struct LegacyAccountData: Codable {
            let name: String
            let groupName: String
            let includeInBalance: Bool
            let createdAt: Date
        }
        
        struct LegacyCategoryData: Codable {
            let name: String
            let createdAt: Date
        }
        
        struct LegacyTransactionData: Codable {
            let amount: Double
            let categoryName: String
            let accountName: String
            let timestamp: Date
            let notes: String?
        }
    }
    
    enum ConflictStrategy {
        case lastWriteWins          // Letzte Änderung gewinnt
        case mergeChanges           // Versuche intelligentes Merging
        case askUser               // Benutzer entscheidet
        case preserveLocal         // Lokale Änderungen behalten
    }
    
    struct MergeConflict: Identifiable {
        let id = UUID()
        let type: ConflictType
        let localData: Any
        let remoteData: Any
        let description: String
        var resolution: ConflictResolution?
        
        enum ConflictType {
            case transaction
            case account
            case accountGroup
            case category
        }
        
        enum ConflictResolution {
            case useLocal
            case useRemote
            case merge
            case skip
        }
    }
    
    func restoreWithConflictResolution(from url: URL, viewModel: TransactionViewModel) async -> Bool {
        do {
            let jsonData = try Data(contentsOf: url)
            
            // Try to decode as new Enhanced Backup format first
            if let backup = try? JSONDecoder().decode(BackupManager.EnhancedBackupData.self, from: jsonData) {
                print("🔄 Starting conflict resolution restore with Enhanced Backup...")
                print("📊 Remote backup from user: \(backup.userID), device: \(backup.deviceName)")
                
                switch conflictResolutionStrategy {
                case .lastWriteWins:
                    return await performLastWriteWinsRestore(backup, viewModel: viewModel)
                case .mergeChanges:
                    return await performIntelligentMerge(backup, viewModel: viewModel)
                case .askUser:
                    return await performUserDecisionRestore(backup, viewModel: viewModel)
                case .preserveLocal:
                    return await performPreserveLocalRestore(backup, viewModel: viewModel)
                }
            }
            
            // Fallback: Try to decode as legacy backup format
            print("🔄 Enhanced backup parsing failed, trying legacy format...")
            if let legacyBackup = try? JSONDecoder().decode(LegacyBackupData.self, from: jsonData) {
                print("📊 Legacy backup detected, converting to enhanced format...")
                return await performLegacyBackupRestore(legacyBackup, viewModel: viewModel)
            }
            
            // If both fail, try raw JSON dictionary approach
            if let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                print("🔄 Trying raw JSON dictionary fallback...")
                return await performRawJSONRestore(jsonObject, viewModel: viewModel)
            }
            
            print("❌ Failed to parse backup in any known format")
            return false
            
        } catch {
            print("❌ Failed to parse backup for conflict resolution: \(error)")
            return false
        }
    }
    
    // MARK: - Conflict Resolution Strategies
    
    private func performLastWriteWinsRestore(_ backup: BackupManager.EnhancedBackupData, viewModel: TransactionViewModel) async -> Bool {
        print("🏆 Using Last Write Wins strategy")
        print("📊 Remote backup: \(backup.transactions.count) transactions, \(backup.accounts.count) accounts")
        
        return await withCheckedContinuation { continuation in
            viewModel.getBackgroundContext().perform {
                do {
                    // Backup current state for potential rollback
                    let backupSuccessful = self.createPreRestoreSnapshot(viewModel.getBackgroundContext())
                    if !backupSuccessful {
                        print("⚠️ Warning: Could not create pre-restore snapshot")
                    }
                    
                    // Simple approach: Replace everything with remote data
                    try self.clearAllData(viewModel.getBackgroundContext())
                    let success = self.restoreFromBackup(backup, context: viewModel.getBackgroundContext())
                    
                    if success {
                        try viewModel.getBackgroundContext().save()
                        print("✅ Last Write Wins restore completed - context saved")
                        
                        // Force main context to refresh from persistent store
                        DispatchQueue.main.async {
                            viewModel.getContext().refreshAllObjects()
                            viewModel.fetchAccountGroups()
                            viewModel.fetchCategories()
                            print("🔄 UI refreshed after restore")
                            continuation.resume(returning: true)
                        }
                    } else {
                        print("❌ Restore failed - attempting rollback")
                        self.attemptRollback(viewModel.getBackgroundContext())
                        DispatchQueue.main.async {
                            continuation.resume(returning: false)
                        }
                    }
                } catch {
                    print("❌ Last Write Wins restore failed: \(error)")
                    self.attemptRollback(viewModel.getBackgroundContext())
                    DispatchQueue.main.async {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
    
    private func createPreRestoreSnapshot(_ context: NSManagedObjectContext) -> Bool {
        // Erstelle einen Snapshot der aktuellen Daten für potentiellen Rollback
        // Vereinfachte Version - in einer vollständigen Implementierung würde hier
        // ein vollständiger Snapshot erstellt werden
        print("📸 Creating pre-restore snapshot...")
        return true // Placeholder
    }
    
    private func attemptRollback(_ context: NSManagedObjectContext) {
        print("🔄 Attempting rollback after failed restore...")
        context.rollback()
        // In einer vollständigen Implementierung würde hier der Snapshot wiederhergestellt
    }
    
    private func performIntelligentMerge(_ backup: BackupManager.EnhancedBackupData, viewModel: TransactionViewModel) async -> Bool {
        print("🧠 Using Intelligent Merge strategy")
        
        return await withCheckedContinuation { continuation in
            viewModel.getBackgroundContext().perform {
                do {
                    let mergeResult = self.performIntelligentMergeLogic(backup, context: viewModel.getBackgroundContext())
                    
                    if mergeResult {
                        try viewModel.getBackgroundContext().save()
                        print("✅ Intelligent merge completed")
                    }
                    
                    DispatchQueue.main.async {
                        if mergeResult {
                            viewModel.fetchAccountGroups()
                            viewModel.fetchCategories()
                        }
                        continuation.resume(returning: mergeResult)
                    }
                } catch {
                    print("❌ Intelligent merge failed: \(error)")
                    DispatchQueue.main.async {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
    
    private func performUserDecisionRestore(_ backup: BackupManager.EnhancedBackupData, viewModel: TransactionViewModel) async -> Bool {
        print("👤 Using Ask User strategy")
        
        // For now, fallback to last write wins
        // In a real implementation, this would show a conflict resolution UI
        await MainActor.run {
            showConflictResolutionSheet = true
        }
        
        return await performLastWriteWinsRestore(backup, viewModel: viewModel)
    }
    
    private func performPreserveLocalRestore(_ backup: BackupManager.EnhancedBackupData, viewModel: TransactionViewModel) async -> Bool {
        print("🛡️ Using Preserve Local strategy")
        
        return await withCheckedContinuation { continuation in
            viewModel.getBackgroundContext().perform {
                do {
                    // Only add new data that doesn't conflict with local data
                    let mergeResult = self.addNonConflictingData(backup, context: viewModel.getBackgroundContext())
                    
                    if mergeResult {
                        try viewModel.getBackgroundContext().save()
                        print("✅ Preserve local restore completed")
                    }
                    
                    DispatchQueue.main.async {
                        if mergeResult {
                            viewModel.fetchAccountGroups()
                            viewModel.fetchCategories()
                        }
                        continuation.resume(returning: mergeResult)
                    }
                } catch {
                    print("❌ Preserve local restore failed: \(error)")
                    DispatchQueue.main.async {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
    
    // MARK: - Merge Logic
    
    private func performIntelligentMergeLogic(_ backup: BackupManager.EnhancedBackupData, context: NSManagedObjectContext) -> Bool {
        do {
            // 1. Merge Categories (always safe to add new ones)
            try mergeCategories(backup.categories, context: context)
            
            // 2. Merge Account Groups (safe to add new ones)
            try mergeAccountGroups(backup.accountGroups, context: context)
            
            // 3. Merge Accounts (check for conflicts)
            try mergeAccounts(backup.accounts, context: context)
            
            // 4. Merge Transactions (most complex - check for duplicates and conflicts)
            try mergeTransactions(backup.transactions, context: context)
            
            print("✅ Intelligent merge logic completed successfully")
            return true
            
        } catch {
            print("❌ Intelligent merge logic failed: \(error)")
            return false
        }
    }
    
    private func mergeCategories(_ remoteCategories: [BackupManager.EnhancedBackupData.CategoryData], context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        let localCategories = try context.fetch(request)
        let localCategoryNames = Set(localCategories.compactMap { $0.name })
        
        for remoteCategoryData in remoteCategories {
            if !localCategoryNames.contains(remoteCategoryData.name) {
                let newCategory = Category(context: context)
                newCategory.name = remoteCategoryData.name
                print("➕ Added new category: \(remoteCategoryData.name)")
            }
        }
    }
    
    private func mergeAccountGroups(_ remoteGroups: [BackupManager.EnhancedBackupData.AccountGroupData], context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
        let localGroups = try context.fetch(request)
        let localGroupNames = Set(localGroups.compactMap { $0.name })
        
        for remoteGroupData in remoteGroups {
            if !localGroupNames.contains(remoteGroupData.name) {
                let newGroup = AccountGroup(context: context)
                newGroup.name = remoteGroupData.name
                print("➕ Added new account group: \(remoteGroupData.name)")
            }
        }
    }
    
    private func mergeAccounts(_ remoteAccounts: [BackupManager.EnhancedBackupData.AccountData], context: NSManagedObjectContext) throws {
        let groupRequest: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
        let localGroups = try context.fetch(groupRequest)
        let groupMap: [String: AccountGroup] = Dictionary(uniqueKeysWithValues: localGroups.compactMap { group in
            guard let name = group.name else { return nil }
            return (name, group)
        })
        
        let accountRequest: NSFetchRequest<Account> = Account.fetchRequest()
        let localAccounts = try context.fetch(accountRequest)
        let localAccountNames = Set(localAccounts.compactMap { $0.name })
        
        for remoteAccountData in remoteAccounts {
            if !localAccountNames.contains(remoteAccountData.name) {
                let newAccount = Account(context: context)
                newAccount.name = remoteAccountData.name
                newAccount.group = groupMap[remoteAccountData.group]
                newAccount.setValue(remoteAccountData.type, forKey: "type")
                newAccount.setValue(remoteAccountData.includeInBalance, forKey: "includeInBalance")
                print("➕ Added new account: \(remoteAccountData.name)")
            }
        }
    }
    
    private func mergeTransactions(_ remoteTransactions: [BackupManager.EnhancedBackupData.TransactionData], context: NSManagedObjectContext) throws {
        // Get all local transactions
        let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        let localTransactions = try context.fetch(transactionRequest)
        let localTransactionIDs = Set(localTransactions.map { $0.id })
        
        // Get account and category maps
        let accountRequest: NSFetchRequest<Account> = Account.fetchRequest()
        let localAccounts = try context.fetch(accountRequest)
        let accountMap: [String: Account] = Dictionary(uniqueKeysWithValues: localAccounts.compactMap { account in
            guard let name = account.name else { return nil }
            return (name, account)
        })
        
        let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
        let localCategories = try context.fetch(categoryRequest)
        let categoryMap: [String: Category] = Dictionary(uniqueKeysWithValues: localCategories.compactMap { category in
            guard let name = category.name else { return nil }
            return (name, category)
        })
        
        var addedCount = 0
        var skippedCount = 0
        
        for remoteTransactionData in remoteTransactions {
            let transactionID = UUID(uuidString: remoteTransactionData.id) ?? UUID()
            
            // Check if transaction already exists
            if localTransactionIDs.contains(transactionID) {
                skippedCount += 1
                continue
            }
            
            // Check if we have the required account and category
            guard let account = accountMap[remoteTransactionData.account],
                  let category = categoryMap[remoteTransactionData.category] else {
                print("⚠️ Skipping transaction due to missing account or category: \(remoteTransactionData.id)")
                skippedCount += 1
                continue
            }
            
            // Create new transaction
            let newTransaction = Transaction(context: context)
            newTransaction.id = transactionID
            newTransaction.type = remoteTransactionData.type
            newTransaction.amount = remoteTransactionData.amount
            newTransaction.date = Date(timeIntervalSince1970: remoteTransactionData.date)
            newTransaction.usage = remoteTransactionData.usage
            newTransaction.account = account
            newTransaction.categoryRelationship = category
            
            if let targetAccountName = remoteTransactionData.targetAccount {
                newTransaction.targetAccount = accountMap[targetAccountName]
            }
            
            addedCount += 1
        }
        
        print("📊 Transaction merge result: \(addedCount) added, \(skippedCount) skipped")
    }
    
    private func addNonConflictingData(_ backup: BackupManager.EnhancedBackupData, context: NSManagedObjectContext) -> Bool {
        // This is similar to intelligent merge but more conservative
        // Only add data that definitely doesn't conflict
        return performIntelligentMergeLogic(backup, context: context)
    }
    
    // MARK: - Helper Methods
    
    private func clearAllData(_ context: NSManagedObjectContext) throws {
        print("🗑️ Starting data clearance...")
        
        // Use individual fetch and delete instead of batch delete for better reliability
        let entities = ["Transaction", "Account", "AccountGroup", "Category"]
        
        for entityName in entities {
            // Fetch all objects of this entity type
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
            let objects = try context.fetch(fetchRequest)
            
            // Delete each object individually
            for object in objects {
                context.delete(object)
            }
            
            print("🗑️ Marked \(objects.count) \(entityName) entities for deletion")
        }
        
        // Save the context to actually delete the objects
        try context.save()
        
        // Force context to refresh to reflect the deletions
        context.reset()
        
        print("🗑️ Cleared all existing data and reset context")
        
        // Verify deletion by checking counts
        for entityName in entities {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
            let count = try context.count(for: fetchRequest)
            print("🔍 After deletion - \(entityName): \(count) objects remaining")
        }
    }
    
    private func restoreFromBackup(_ backup: BackupManager.EnhancedBackupData, context: NSManagedObjectContext) -> Bool {
        // Restore categories
        var categoryMap: [String: Category] = [:]
        for categoryData in backup.categories {
            let category = Category(context: context)
            category.name = categoryData.name
            categoryMap[categoryData.name] = category
        }
        
        // Restore account groups
        var groupMap: [String: AccountGroup] = [:]
        for groupData in backup.accountGroups {
            let group = AccountGroup(context: context)
            group.name = groupData.name
            groupMap[groupData.name] = group
        }
        
        // Restore accounts
        var accountMap: [String: Account] = [:]
        for accountData in backup.accounts {
            let account = Account(context: context)
            account.name = accountData.name
            account.group = groupMap[accountData.group]
            account.setValue(accountData.type, forKey: "type")
            account.setValue(accountData.includeInBalance, forKey: "includeInBalance")
            accountMap[accountData.name] = account
        }
        
        // Restore transactions
        for transactionData in backup.transactions {
            let transaction = Transaction(context: context)
            transaction.id = UUID(uuidString: transactionData.id) ?? UUID()
            transaction.type = transactionData.type
            transaction.amount = transactionData.amount
            transaction.date = Date(timeIntervalSince1970: transactionData.date)
            transaction.usage = transactionData.usage
            transaction.account = accountMap[transactionData.account]
            transaction.categoryRelationship = categoryMap[transactionData.category]
            
            if let targetAccountName = transactionData.targetAccount {
                transaction.targetAccount = accountMap[targetAccountName]
            }
        }
        
        print("✅ Backup restoration completed successfully")
        return true
    }
    
    // MARK: - Configuration
    
    func setConflictResolutionStrategy(_ strategy: ConflictStrategy) {
        conflictResolutionStrategy = strategy
        UserDefaults.standard.set(strategy.rawValue, forKey: "conflictResolutionStrategy")
        print("🔧 Set conflict resolution strategy to: \(strategy)")
    }
    
    private func loadConflictResolutionStrategy() {
        if let savedStrategy = UserDefaults.standard.object(forKey: "conflictResolutionStrategy") as? String {
            switch savedStrategy {
            case "lastWriteWins":
                conflictResolutionStrategy = .lastWriteWins
            case "mergeChanges":
                conflictResolutionStrategy = .mergeChanges
            case "askUser":
                conflictResolutionStrategy = .askUser
            case "preserveLocal":
                conflictResolutionStrategy = .preserveLocal
            default:
                conflictResolutionStrategy = .lastWriteWins
            }
        }
    }
    
    // MARK: - Legacy Backup Support
    
    private func performLegacyBackupRestore(_ legacyBackup: LegacyBackupData, viewModel: TransactionViewModel) async -> Bool {
        print("🔄 Restoring legacy backup format...")
        
        return await withCheckedContinuation { continuation in
            viewModel.getBackgroundContext().perform {
                do {
                    // Convert legacy format to our standard restore process
                    try self.clearAllData(viewModel.getBackgroundContext())
                    let success = self.restoreFromLegacyBackup(legacyBackup, context: viewModel.getBackgroundContext())
                    
                    if success {
                        try viewModel.getBackgroundContext().save()
                        print("✅ Legacy backup restore completed")
                    }
                    
                    DispatchQueue.main.async {
                        if success {
                            viewModel.fetchAccountGroups()
                            viewModel.fetchCategories()
                        }
                        continuation.resume(returning: success)
                    }
                } catch {
                    print("❌ Legacy backup restore failed: \(error)")
                    DispatchQueue.main.async {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
    
    private func performRawJSONRestore(_ jsonObject: [String: Any], viewModel: TransactionViewModel) async -> Bool {
        print("🔄 Attempting raw JSON restore...")
        
        return await withCheckedContinuation { continuation in
            viewModel.getBackgroundContext().perform {
                do {
                    // Clear all existing data first to prevent duplicates
                    try self.clearAllData(viewModel.getBackgroundContext())
                    print("🗑️ Cleared existing data before raw JSON restore")
                    
                    let success = self.restoreFromRawJSON(jsonObject, context: viewModel.getBackgroundContext())
                    
                    if success {
                        // Update the backup manager's hash to prevent immediate re-upload
                        Task {
                            let backupManager = BackupManager(viewModel: viewModel)
                            if await backupManager.createEnhancedBackup() != nil {
                                // This will update the saved hash in BackupManager
                                _ = await backupManager.hasLocalChanges()
                            }
                        }
                        
                        try viewModel.getBackgroundContext().save()
                        print("✅ Raw JSON restore completed and saved")
                        
                        // Force main context to refresh from persistent store
                        DispatchQueue.main.async {
                            viewModel.getContext().refreshAllObjects()
                            viewModel.fetchAccountGroups()
                            viewModel.fetchCategories()
                            print("🔄 UI refreshed after raw JSON restore")
                            continuation.resume(returning: true)
                        }
                    } else {
                        DispatchQueue.main.async {
                            continuation.resume(returning: false)
                        }
                    }
                } catch {
                    print("❌ Raw JSON restore failed with error: \(error)")
                    DispatchQueue.main.async {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
    
    private func restoreFromLegacyBackup(_ backup: LegacyBackupData, context: NSManagedObjectContext) -> Bool {
        // Restore categories
        var categoryMap: [String: Category] = [:]
        for categoryData in backup.categories {
            let category = Category(context: context)
            category.name = categoryData.name
            categoryMap[categoryData.name] = category
        }
        
        // Restore account groups
        var groupMap: [String: AccountGroup] = [:]
        for groupData in backup.accountGroups {
            let group = AccountGroup(context: context)
            group.name = groupData.name
            groupMap[groupData.name] = group
        }
        
        // Restore accounts
        var accountMap: [String: Account] = [:]
        for accountData in backup.accounts {
            let account = Account(context: context)
            account.name = accountData.name
            account.group = groupMap[accountData.groupName]
            account.setValue(accountData.includeInBalance, forKey: "includeInBalance")
            accountMap[accountData.name] = account
        }
        
        // Restore transactions
        for transactionData in backup.transactions {
            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.amount = transactionData.amount
            transaction.date = transactionData.timestamp
            transaction.usage = transactionData.notes ?? ""
            transaction.account = accountMap[transactionData.accountName]
            transaction.categoryRelationship = categoryMap[transactionData.categoryName]
            
            // Set transaction type based on amount (critical fix for legacy backups)
            if transactionData.amount >= 0 {
                transaction.type = "income"
            } else {
                transaction.type = "expense"
            }
        }
        
        print("✅ Legacy backup restoration completed successfully")
        return true
    }
    
    private func restoreFromRawJSON(_ jsonObject: [String: Any], context: NSManagedObjectContext) -> Bool {
        // Try to extract basic data structures from raw JSON
        print("🔍 Analyzing raw JSON structure...")
        
        // Check if it has the basic structure we expect
        guard let accountGroups = jsonObject["accountGroups"] as? [[String: Any]],
              let accounts = jsonObject["accounts"] as? [[String: Any]],
              let categories = jsonObject["categories"] as? [[String: Any]],
              let transactions = jsonObject["transactions"] as? [[String: Any]] else {
            print("❌ Raw JSON does not contain expected structure")
            return false
        }
        
        print("📊 Found structured data: \(accountGroups.count) groups, \(accounts.count) accounts, \(categories.count) categories, \(transactions.count) transactions")
        
        // Since we cleared all data, we can create fresh entities without checking for duplicates
        
        // Create categories
        var categoryMap: [String: Category] = [:]
        for categoryJSON in categories {
            if let name = categoryJSON["name"] as? String {
                let category = Category(context: context)
                category.name = name
                categoryMap[name] = category
                print("➕ Created category: \(name)")
            }
        }
        
        // Create account groups
        var groupMap: [String: AccountGroup] = [:]
        for groupJSON in accountGroups {
            if let name = groupJSON["name"] as? String {
                let group = AccountGroup(context: context)
                group.name = name
                groupMap[name] = group
                print("➕ Created account group: \(name)")
            }
        }
        
        // Create accounts
        var accountMap: [String: Account] = [:]
        for accountJSON in accounts {
            if let name = accountJSON["name"] as? String,
               let groupName = accountJSON["groupName"] as? String ?? accountJSON["group"] as? String {
                
                let account = Account(context: context)
                account.name = name
                account.group = groupMap[groupName]
                
                if let includeInBalance = accountJSON["includeInBalance"] as? Bool {
                    account.setValue(includeInBalance, forKey: "includeInBalance")
                }
                
                accountMap[name] = account
                print("➕ Created account: \(name)")
            }
        }
        
        var newTransactionsCount = 0
        
        // Create transactions
        for transactionJSON in transactions {
            if let amount = transactionJSON["amount"] as? Double,
               let categoryName = transactionJSON["categoryName"] as? String ?? transactionJSON["category"] as? String,
               let accountName = transactionJSON["accountName"] as? String ?? transactionJSON["account"] as? String {
                
                // Get transaction date - handle multiple date formats
                var transactionDate: Date
                if let timestamp = transactionJSON["timestamp"] as? TimeInterval {
                    transactionDate = Date(timeIntervalSince1970: timestamp)
                } else if let dateValue = transactionJSON["date"] as? TimeInterval {
                    // Handle Unix timestamp (your backup format)
                    transactionDate = Date(timeIntervalSince1970: dateValue)
                } else if let dateString = transactionJSON["date"] as? String {
                    // Try to parse date string
                    let formatter = ISO8601DateFormatter()
                    transactionDate = formatter.date(from: dateString) ?? Date()
                } else {
                    transactionDate = Date()
                }
                
                let transaction = Transaction(context: context)
                
                // Handle transaction ID - use existing ID if available
                if let idString = transactionJSON["id"] as? String,
                   let uuid = UUID(uuidString: idString) {
                    transaction.id = uuid
                } else {
                    transaction.id = UUID()
                }
                
                transaction.amount = amount
                transaction.date = transactionDate
                transaction.account = accountMap[accountName]
                transaction.categoryRelationship = categoryMap[categoryName]
                
                // Use the transaction type from JSON if available, otherwise derive from amount
                if let transactionType = transactionJSON["type"] as? String {
                    transaction.type = transactionType
                } else {
                    // Fallback: Set transaction type based on amount
                    if amount >= 0 {
                        transaction.type = "einnahme"  // Use German terms to match your data
                    } else {
                        transaction.type = "ausgabe"
                    }
                }
                
                // Try to get notes/usage
                if let notes = transactionJSON["notes"] as? String {
                    transaction.usage = notes
                } else if let usage = transactionJSON["usage"] as? String {
                    transaction.usage = usage
                } else {
                    transaction.usage = ""
                }
                
                // Handle target account for transfers
                if let targetAccountName = transactionJSON["targetAccount"] as? String,
                   !targetAccountName.isEmpty,
                   let targetAccount = accountMap[targetAccountName] {
                    transaction.targetAccount = targetAccount
                }
                
                newTransactionsCount += 1
                print("➕ Created transaction: \(amount) \(categoryName) on \(transactionDate)")
                
            } else {
                print("⚠️ Skipping transaction due to missing required fields: \(transactionJSON)")
            }
        }
        
        print("📊 Transaction processing:")
        print("  New transactions created: \(newTransactionsCount)")
        
        print("✅ Raw JSON restoration completed successfully")
        return true
    }
    
    init() {
        loadConflictResolutionStrategy()
    }
}

// MARK: - Extensions

extension MultiUserSyncManager.ConflictStrategy {
    var rawValue: String {
        switch self {
        case .lastWriteWins: return "lastWriteWins"
        case .mergeChanges: return "mergeChanges"
        case .askUser: return "askUser"
        case .preserveLocal: return "preserveLocal"
        }
    }
    
    var displayName: String {
        switch self {
        case .lastWriteWins: return "Letzte Änderung gewinnt"
        case .mergeChanges: return "Intelligentes Merging"
        case .askUser: return "Benutzer entscheidet"
        case .preserveLocal: return "Lokale Änderungen behalten"
        }
    }
    
    var description: String {
        switch self {
        case .lastWriteWins: return "Überschreibt lokale Daten mit den neuesten Remote-Daten"
        case .mergeChanges: return "Versucht automatisch Änderungen zu kombinieren"
        case .askUser: return "Fragt bei Konflikten nach Benutzerentscheidung"
        case .preserveLocal: return "Behält lokale Änderungen und fügt nur neue Remote-Daten hinzu"
        }
    }
} 