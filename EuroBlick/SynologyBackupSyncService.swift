import Foundation
import SwiftUI
import CoreData

class SynologyBackupSyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var availableBackups: [BackupInfo] = []
    
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 30 // Sync alle 30 Sekunden
    private let viewModel: TransactionViewModel
    private let backupManager: BackupManager
    private let multiUserSyncManager: MultiUserSyncManager
    
    enum SyncStatus {
        case idle
        case checking
        case downloading
        case uploading
        case syncing
        case error(String)
        case success
    }
    
    struct BackupInfo: Identifiable, Codable {
        let id = UUID()
        let filename: String
        let timestamp: Date
        let size: Int64
        let userID: String?
        let deviceID: String
        
        func isNewerThan(_ other: BackupInfo) -> Bool {
            return timestamp > other.timestamp
        }
        
        enum CodingKeys: String, CodingKey {
            case filename, timestamp, size, userID, deviceID
        }
    }
    
    init(viewModel: TransactionViewModel) {
        self.viewModel = viewModel
        self.backupManager = BackupManager(viewModel: viewModel)
        self.multiUserSyncManager = MultiUserSyncManager()
        
        loadLastSyncDate()
        // TEMPORARILY DISABLED: startAutoSync() - to stop the endless loop
        print("🛑 Automatic sync DISABLED to prevent endless loop")
        startAutoSync()
    }
    
    deinit {
        stopAutoSync()
    }
    
    // MARK: - Public Methods
    
    func startAutoSync() {
        guard syncTimer == nil else { return }
        
        print("🔄 Starting automatic Synology Drive sync...")
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performAutoSync()
            }
        }
        
        // Perform initial sync
        Task {
            await performAutoSync()
        }
    }
    
    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        print("⏹️ Stopped automatic sync")
    }
    
    func performManualSync() async {
        await performAutoSync(isManual: true)
    }
    
    func analyzeAvailableBackups() async -> [(BackupInfo, String)] {
        do {
            let backups = try await fetchRemoteBackups()
            var results: [(BackupInfo, String)] = []
            
            for backup in backups.sorted(by: { $0.timestamp > $1.timestamp }) {
                let analysis = await analyzeBackupContent(backup)
                results.append((backup, analysis))
            }
            
            return results
        } catch {
            print("❌ Failed to analyze backups: \(error)")
            return []
        }
    }
    
    func restoreSpecificBackup(_ backup: BackupInfo) async {
        do {
            await MainActor.run {
                isSyncing = true
                syncStatus = .downloading
            }
            
            print("🎯 Manually restoring selected backup: \(backup.filename)")
            try await downloadAndRestoreBackup(backup)
            
            await MainActor.run {
                syncStatus = .success
                lastSyncDate = Date()
                saveLastSyncDate()
            }
            
            print("✅ Manual backup restore completed successfully")
            
            // Force UI refresh on main thread after successful restore
            await MainActor.run {
                viewModel.fetchAccountGroups()
                viewModel.fetchCategories()
                print("🔄 Manual restore - UI refreshed on main thread")
            }
            
        } catch {
            print("❌ Manual backup restore failed: \(error)")
            await MainActor.run {
                syncStatus = .error(error.localizedDescription)
            }
        }
        
        await MainActor.run {
            isSyncing = false
        }
    }
    
    private func analyzeBackupContent(_ backupInfo: BackupInfo) async -> String {
        do {
            guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
                  let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
                  let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") else {
                return "❌ WebDAV credentials missing"
            }
            
            // Construct download URL
            var fileURL: URL
            if webdavURL.hasSuffix(".json") {
                let url = URL(string: webdavURL)!
                let directoryURL = url.deletingLastPathComponent()
                fileURL = directoryURL.appendingPathComponent(backupInfo.filename)
            } else {
                let baseURL = webdavURL.hasSuffix("/") ? webdavURL : webdavURL + "/"
                let encodedFilename = backupInfo.filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? backupInfo.filename
                guard let constructedURL = URL(string: baseURL + encodedFilename) else {
                    return "❌ Invalid URL"
                }
                fileURL = constructedURL
            }
            
            var request = URLRequest(url: fileURL)
            request.httpMethod = "GET"
            
            let authString = "\(webdavUser):\(webdavPassword)"
            let authData = authString.data(using: .utf8)!
            let base64Auth = authData.base64EncodedString()
            request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                return "❌ Download failed"
            }
            
            // Try to parse and analyze content
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return analyzeJSONContent(jsonObject)
            } else {
                return "❌ Invalid JSON format"
            }
            
        } catch {
            return "❌ Error: \(error.localizedDescription)"
        }
    }
    
    private func analyzeJSONContent(_ json: [String: Any]) -> String {
        var analysis: [String] = []
        
        // Check format
        if let version = json["version"] as? String {
            analysis.append("📋 Format: Enhanced v\(version)")
            
            // Enhanced format analysis
            if let accountGroups = json["accountGroups"] as? [[String: Any]] {
                analysis.append("📁 Groups: \(accountGroups.count)")
            }
            if let accounts = json["accounts"] as? [[String: Any]] {
                analysis.append("💳 Accounts: \(accounts.count)")
            }
            if let transactions = json["transactions"] as? [[String: Any]] {
                analysis.append("💰 Transactions: \(transactions.count)")
            }
            if let categories = json["categories"] as? [[String: Any]] {
                analysis.append("🏷️ Categories: \(categories.count)")
            }
            
            // Show some account names
            if let accounts = json["accounts"] as? [[String: Any]], !accounts.isEmpty {
                let accountNames = accounts.prefix(3).compactMap { $0["name"] as? String }
                if !accountNames.isEmpty {
                    analysis.append("📋 Sample accounts: \(accountNames.joined(separator: ", "))")
                }
            }
            
        } else {
            analysis.append("📋 Format: Legacy")
            
            // Legacy format analysis
            if let accountGroups = json["accountGroups"] as? [[String: Any]] {
                analysis.append("📁 Groups: \(accountGroups.count)")
            }
            if let accounts = json["accounts"] as? [[String: Any]] {
                analysis.append("💳 Accounts: \(accounts.count)")
            }
            if let transactions = json["transactions"] as? [[String: Any]] {
                analysis.append("💰 Transactions: \(transactions.count)")
            }
            if let categories = json["categories"] as? [[String: Any]] {
                analysis.append("🏷️ Categories: \(categories.count)")
            }
        }
        
        return analysis.joined(separator: " | ")
    }
    
    // MARK: - Private Methods
    
    private func performAutoSync(isManual: Bool = false) async {
        guard !isSyncing else {
            print("📋 Sync already in progress, skipping...")
            return
        }
        
        await MainActor.run {
            isSyncing = true
            syncStatus = .checking
        }
        
        do {
            print("🔍 Checking for new backups on Synology Drive...")
            
            // 1. Check local data state first
            let localDataExists = await checkLocalDataExists()
            print("📊 Local data check: \(localDataExists ? "HAS DATA" : "EMPTY")")
            
            // 2. Check for remote backups
            let remoteBackups = try await fetchRemoteBackups()
            
            await MainActor.run {
                availableBackups = remoteBackups.sorted { $0.timestamp > $1.timestamp }
            }
            
            let hasRemoteData = !remoteBackups.isEmpty
            print("📊 Remote data check: \(hasRemoteData ? "HAS BACKUPS (\(remoteBackups.count))" : "EMPTY")")
            
            // 3. Smart sync decision making
            if !localDataExists && hasRemoteData {
                // Case 1: Local empty, remote has data → Download newest
                if let newestRemote = remoteBackups.max(by: { $0.timestamp < $1.timestamp }) {
                    await MainActor.run {
                        syncStatus = .downloading
                    }
                    
                    print("📥 LOCAL EMPTY → Downloading remote backup: \(newestRemote.filename)")
                    try await downloadAndRestoreBackup(newestRemote)
                }
            } else if localDataExists && !hasRemoteData {
                // Case 2: Local has data, remote empty → Upload
                await MainActor.run {
                    syncStatus = .uploading
                }
                
                print("📤 REMOTE EMPTY → Uploading local data...")
                try await uploadCurrentState()
            } else if localDataExists && hasRemoteData {
                // Case 3: Both have data → Check for newer remote backup
                if let newestRemote = remoteBackups.max(by: { $0.timestamp < $1.timestamp }),
                   shouldDownloadBackup(newestRemote) {
                    
                    await MainActor.run {
                        syncStatus = .downloading
                    }
                    
                    print("📥 CONFLICT RESOLUTION → Downloading newer backup: \(newestRemote.filename)")
                    try await downloadAndRestoreBackup(newestRemote)
                }
                
                // Check if we have local changes to upload
                if await backupManager.hasLocalChanges() {
                    await MainActor.run {
                        syncStatus = .uploading
                    }
                    
                    print("📤 LOCAL CHANGES → Uploading changes...")
                    try await uploadCurrentState()
                }
            } else {
                // Case 4: Both empty → Nothing to do
                print("⭕ Both local and remote are empty - nothing to sync")
            }
            
            await MainActor.run {
                syncStatus = .success
                lastSyncDate = Date()
                saveLastSyncDate()
            }
            
            print("✅ Sync completed successfully at \(Date())")
            
        } catch {
            print("❌ Sync failed: \(error)")
            await MainActor.run {
                syncStatus = .error(error.localizedDescription)
            }
        }
        
        await MainActor.run {
            isSyncing = false
        }
    }
    
    private func checkLocalDataExists() async -> Bool {
        return await withCheckedContinuation { continuation in
            viewModel.getContext().perform {
                // Check if we have any meaningful data
                let groupRequest: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
                let accountRequest: NSFetchRequest<Account> = Account.fetchRequest()
                let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                
                do {
                    let groups = try self.viewModel.getContext().fetch(groupRequest)
                    let accounts = try self.viewModel.getContext().fetch(accountRequest)
                    let transactions = try self.viewModel.getContext().fetch(transactionRequest)
                    
                    let hasData = !groups.isEmpty || !accounts.isEmpty || !transactions.isEmpty
                    
                    print("📊 Local data inventory:")
                    print("  Account Groups: \(groups.count)")
                    print("  Accounts: \(accounts.count)")
                    print("  Transactions: \(transactions.count)")
                    print("  Has meaningful data: \(hasData)")
                    
                    continuation.resume(returning: hasData)
                } catch {
                    print("❌ Error checking local data: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private func fetchRemoteBackups() async throws -> [BackupInfo] {
        // Get WebDAV credentials
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword"),
              !webdavURL.isEmpty, !webdavUser.isEmpty, !webdavPassword.isEmpty else {
            print("❌ WebDAV credentials missing or empty")
            print("  URL: \(UserDefaults.standard.string(forKey: "webdavURL") ?? "nil")")
            print("  User: \(UserDefaults.standard.string(forKey: "webdavUser") ?? "nil")")
            print("  Password: \(UserDefaults.standard.string(forKey: "webdavPassword")?.isEmpty == false ? "present" : "missing")")
            throw SyncError.missingCredentials
        }
        
        // First try: Check the configured directory
        let result1 = try await fetchBackupsFromPath(webdavURL, user: webdavUser, password: webdavPassword)
        if !result1.isEmpty {
            return result1
        }
        
        print("🔄 No backups found in configured path, trying alternative paths...")
        
        // Second try: Check if the URL points to a specific file, try the parent directory  
        if webdavURL.hasSuffix(".json") {
            if let url = URL(string: webdavURL) {
                let parentURL = url.deletingLastPathComponent().absoluteString
                print("🔄 Trying parent directory: \(parentURL)")
                let result2 = try await fetchBackupsFromPath(parentURL, user: webdavUser, password: webdavPassword)
                if !result2.isEmpty {
                    return result2
                }
            }
        }
        
        // Third try: Try root WebDAV directory
        if let baseHost = URL(string: webdavURL)?.scheme,
           let host = URL(string: webdavURL)?.host,
           let port = URL(string: webdavURL)?.port {
            let rootWebDAV = "\(baseHost)://\(host):\(port)/webdav"
            print("🔄 Trying root WebDAV directory: \(rootWebDAV)")
            let result3 = try await fetchBackupsFromPath(rootWebDAV, user: webdavUser, password: webdavPassword)
            if !result3.isEmpty {
                return result3
            }
        }
        
        // Fourth try: Direct file check - maybe the file still exists
        print("🔄 Trying direct file access to original configured file...")
        if webdavURL.hasSuffix(".json") {
            let directResult = try await checkDirectFileAccess(webdavURL, user: webdavUser, password: webdavPassword)
            if let backup = directResult {
                return [backup]
            }
        }
        
        return []
    }
    
    private func fetchBackupsFromPath(_ path: String, user: String, password: String) async throws -> [BackupInfo] {
        // Create PROPFIND request to list files
        let baseURL: String
        if path.hasSuffix(".json") {
            // URL points to a specific file, get directory
            guard let url = URL(string: path) else {
                print("❌ Invalid WebDAV URL: \(path)")
                throw SyncError.invalidURL
            }
            baseURL = url.deletingLastPathComponent().absoluteString
        } else if path.contains("/EuroBlickBackup") {
            // URL contains backup reference, remove it
            baseURL = path.replacingOccurrences(of: "/EuroBlickBackup", with: "")
        } else {
            // URL is directory, use as-is
            baseURL = path
        }
        
        guard let serverURL = URL(string: baseURL) else {
            print("❌ Invalid server URL: \(baseURL)")
            throw SyncError.invalidURL
        }
        
        print("🌐 WebDAV PROPFIND Request:")
        print("  Original URL: \(path)")
        print("  Server URL: \(serverURL)")
        print("  User: \(user)")
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        
        let authString = "\(user):\(password)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        
        let propfindBody = """
        <?xml version="1.0" encoding="utf-8" ?>
        <propfind xmlns="DAV:">
            <prop>
                <getlastmodified/>
                <getcontentlength/>
                <displayname/>
            </prop>
        </propfind>
        """
        request.httpBody = propfindBody.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw SyncError.networkError("Invalid response type")
            }
            
            print("📡 WebDAV Response:")
            print("  Status Code: \(httpResponse.statusCode)")
            print("  Headers: \(httpResponse.allHeaderFields)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("  Response Body: \(responseString.prefix(500))...")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = "HTTP \(httpResponse.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                print("❌ HTTP Error: \(errorMessage)")
                throw SyncError.networkError(errorMessage)
            }
            
            return try parseWebDAVResponse(data)
            
        } catch {
            print("❌ Network error: \(error)")
            if let urlError = error as? URLError {
                print("  URLError code: \(urlError.code)")
                print("  URLError description: \(urlError.localizedDescription)")
            }
            throw SyncError.networkError("Network error: \(error.localizedDescription)")
        }
    }
    
    private func checkDirectFileAccess(_ fileURL: String, user: String, password: String) async throws -> BackupInfo? {
        guard let url = URL(string: fileURL) else { return nil }
        
        print("🔍 Direct file check: \(fileURL)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"  // Just check if file exists
        
        let authString = "\(user):\(password)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            
            print("📡 Direct file response: \(httpResponse.statusCode)")
            
            if 200...299 ~= httpResponse.statusCode {
                let filename = url.lastPathComponent
                let size = Int64(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
                
                // Get last modified from headers
                var timestamp = Date()
                if let lastModifiedString = httpResponse.value(forHTTPHeaderField: "Last-Modified") {
                    timestamp = parseWebDAVDate(lastModifiedString) ?? Date()
                }
                
                print("✅ Found direct file: \(filename) (\(size) bytes)")
                
                return BackupInfo(
                    filename: filename,
                    timestamp: timestamp,
                    size: size,
                    userID: extractUserID(from: filename),
                    deviceID: extractDeviceID(from: filename)
                )
            }
            
        } catch {
            print("❌ Direct file check failed: \(error)")
        }
        
        return nil
    }
    
    private func parseWebDAVResponse(_ data: Data) throws -> [BackupInfo] {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        print("🔍 Parsing WebDAV XML response:")
        print("📄 Full XML: \(xmlString)")
        
        var backups: [BackupInfo] = []
        
        // Split into individual <D:response> blocks
        let responseBlocks = xmlString.components(separatedBy: "<D:response")
        print("📦 Found \(responseBlocks.count - 1) response blocks")
        
        for (index, block) in responseBlocks.enumerated() {
            if index == 0 { continue } // Skip the first empty block
            
            let fullBlock = "<D:response" + block
            print("📋 Processing response block \(index):")
            print("  Content: \(fullBlock.prefix(200))...")
            
            // Extract href (file path)
            var href: String?
            if let hrefStart = fullBlock.range(of: "<D:href>"),
               let hrefEnd = fullBlock.range(of: "</D:href>") {
                let startIndex = hrefStart.upperBound
                let endIndex = hrefEnd.lowerBound
                href = String(fullBlock[startIndex..<endIndex])
                print("  📁 Found href: \(href ?? "nil")")
            }
            
            // Skip directory entries (ending with /)
            guard let filePath = href, !filePath.hasSuffix("/") else {
                print("  ⏭️ Skipping directory entry: \(href ?? "nil")")
                continue
            }
            
            // Extract filename from path
            let filename = URL(string: filePath)?.lastPathComponent ?? filePath
            print("  📄 Filename: \(filename)")
            
            // Only process EuroBlick backup files
            guard filename.contains("EuroBlick") && filename.hasSuffix(".json") else {
                print("  ⏭️ Skipping non-backup file: \(filename)")
                continue
            }
            
            // Extract last modified date
            var lastModified: Date?
            if let dateStart = fullBlock.range(of: "<lp1:getlastmodified>") ?? fullBlock.range(of: "<D:getlastmodified>"),
               let dateEnd = fullBlock.range(of: "</lp1:getlastmodified>") ?? fullBlock.range(of: "</D:getlastmodified>") {
                let startIndex = dateStart.upperBound
                let endIndex = dateEnd.lowerBound
                let dateString = String(fullBlock[startIndex..<endIndex])
                lastModified = parseWebDAVDate(dateString)
                print("  📅 Date: \(dateString) -> \(lastModified?.description ?? "nil")")
            }
            
            // Extract content length
            var contentLength: Int64 = 0
            if let sizeStart = fullBlock.range(of: "<lp1:getcontentlength>") ?? fullBlock.range(of: "<D:getcontentlength>"),
               let sizeEnd = fullBlock.range(of: "</lp1:getcontentlength>") ?? fullBlock.range(of: "</D:getcontentlength>") {
                let startIndex = sizeStart.upperBound
                let endIndex = sizeEnd.lowerBound
                let sizeString = String(fullBlock[startIndex..<endIndex])
                contentLength = Int64(sizeString) ?? 0
                print("  📦 Size: \(sizeString) -> \(contentLength)")
            }
            
            // Create backup info if we have minimum required data
            if let timestamp = lastModified {
                let backup = BackupInfo(
                    filename: filename,
                    timestamp: timestamp,
                    size: contentLength,
                    userID: extractUserID(from: filename),
                    deviceID: extractDeviceID(from: filename)
                )
                backups.append(backup)
                print("  ✅ Created backup info: \(backup.filename)")
            } else {
                print("  ❌ Missing timestamp for: \(filename)")
            }
        }
        
        print("🎯 Found \(backups.count) valid backup files:")
        for backup in backups {
            print("  📄 \(backup.filename) - \(backup.size) bytes - \(formatDate(backup.timestamp))")
        }
        
        return backups
    }
    
    private func parseWebDAVDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
    
    private func extractUserID(from filename: String) -> String? {
        // Extract user ID from filename pattern: EuroBlickBackup_user123_device456_timestamp.json
        let components = filename.components(separatedBy: "_")
        if components.count >= 3 && components[1].starts(with: "user") {
            return String(components[1].dropFirst(4)) // Remove "user" prefix
        }
        return nil
    }
    
    private func extractDeviceID(from filename: String) -> String {
        let components = filename.components(separatedBy: "_")
        if components.count >= 3 && components[2].starts(with: "device") {
            return String(components[2].dropFirst(6)) // Remove "device" prefix
        }
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
    
    private func shouldDownloadBackup(_ remoteBackup: BackupInfo) -> Bool {
        // Check if the remote backup is newer than our last sync
        if let lastSync = lastSyncDate {
            return remoteBackup.timestamp > lastSync
        }
        return true // First sync, download latest
    }
    
    private func chooseBestBackup(_ backups: [BackupInfo]) async -> BackupInfo? {
        guard !backups.isEmpty else { return nil }
        
        print("🎯 Analyzing \(backups.count) available backups...")
        
        // Sort by timestamp (newest first) but also consider data richness
        let sortedBackups = backups.sorted { $0.timestamp > $1.timestamp }
        
        for backup in sortedBackups.prefix(3) { // Check top 3 newest
            print("📋 Backup: \(backup.filename)")
            print("  📅 Date: \(formatDate(backup.timestamp))")
            print("  📦 Size: \(backup.size) bytes")
            print("  👤 User: \(backup.userID ?? "unknown")")
            print("  📱 Device: \(backup.deviceID)")
        }
        
        // For now, return the newest, but we could add logic to prefer larger backups
        // that might contain more data
        return sortedBackups.first
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
    
    private func downloadAndRestoreBackup(_ backupInfo: BackupInfo) async throws {
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") else {
            throw SyncError.missingCredentials
        }
        
        // Construct the correct download URL
        var fileURL: URL
        if webdavURL.hasSuffix(".json") {
            // If webdavURL points to a specific file, get the directory and append our filename
            let url = URL(string: webdavURL)!
            let directoryURL = url.deletingLastPathComponent()
            fileURL = directoryURL.appendingPathComponent(backupInfo.filename)
        } else {
            // If webdavURL is a directory, append the filename
            let baseURL = webdavURL.hasSuffix("/") ? webdavURL : webdavURL + "/"
            let encodedFilename = backupInfo.filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? backupInfo.filename
            guard let constructedURL = URL(string: baseURL + encodedFilename) else {
                throw SyncError.invalidURL
            }
            fileURL = constructedURL
        }
        
        print("📥 Downloading backup from: \(fileURL.absoluteString)")
        
        var request = URLRequest(url: fileURL)
        request.httpMethod = "GET"
        
        let authString = "\(webdavUser):\(webdavPassword)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw SyncError.networkError("Invalid response type")
        }
        
        print("📡 Download response:")
        print("  Status Code: \(httpResponse.statusCode)")
        print("  Content Length: \(data.count) bytes")
        
        guard 200...299 ~= httpResponse.statusCode else {
            let errorMessage = "HTTP \(httpResponse.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
            print("❌ Download failed: \(errorMessage)")
            throw SyncError.networkError("Failed to download backup: \(errorMessage)")
        }
        
        print("✅ Successfully downloaded \(data.count) bytes")
        
        // Save to temporary file and restore
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(backupInfo.filename)
        try data.write(to: tempURL)
        
        print("📄 Temporary file created at: \(tempURL.path)")
        
        await MainActor.run {
            syncStatus = .syncing
        }
        
        // Restore using multi-user sync manager for conflict resolution
        print("🔄 Starting restore with conflict resolution...")
        let success = await multiUserSyncManager.restoreWithConflictResolution(from: tempURL, viewModel: viewModel)
        
        if !success {
            print("❌ Restore with conflict resolution failed")
            throw SyncError.restoreError("Failed to restore backup with conflict resolution")
        }
        
        print("✅ Backup successfully restored!")
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    private func uploadCurrentState() async throws {
        guard let backup = await backupManager.createEnhancedBackup() else {
            throw SyncError.restoreError("Failed to create backup data")
        }
        try await backupManager.uploadBackup(backup)
    }
    
    private func loadLastSyncDate() {
        if let timestamp = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date {
            lastSyncDate = timestamp
        }
    }
    
    private func saveLastSyncDate() {
        UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
    }
    
    enum SyncError: LocalizedError {
        case missingCredentials
        case invalidURL
        case networkError(String)
        case restoreError(String)
        
        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "WebDAV-Zugangsdaten fehlen"
            case .invalidURL:
                return "Ungültige WebDAV-URL"
            case .networkError(let message):
                return "Netzwerkfehler: \(message)"
            case .restoreError(let message):
                return "Wiederherstellungsfehler: \(message)"
            }
        }
    }
} 