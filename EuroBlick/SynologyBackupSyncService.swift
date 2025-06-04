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
        
        var isNewerThan(_ other: BackupInfo) -> Bool {
            return timestamp > other.timestamp
        }
    }
    
    init(viewModel: TransactionViewModel) {
        self.viewModel = viewModel
        self.backupManager = BackupManager(viewModel: viewModel)
        self.multiUserSyncManager = MultiUserSyncManager()
        
        loadLastSyncDate()
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
            
            // 1. Check for new backups
            let remoteBackups = try await fetchRemoteBackups()
            
            await MainActor.run {
                availableBackups = remoteBackups.sorted { $0.timestamp > $1.timestamp }
            }
            
            // 2. Check if we need to download newer backup
            if let newestRemote = remoteBackups.max(by: { $0.timestamp < $1.timestamp }),
               shouldDownloadBackup(newestRemote) {
                
                await MainActor.run {
                    syncStatus = .downloading
                }
                
                print("⬇️ Downloading newer backup: \(newestRemote.filename)")
                try await downloadAndRestoreBackup(newestRemote)
            }
            
            // 3. Check if we need to upload our changes
            if await backupManager.hasLocalChanges() {
                await MainActor.run {
                    syncStatus = .uploading
                }
                
                print("⬆️ Uploading local changes...")
                try await uploadCurrentState()
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
    
    private func fetchRemoteBackups() async throws -> [BackupInfo] {
        // Get WebDAV credentials
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword"),
              !webdavURL.isEmpty, !webdavUser.isEmpty, !webdavPassword.isEmpty else {
            throw SyncError.missingCredentials
        }
        
        // Create PROPFIND request to list files
        guard let serverURL = URL(string: webdavURL.replacingOccurrences(of: "/EuroBlickBackup", with: "")) else {
            throw SyncError.invalidURL
        }
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        
        let authString = "\(webdavUser):\(webdavPassword)"
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SyncError.networkError("Failed to list remote files")
        }
        
        return try parseWebDAVResponse(data)
    }
    
    private func parseWebDAVResponse(_ data: Data) throws -> [BackupInfo] {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        var backups: [BackupInfo] = []
        
        // Simple XML parsing for backup files
        let lines = xmlString.components(separatedBy: .newlines)
        var currentBackup: [String: String] = [:]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.contains("<D:displayname>") && trimmed.contains("EuroBlickBackup") {
                let filename = extractXMLValue(from: trimmed, tag: "D:displayname") ?? ""
                currentBackup["filename"] = filename
            } else if trimmed.contains("<D:getlastmodified>") {
                let dateString = extractXMLValue(from: trimmed, tag: "D:getlastmodified") ?? ""
                currentBackup["lastModified"] = dateString
            } else if trimmed.contains("<D:getcontentlength>") {
                let sizeString = extractXMLValue(from: trimmed, tag: "D:getcontentlength") ?? ""
                currentBackup["size"] = sizeString
            } else if trimmed.contains("</D:response>") && !currentBackup.isEmpty {
                // End of response, create backup info
                if let filename = currentBackup["filename"],
                   filename.contains("EuroBlickBackup"),
                   let timestamp = parseWebDAVDate(currentBackup["lastModified"] ?? ""),
                   let sizeString = currentBackup["size"],
                   let size = Int64(sizeString) {
                    
                    let backup = BackupInfo(
                        filename: filename,
                        timestamp: timestamp,
                        size: size,
                        userID: extractUserID(from: filename),
                        deviceID: extractDeviceID(from: filename)
                    )
                    backups.append(backup)
                }
                currentBackup.removeAll()
            }
        }
        
        return backups
    }
    
    private func extractXMLValue(from line: String, tag: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"
        
        guard let openRange = line.range(of: openTag),
              let closeRange = line.range(of: closeTag) else {
            return nil
        }
        
        let startIndex = openRange.upperBound
        let endIndex = closeRange.lowerBound
        
        return String(line[startIndex..<endIndex])
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
    
    private func downloadAndRestoreBackup(_ backupInfo: BackupInfo) async throws {
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") else {
            throw SyncError.missingCredentials
        }
        
        let fileURL = URL(string: webdavURL.replacingOccurrences(of: "/EuroBlickBackup", with: "/\(backupInfo.filename)"))!
        
        var request = URLRequest(url: fileURL)
        request.httpMethod = "GET"
        
        let authString = "\(webdavUser):\(webdavPassword)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SyncError.networkError("Failed to download backup")
        }
        
        // Save to temporary file and restore
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(backupInfo.filename)
        try data.write(to: tempURL)
        
        await MainActor.run {
            syncStatus = .syncing
        }
        
        // Restore using multi-user sync manager for conflict resolution
        let success = await multiUserSyncManager.restoreWithConflictResolution(from: tempURL, viewModel: viewModel)
        
        if !success {
            throw SyncError.restoreError("Failed to restore backup with conflict resolution")
        }
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    private func uploadCurrentState() async throws {
        let backup = await backupManager.createEnhancedBackup()
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