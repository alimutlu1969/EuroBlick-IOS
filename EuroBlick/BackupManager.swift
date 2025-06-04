import Foundation
import CoreData
import SwiftUI

class BackupManager: ObservableObject {
    private let viewModel: TransactionViewModel
    private var lastBackupHash: String?
    
    struct EnhancedBackupData: Codable {
        let version: String
        let timestamp: Date
        let userID: String
        let deviceID: String
        let deviceName: String
        let appVersion: String
        let dataHash: String
        let accountGroups: [AccountGroupData]
        let accounts: [AccountData]
        let transactions: [TransactionData]
        let categories: [CategoryData]
        
        struct AccountGroupData: Codable {
            let name: String
            let accounts: [String]
        }
        
        struct AccountData: Codable {
            let name: String
            let group: String
            let type: String?
            let includeInBalance: Bool
            let transactions: [String] // UUIDs
        }
        
        struct TransactionData: Codable {
            let id: String
            let type: String
            let amount: Double
            let date: TimeInterval
            let category: String
            let account: String
            let targetAccount: String?
            let usage: String
            let userID: String?
            let lastModified: TimeInterval
        }
        
        struct CategoryData: Codable {
            let name: String
        }
    }
    
    init(viewModel: TransactionViewModel) {
        self.viewModel = viewModel
        loadLastBackupHash()
    }
    
    // MARK: - Public Methods
    
    func createEnhancedBackup() async -> EnhancedBackupData? {
        return await withCheckedContinuation { continuation in
            viewModel.getContext().perform {
                let backup = self.createBackupData()
                continuation.resume(returning: backup)
            }
        }
    }
    
    func hasLocalChanges() async -> Bool {
        guard let backup = await createEnhancedBackup() else { return false }
        
        let currentHash = calculateDataHash(backup)
        return currentHash != lastBackupHash
    }
    
    func uploadBackup(_ backup: EnhancedBackupData) async throws {
        // Create filename with enhanced naming convention
        let filename = createBackupFilename(backup)
        
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") else {
            throw BackupError.missingCredentials
        }
        
        // Convert backup to JSON
        let jsonData = try JSONEncoder().encode(backup)
        
        // Create upload URL
        let baseURL = webdavURL.replacingOccurrences(of: "/EuroBlickBackup", with: "")
        guard let uploadURL = URL(string: "\(baseURL)/\(filename)") else {
            throw BackupError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        
        let authString = "\(webdavUser):\(webdavPassword)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Upload
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw BackupError.uploadFailed
        }
        
        // Update last backup hash
        lastBackupHash = backup.dataHash
        saveLastBackupHash()
        
        print("✅ Enhanced backup uploaded successfully: \(filename)")
    }
    
    func restoreFromEnhancedBackup(_ backup: EnhancedBackupData) async -> Bool {
        return await withCheckedContinuation { continuation in
            viewModel.getBackgroundContext().perform {
                let success = self.performRestore(backup)
                DispatchQueue.main.async {
                    if success {
                        self.viewModel.fetchAccountGroups()
                        self.viewModel.fetchCategories()
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func createBackupData() -> EnhancedBackupData? {
        let context = viewModel.getContext()
        
        // Fetch all data
        let groupsRequest: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
        let accountsRequest: NSFetchRequest<Account> = Account.fetchRequest()
        let transactionsRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        let categoriesRequest: NSFetchRequest<Category> = Category.fetchRequest()
        
        guard let groups = try? context.fetch(groupsRequest),
              let accounts = try? context.fetch(accountsRequest),
              let transactions = try? context.fetch(transactionsRequest),
              let categories = try? context.fetch(categoriesRequest) else {
            print("❌ Failed to fetch data for backup")
            return nil
        }
        
        // Convert to backup format
        let groupsData = groups.map { group in
            EnhancedBackupData.AccountGroupData(
                name: group.name ?? "",
                accounts: (group.accounts?.allObjects as? [Account])?.compactMap { $0.name } ?? []
            )
        }
        
        let accountsData = accounts.map { account in
            EnhancedBackupData.AccountData(
                name: account.name ?? "",
                group: account.group?.name ?? "",
                type: account.value(forKey: "type") as? String,
                includeInBalance: account.value(forKey: "includeInBalance") as? Bool ?? true,
                transactions: (account.transactions?.allObjects as? [Transaction])?.map { $0.id.uuidString } ?? []
            )
        }
        
        let transactionsData = transactions.map { transaction in
            EnhancedBackupData.TransactionData(
                id: transaction.id.uuidString,
                type: transaction.type ?? "",
                amount: transaction.amount,
                date: transaction.date.timeIntervalSince1970,
                category: transaction.categoryRelationship?.name ?? "",
                account: transaction.account?.name ?? "",
                targetAccount: transaction.targetAccount?.name,
                usage: transaction.usage ?? "",
                userID: getCurrentUserID(),
                lastModified: Date().timeIntervalSince1970
            )
        }
        
        let categoriesData = categories.map { category in
            EnhancedBackupData.CategoryData(name: category.name ?? "")
        }
        
        let backup = EnhancedBackupData(
            version: "2.0",
            timestamp: Date(),
            userID: getCurrentUserID(),
            deviceID: getCurrentDeviceID(),
            deviceName: UIDevice.current.name,
            appVersion: getAppVersion(),
            dataHash: "",
            accountGroups: groupsData,
            accounts: accountsData,
            transactions: transactionsData,
            categories: categoriesData
        )
        
        // Calculate hash after creating the backup
        let hash = calculateDataHash(backup)
        return EnhancedBackupData(
            version: backup.version,
            timestamp: backup.timestamp,
            userID: backup.userID,
            deviceID: backup.deviceID,
            deviceName: backup.deviceName,
            appVersion: backup.appVersion,
            dataHash: hash,
            accountGroups: backup.accountGroups,
            accounts: backup.accounts,
            transactions: backup.transactions,
            categories: backup.categories
        )
    }
    
    private func createBackupFilename(_ backup: EnhancedBackupData) -> String {
        let timestamp = Int(backup.timestamp.timeIntervalSince1970)
        let userID = backup.userID
        let deviceID = backup.deviceID
        
        return "EuroBlickBackup_user\(userID)_device\(deviceID)_\(timestamp).json"
    }
    
    private func calculateDataHash(_ backup: EnhancedBackupData) -> String {
        // Create a hash from the core data (excluding metadata like timestamp, userID, etc.)
        let coreData = [
            backup.accountGroups.description,
            backup.accounts.description,
            backup.transactions.description,
            backup.categories.description
        ].joined()
        
        return String(coreData.hashValue)
    }
    
    private func performRestore(_ backup: EnhancedBackupData) -> Bool {
        let context = viewModel.getBackgroundContext()
        
        do {
            // Clear existing data
            try clearExistingData(context)
            
            // Restore categories first
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
            
            // Save context
            try context.save()
            
            // Update hash
            lastBackupHash = backup.dataHash
            saveLastBackupHash()
            
            print("✅ Enhanced backup restored successfully")
            return true
            
        } catch {
            print("❌ Failed to restore backup: \(error)")
            return false
        }
    }
    
    private func clearExistingData(_ context: NSManagedObjectContext) throws {
        let entities = ["Transaction", "Account", "AccountGroup", "Category"]
        
        for entityName in entities {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: entityName)
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDeleteRequest.resultType = .resultTypeCount
            
            try context.execute(batchDeleteRequest)
        }
    }
    
    private func getCurrentUserID() -> String {
        if let userID = UserDefaults.standard.string(forKey: "currentUserID") {
            return userID
        }
        
        // Generate new user ID
        let newUserID = UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(String(newUserID), forKey: "currentUserID")
        return String(newUserID)
    }
    
    private func getCurrentDeviceID() -> String {
        return UIDevice.current.identifierForVendor?.uuidString.prefix(8).lowercased() ?? "unknown"
    }
    
    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private func loadLastBackupHash() {
        lastBackupHash = UserDefaults.standard.string(forKey: "lastBackupHash")
    }
    
    private func saveLastBackupHash() {
        if let hash = lastBackupHash {
            UserDefaults.standard.set(hash, forKey: "lastBackupHash")
        }
    }
    
    enum BackupError: LocalizedError {
        case missingCredentials
        case invalidURL
        case uploadFailed
        case encodingFailed
        case restoreFailed
        
        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "WebDAV-Zugangsdaten fehlen"
            case .invalidURL:
                return "Ungültige WebDAV-URL"
            case .uploadFailed:
                return "Upload fehlgeschlagen"
            case .encodingFailed:
                return "Backup-Kodierung fehlgeschlagen"
            case .restoreFailed:
                return "Wiederherstellung fehlgeschlagen"
            }
        }
    }
} 