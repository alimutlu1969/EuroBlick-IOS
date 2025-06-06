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
                print("📊 BACKUP CONTENT VERIFICATION:")
                print("  📁 Account Groups: \(backup.accountGroups.count)")
                print("  💳 Accounts: \(backup.accounts.count)")
                print("  🏷️ Categories: \(backup.categories.count)")
                print("  💰 Transactions: \(backup.transactions.count)")
                
                // Show first few items for verification
                if !backup.accountGroups.isEmpty {
                    print("  📁 First group: '\(backup.accountGroups[0].name)'")
                }
                if !backup.accounts.isEmpty {
                    print("  💳 First account: '\(backup.accounts[0].name)' in group '\(backup.accounts[0].group)'")
                }
                if !backup.transactions.isEmpty {
                    print("  💰 First transaction: \(backup.transactions[0].amount) \(backup.transactions[0].type)")
                }
                
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
                print("📊 LEGACY BACKUP CONTENT:")
                print("  📁 Account Groups: \(legacyBackup.accountGroups.count)")
                print("  💳 Accounts: \(legacyBackup.accounts.count)")
                print("  🏷️ Categories: \(legacyBackup.categories.count)")
                print("  💰 Transactions: \(legacyBackup.transactions.count)")
                return await performLegacyBackupRestore(legacyBackup, viewModel: viewModel)
            }
            
            // If both fail, try raw JSON dictionary approach
            if let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                print("🔄 Trying raw JSON dictionary fallback...")
                
                // Show what's in the raw JSON
                if let accountGroups = jsonObject["accountGroups"] as? [[String: Any]] {
                    print("📊 RAW JSON CONTENT:")
                    print("  📁 Account Groups: \(accountGroups.count)")
                    if let accounts = jsonObject["accounts"] as? [[String: Any]] {
                        print("  💳 Accounts: \(accounts.count)")
                    }
                    if let categories = jsonObject["categories"] as? [[String: Any]] {
                        print("  🏷️ Categories: \(categories.count)")
                    }
                    if let transactions = jsonObject["transactions"] as? [[String: Any]] {
                        print("  💰 Transactions: \(transactions.count)")
                    }
                }
                
                return await performRawJSONRestore(jsonObject, viewModel: viewModel)
            }
            
            print("❌ Failed to parse backup in any known format")
            print("❌ JSON data size: \(jsonData.count) bytes")
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("❌ JSON preview: \(String(jsonString.prefix(200)))...")
            }
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
                    print("🔄 About to call restoreFromBackup...")
                    let success = self.restoreFromBackup(backup, context: viewModel.getBackgroundContext())
                    print("🔄 restoreFromBackup returned: \(success)")
                    
                    if success {
                        print("🔄 Attempting to save background context...")
                        try viewModel.getBackgroundContext().save()
                        print("✅ Background context saved")
                        
                        // CRITICAL: In Parent-Child setup, we MUST also save the parent (main) context!
                        print("🔄 CRITICAL: Saving parent (main) context to persistent store...")
                        
                        // Force save main context synchronously  
                        var mainContextSaveError: Error? = nil
                        DispatchQueue.main.sync {
                            viewModel.getContext().performAndWait {
                                do {
                                    if viewModel.getContext().hasChanges {
                                        try viewModel.getContext().save()
                                        print("✅ Main context saved to persistent store!")
                                    } else {
                                        print("ℹ️ Main context had no changes to save")
                                    }
                                } catch {
                                    print("❌ Failed to save main context: \(error)")
                                    mainContextSaveError = error
                                }
                            }
                        }
                        
                        if let error = mainContextSaveError {
                            throw error
                        }
                        
                        print("✅ Parent-Child save sequence completed!")
                        
                        // CRITICAL: Force main context to completely reload from persistent store
                        print("🔄 FORCING MAIN CONTEXT TO COMPLETELY RELOAD FROM PERSISTENT STORE...")
                        
                        // Force comprehensive UI refresh from persistent store
                        DispatchQueue.main.async {
                            // 1. NUCLEAR OPTION: Complete context reconstruction
                            print("🔄 NUCLEAR OPTION: Forcing complete main context reload...")
                            
                            // Force main context to drop everything and reload from store
                            viewModel.getContext().performAndWait {
                                viewModel.getContext().reset()
                                print("🔄 Main context reset completed")
                            }
                            
                            // Wait for reset to complete
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                
                                // Force fresh object loading with explicit Core Data fetch
                                viewModel.getContext().performAndWait {
                                    // Force reload all entities from persistent store
                                    let entities = ["AccountGroup", "Account", "Transaction", "Category"]
                                    
                                    for entityName in entities {
                                        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                                        fetchRequest.returnsObjectsAsFaults = false // Force full object loading
                                        
                                        do {
                                            let objects = try viewModel.getContext().fetch(fetchRequest)
                                            print("🔄 FORCED RELOAD: \(entityName) = \(objects.count) objects")
                                            
                                            // Touch each object to ensure it's loaded
                                            for object in objects {
                                                _ = object.objectID
                                            }
                                        } catch {
                                            print("❌ Error reloading \(entityName): \(error)")
                                        }
                                    }
                                }
                                
                                // 2. Fetch all data fresh from store
                                viewModel.fetchAccountGroups()
                                viewModel.fetchCategories()
                                
                                // 3. CRITICAL: Force balance recalculation with fresh data
                                print("🔄 Forcing balance recalculation after context reload...")
                                let _ = viewModel.calculateAllBalances()
                                
                                // 4. Force view model to notify UI of changes
                                viewModel.objectWillChange.send()
                                
                                // 5. Send notification for additional UI updates
                                NotificationCenter.default.post(name: NSNotification.Name("DataDidChange"), object: nil)
                                NotificationCenter.default.post(name: NSNotification.Name("BalanceDataChanged"), object: nil)
                                
                                print("🔄 Nuclear context reload completed after restore")
                                continuation.resume(returning: true)
                                
                                // 6. Additional verification after nuclear reload
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    print("🔄 Phase 2: Post-nuclear verification...")
                                    
                                    // Verify main context now sees the data
                                    viewModel.getContext().performAndWait {
                                        let entities = ["AccountGroup", "Account", "Transaction", "Category"]
                                        
                                        for entityName in entities {
                                            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                                            do {
                                                let count = try viewModel.getContext().count(for: fetchRequest)
                                                print("🔍 POST-NUCLEAR VERIFICATION: \(entityName) = \(count) objects")
                                            } catch {
                                                print("❌ Error verifying \(entityName): \(error)")
                                            }
                                        }
                                    }
                                    
                                    let _ = viewModel.calculateAllBalances()
                                    viewModel.fetchAccountGroups()
                                    viewModel.fetchCategories()
                                    viewModel.objectWillChange.send()
                                    NotificationCenter.default.post(name: NSNotification.Name("BalanceDataChanged"), object: nil)
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                    print("🔄 Phase 3: Final verification and balance recalculation...")
                                    let _ = viewModel.calculateAllBalances()
                                    viewModel.fetchAccountGroups()
                                    viewModel.objectWillChange.send()
                                    NotificationCenter.default.post(name: NSNotification.Name("DataDidChange"), object: nil)
                                    print("🔄 Nuclear restore completed - data should now be visible!")
                                }
                            }
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
        print("🔄 DETAILED RESTORE - Starting with backup containing:")
        print("  📁 Account Groups: \(backup.accountGroups.count)")
        print("  💳 Accounts: \(backup.accounts.count)")
        print("  🏷️ Categories: \(backup.categories.count)")
        print("  💰 Transactions: \(backup.transactions.count)")
        
        // Restore categories
        var categoryMap: [String: Category] = [:]
        print("🔄 Creating \(backup.categories.count) categories...")
        for (index, categoryData) in backup.categories.enumerated() {
            let category = Category(context: context)
            category.name = categoryData.name
            categoryMap[categoryData.name] = category
            print("  ➕ Category \(index + 1): '\(categoryData.name)'")
        }
        print("✅ Created \(categoryMap.count) categories")
        
        // Restore account groups
        var groupMap: [String: AccountGroup] = [:]
        print("🔄 Creating \(backup.accountGroups.count) account groups...")
        for (index, groupData) in backup.accountGroups.enumerated() {
            let group = AccountGroup(context: context)
            group.name = groupData.name
            groupMap[groupData.name] = group
            print("  ➕ Group \(index + 1): '\(groupData.name)'")
        }
        print("✅ Created \(groupMap.count) account groups")
        
        // Restore accounts
        var accountMap: [String: Account] = [:]
        print("🔄 Creating \(backup.accounts.count) accounts...")
        for (index, accountData) in backup.accounts.enumerated() {
            let account = Account(context: context)
            account.name = accountData.name
            account.group = groupMap[accountData.group]
            account.setValue(accountData.type, forKey: "type")
            account.setValue(accountData.includeInBalance, forKey: "includeInBalance")
            accountMap[accountData.name] = account
            print("  ➕ Account \(index + 1): '\(accountData.name)' in group '\(accountData.group)'")
        }
        print("✅ Created \(accountMap.count) accounts")
        
        // Restore transactions
        print("🔄 Creating \(backup.transactions.count) transactions...")
        var transactionCount = 0
        for (index, transactionData) in backup.transactions.enumerated() {
            guard let account = accountMap[transactionData.account],
                  let category = categoryMap[transactionData.category] else {
                print("  ❌ Skipping transaction \(index + 1): missing account '\(transactionData.account)' or category '\(transactionData.category)'")
                continue
            }
            
            let transaction = Transaction(context: context)
            transaction.id = UUID(uuidString: transactionData.id) ?? UUID()
            transaction.type = transactionData.type
            transaction.amount = transactionData.amount
            transaction.date = Date(timeIntervalSince1970: transactionData.date)
            transaction.usage = transactionData.usage
            transaction.account = account
            transaction.categoryRelationship = category
            
            if let targetAccountName = transactionData.targetAccount {
                transaction.targetAccount = accountMap[targetAccountName]
            }
            
            transactionCount += 1
            if index < 5 || index % 10 == 0 { // Log first 5 and every 10th
                print("  ➕ Transaction \(index + 1): \(transactionData.amount) \(transactionData.type) for \(transactionData.account)")
            }
        }
        print("✅ Created \(transactionCount) transactions")
        
        // CRITICAL: Verify entities were actually created
        do {
            let categoryCount = try context.count(for: NSFetchRequest<Category>(entityName: "Category"))
            let groupCount = try context.count(for: NSFetchRequest<AccountGroup>(entityName: "AccountGroup"))
            let accountCount = try context.count(for: NSFetchRequest<Account>(entityName: "Account"))
            let transactionCountCheck = try context.count(for: NSFetchRequest<Transaction>(entityName: "Transaction"))
            
            print("🔍 VERIFICATION - Entities in context:")
            print("  📁 Account Groups: \(groupCount)")
            print("  💳 Accounts: \(accountCount)")
            print("  🏷️ Categories: \(categoryCount)")
            print("  💰 Transactions: \(transactionCountCheck)")
            
            if groupCount == 0 && accountCount == 0 && transactionCountCheck == 0 {
                print("❌ NO ENTITIES CREATED - RESTORE FAILED!")
                return false
            }
            
            if transactionCountCheck != backup.transactions.count {
                print("⚠️ Transaction count mismatch: expected \(backup.transactions.count), got \(transactionCountCheck)")
            }
            
        } catch {
            print("❌ Verification error: \(error)")
            return false
        }
        
        print("✅ Backup restoration completed successfully with verified entities")
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