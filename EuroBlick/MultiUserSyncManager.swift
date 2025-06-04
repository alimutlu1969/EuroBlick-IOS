import Foundation
import CoreData
import SwiftUI

class MultiUserSyncManager: ObservableObject {
    @Published var conflictResolutionStrategy: ConflictStrategy = .lastWriteWins
    @Published var mergeConflicts: [MergeConflict] = []
    @Published var showConflictResolutionSheet = false
    
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
            let backup = try JSONDecoder().decode(BackupManager.EnhancedBackupData.self, from: jsonData)
            
            print("🔄 Starting conflict resolution restore...")
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
            
        } catch {
            print("❌ Failed to parse backup for conflict resolution: \(error)")
            return false
        }
    }
    
    // MARK: - Conflict Resolution Strategies
    
    private func performLastWriteWinsRestore(_ backup: BackupManager.EnhancedBackupData, viewModel: TransactionViewModel) async -> Bool {
        print("🏆 Using Last Write Wins strategy")
        
        return await withCheckedContinuation { continuation in
            viewModel.getBackgroundContext().perform {
                do {
                    // Simple approach: Replace everything with remote data
                    try self.clearAllData(viewModel.getBackgroundContext())
                    let success = self.restoreFromBackup(backup, context: viewModel.getBackgroundContext())
                    
                    if success {
                        try viewModel.getBackgroundContext().save()
                        print("✅ Last Write Wins restore completed")
                    }
                    
                    DispatchQueue.main.async {
                        if success {
                            viewModel.fetchAccountGroups()
                            viewModel.fetchCategories()
                        }
                        continuation.resume(returning: success)
                    }
                } catch {
                    print("❌ Last Write Wins restore failed: \(error)")
                    DispatchQueue.main.async {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
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
        let groupMap = Dictionary(uniqueKeysWithValues: localGroups.compactMap { group in
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
        let accountMap = Dictionary(uniqueKeysWithValues: localAccounts.compactMap { account in
            guard let name = account.name else { return nil }
            return (name, account)
        })
        
        let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
        let localCategories = try context.fetch(categoryRequest)
        let categoryMap = Dictionary(uniqueKeysWithValues: localCategories.compactMap { category in
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
        let entities = ["Transaction", "Account", "AccountGroup", "Category"]
        
        for entityName in entities {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: entityName)
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDeleteRequest.resultType = .resultTypeCount
            
            try context.execute(batchDeleteRequest)
        }
        
        print("🗑️ Cleared all existing data")
    }
    
    private func restoreFromBackup(_ backup: BackupManager.EnhancedBackupData, context: NSManagedObjectContext) -> Bool {
        do {
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
            
            return true
            
        } catch {
            print("❌ Failed to restore from backup: \(error)")
            return false
        }
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