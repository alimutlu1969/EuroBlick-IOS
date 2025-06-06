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
            let icon: String?
            let iconColor: String?
            let accounts: [String]
        }
        
        struct AccountData: Codable {
            let name: String
            let group: String
            let type: String?
            let icon: String?
            let iconColor: String?
            let order: Int16?
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
        guard let backup = await createEnhancedBackup() else { 
            print("📊 hasLocalChanges: Failed to create backup")
            return false 
        }
        
        let currentHash = calculateDataHash(backup)
        let savedHash = lastBackupHash
        
        print("📊 Change Detection:")
        print("  Current Hash: \(currentHash)")
        print("  Saved Hash: \(savedHash ?? "none")")
        print("  Has Changes: \(currentHash != savedHash)")
        
        // Don't upload if we just restored data and haven't made real changes
        if let savedHash = savedHash, currentHash == savedHash {
            print("📊 No changes detected - skipping upload")
            return false
        }
        
        // Also check if we just uploaded recently (within last 2 minutes) to prevent loops
        if let lastUploadTime = UserDefaults.standard.object(forKey: "lastUploadTime") as? Date,
           Date().timeIntervalSince(lastUploadTime) < 120 {
            print("📊 Recently uploaded (\(Int(Date().timeIntervalSince(lastUploadTime)))s ago) - skipping upload")
            return false
        }
        
        return true
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
        
        // Create upload URL - handle both directory and file URLs
        var uploadURL: URL
        if webdavURL.hasSuffix(".json") {
            // WebDAV URL points to a specific file, extract directory and construct new path
            let url = URL(string: webdavURL)!
            let directoryURL = url.deletingLastPathComponent()
            uploadURL = directoryURL.appendingPathComponent(filename)
        } else {
            // WebDAV URL points to directory, append filename
            let baseURL = webdavURL.hasSuffix("/") ? webdavURL : webdavURL + "/"
            guard let constructedURL = URL(string: baseURL + filename) else {
                throw BackupError.invalidURL
            }
            uploadURL = constructedURL
        }
        
        print("📤 Upload Configuration:")
        print("  WebDAV URL: \(webdavURL)")
        print("  Upload URL: \(uploadURL)")
        print("  Filename: \(filename)")
        
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
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("📤 Upload Response:")
        if let httpResponse = response as? HTTPURLResponse {
            print("  Status Code: \(httpResponse.statusCode)")
            print("  Response Headers: \(httpResponse.allHeaderFields)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackupError.uploadFailed
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Upload HTTP Error \(httpResponse.statusCode): \(responseString)")
            throw BackupError.uploadFailed
        }
        
        // Update last backup hash
        lastBackupHash = backup.dataHash
        saveLastBackupHash()
        
        // Save upload time to prevent loops
        UserDefaults.standard.set(Date(), forKey: "lastUploadTime")
        
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
                icon: group.value(forKey: "icon") as? String,
                iconColor: group.value(forKey: "iconColor") as? String,
                accounts: (group.accounts?.allObjects as? [Account])?.compactMap { $0.name } ?? []
            )
        }
        
        let accountsData = accounts.map { account in
            EnhancedBackupData.AccountData(
                name: account.name ?? "",
                group: account.group?.name ?? "",
                type: account.value(forKey: "type") as? String,
                icon: account.value(forKey: "icon") as? String,
                iconColor: account.value(forKey: "iconColor") as? String,
                order: account.value(forKey: "order") as? Int16,
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
        // Create a deterministic hash from the core data - EXCLUDE timestamps to prevent loops
        var hashComponents: [String] = []
        
        // Sort and hash categories
        let sortedCategories = backup.categories.sorted { $0.name < $1.name }
        hashComponents.append("categories:\(sortedCategories.count)")
        for category in sortedCategories {
            hashComponents.append("cat:\(category.name)")
        }
        
        // Sort and hash account groups
        let sortedGroups = backup.accountGroups.sorted { $0.name < $1.name }
        hashComponents.append("groups:\(sortedGroups.count)")
        for group in sortedGroups {
            hashComponents.append("grp:\(group.name):\(group.accounts.sorted().joined(separator:","))")
        }
        
        // Sort and hash accounts
        let sortedAccounts = backup.accounts.sorted { $0.name < $1.name }
        hashComponents.append("accounts:\(sortedAccounts.count)")
        for account in sortedAccounts {
            hashComponents.append("acc:\(account.name):\(account.group):\(account.includeInBalance)")
        }
        
        // Sort and hash transactions - EXCLUDE timestamps and lastModified to prevent constant changes
        let sortedTransactions = backup.transactions.sorted { $0.id < $1.id }
        hashComponents.append("transactions:\(sortedTransactions.count)")
        for transaction in sortedTransactions {
            // Only include core transaction data, not timestamps
            hashComponents.append("txn:\(transaction.id):\(transaction.amount):\(transaction.category):\(transaction.account):\(transaction.type):\(transaction.usage)")
        }
        
        let combinedString = hashComponents.joined(separator:"|")
        print("📊 STABLE Hash calculation (no timestamps): \(combinedString.prefix(200))...")
        
        return String(combinedString.hashValue)
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
                group.setValue(groupData.icon, forKey: "icon")
                group.setValue(groupData.iconColor, forKey: "iconColor")
                groupMap[groupData.name] = group
            }
            
            // Restore accounts
            var accountMap: [String: Account] = [:]
            for accountData in backup.accounts {
                let account = Account(context: context)
                account.name = accountData.name
                account.group = groupMap[accountData.group]
                account.setValue(accountData.type, forKey: "type")
                account.setValue(accountData.icon, forKey: "icon")
                account.setValue(accountData.iconColor, forKey: "iconColor")
                account.setValue(accountData.order, forKey: "order")
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