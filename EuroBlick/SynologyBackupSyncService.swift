import Foundation
import SwiftUI
import CoreData

// MARK: - Enhanced Error Handling & Retry Mechanism

class RetryManager {
    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    
    init(maxRetries: Int = 3, baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 10.0) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }
    
    func executeWithRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if attempt < maxRetries {
                    let delay = min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
                    print("🔄 Retry attempt \(attempt)/\(maxRetries) after \(String(format: "%.1f", delay))s delay")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NSError(domain: "SyncError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unknown error after \(maxRetries) retries"])
    }
}

// MARK: - Enhanced Logging System

class SyncLogger {
    static let shared = SyncLogger()
    private var logs: [LogEntry] = []
    private let maxLogEntries = 200
    
    struct LogEntry {
        let timestamp: Date
        let level: LogLevel
        let message: String
        let context: String?
        
        var formattedMessage: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let timeString = formatter.string(from: timestamp)
            let levelString = level.emoji
            let contextString = context != nil ? "[\(context!)]" : ""
            return "[\(timeString)] \(levelString) \(contextString) \(message)"
        }
    }
    
    enum LogLevel: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .critical: return "🚨"
            }
        }
    }
    
    func log(_ message: String, level: LogLevel = .info, context: String? = nil) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message, context: context)
        logs.append(entry)
        
        // Keep only the last maxLogEntries
        if logs.count > maxLogEntries {
            logs = Array(logs.suffix(maxLogEntries))
        }
        
        // Also print to console for debugging
        print(entry.formattedMessage)
    }
    
    func getLogs() -> [String] {
        return logs.map { $0.formattedMessage }
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    func getLogsByLevel(_ level: LogLevel) -> [String] {
        return logs.filter { $0.level == level }.map { $0.formattedMessage }
    }
}

// MARK: - Export Data Structures

struct ExportData: Codable {
    let version: String
    let userID: String
    let deviceName: String
    let timestamp: TimeInterval
    let appVersion: String
    let deviceID: String
    let accountGroups: [AccountGroupExport]
    let accounts: [AccountExport]
    let transactions: [TransactionExport]
    let categories: [CategoryExport]
}

struct AccountGroupExport: Codable {
    let id: UUID
    let name: String
    let color: String
    let icon: String
    let order: Int
}

struct AccountExport: Codable {
    let id: UUID
    let name: String
    let balance: Double
    let accountGroupID: UUID
    let icon: String
    let iconColor: String
    let order: Int
}

struct TransactionExport: Codable {
    let id: UUID
    let amount: Double
    let date: Date
    let note: String
    let accountID: UUID
    let categoryID: UUID
    let type: String
}

struct CategoryExport: Codable {
    let id: UUID
    let name: String
    let color: String
    let icon: String
    let order: Int
}

@MainActor
class SynologyBackupSyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var availableBackups: [BackupInfo] = []
    @Published var debugLogs: [String] = []
    @Published var syncProgress: Double = 0.0
    @Published var syncDetails: String = ""
    
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 600 // Sync alle 10 Minuten
    private let viewModel: TransactionViewModel
    private let backupManager: BackupManager
    private let multiUserSyncManager: MultiUserSyncManager
    
    // Enhanced Components
    private let retryManager = RetryManager(maxRetries: 3, baseDelay: 2.0, maxDelay: 15.0)
    private let logger = SyncLogger.shared
    
    // Kritische Safeguards
    private var lastSyncAttempt: Date?
    private var consecutiveUploads: Int = 0
    private let maxConsecutiveUploads = 2 // Maximale Anzahl aufeinanderfolgender Uploads
    
    // Performance Tracking
    private var syncStartTime: Date?
    private var syncMetrics: [String: TimeInterval] = [:]
    
    // Backup-spezifische Eigenschaften
    private var userID: String {
        return UserDefaults.standard.string(forKey: "userID") ?? "default"
    }
    
    private var deviceID: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
    
    enum SyncStatus {
        case idle
        case checking
        case downloading
        case uploading
        case syncing
        case error(String)
        case success
        case blocked(String) // Neu: Für blockierte Sync-Versuche
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
        // AUTO-SYNC: Verbesserte Logik mit Safeguards
        debugLog("🔄 Initializing Synology Drive sync service with improved safeguards")
        
        // Auto-Fix Listener für UI-Faults
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AutoFixUIFaults"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.debugLog("🔧 AUTO-FIX: Detected repeated UI faults - triggering automatic fix")
                await self.fixUIDisplayProblem()
            }
        }
        
        // Aktiviere Auto-Sync nur wenn konfiguriert und aktiviert
        enableAutoSyncIfConfigured()
    }
    
    deinit {
        Task { @MainActor [weak self] in
            self?.stopAutoSync()
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    private func debugLog(_ message: String, level: SyncLogger.LogLevel = .info, context: String? = nil) {
        logger.log(message, level: level, context: context)
        
        DispatchQueue.main.async { [weak self] in
            self?.debugLogs = self?.logger.getLogs() ?? []
        }
    }
    
    func clearDebugLogs() {
        logger.clearLogs()
        DispatchQueue.main.async { [weak self] in
            self?.debugLogs.removeAll()
        }
    }
    
    // MARK: - Public Methods
    
    func startAutoSync() {
        guard syncTimer == nil else {
            debugLog("⚠️ Auto-sync already running")
            return
        }
        
        // Prüfe WebDAV-Konfiguration bevor Auto-Sync gestartet wird
        guard hasValidWebDAVConfiguration() else {
            debugLog("⚠️ Auto-sync not started: WebDAV configuration incomplete")
            syncStatus = .error("WebDAV configuration incomplete")
            return
        }
        
        debugLog("🔄 Starting automatic Synology Drive sync with improved safeguards...")
        
        // Starte Timer auf dem Main Thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.syncTimer = Timer.scheduledTimer(withTimeInterval: self.syncInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    // Prüfe ob ein Sync bereits läuft
                    guard !self.isSyncing else {
                        self.debugLog("⏳ Sync skipped: Another sync is in progress")
                        return
                    }
                    
                    // Prüfe ob der letzte Sync-Versuch zu kurz her ist
                    if let lastAttempt = self.lastSyncAttempt {
                        let timeSinceLastAttempt = Date().timeIntervalSince(lastAttempt)
                        if timeSinceLastAttempt < 30 { // Mindestens 30 Sekunden zwischen Sync-Versuchen
                            self.debugLog("⏳ Sync skipped: Too soon since last attempt (\(Int(timeSinceLastAttempt))s)")
                            return
                        }
                    }
                    
                    self.lastSyncAttempt = Date()
                    await self.performAutoSyncWithSafeguards()
                }
            }
            
            // Führe ersten Sync nach kurzer Verzögerung aus
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 Sekunden Verzögerung
                await self?.performAutoSyncWithSafeguards()
            }
        }
    }
    
    @MainActor
    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        debugLog("⏹️ Stopped automatic sync")
    }
    
    func performManualSync(allowUpload: Bool = false) async {
        debugLog("🔧 MANUAL SYNC started (allowUpload: \(allowUpload))")
        
        guard !isSyncing else {
            debugLog("📋 Manual sync skipped: sync already in progress")
            return
        }
        
        await MainActor.run {
            isSyncing = true
            syncStatus = .checking
        }
        
        do {
            // 1. Check local and remote data
            let localDataExists = await checkLocalDataExists()
            let remoteBackups = try await fetchRemoteBackups()
            
            await MainActor.run {
                availableBackups = remoteBackups.sorted { $0.timestamp > $1.timestamp }
            }
            
            let hasRemoteData = !remoteBackups.isEmpty
            debugLog("📊 Manual sync state: Local=\(localDataExists ? "YES" : "NO"), Remote=\(hasRemoteData ? "YES(\(remoteBackups.count))" : "NO")")
            
            // 2. Download logic (always safe)
            if hasRemoteData, let newestRemote = remoteBackups.max(by: { $0.timestamp < $1.timestamp }) {
                if await shouldDownloadConservatively(newestRemote) || allowUpload {
                    await MainActor.run { syncStatus = .downloading }
                    debugLog("📥 MANUAL DOWNLOAD → \(newestRemote.filename)")
                    try await downloadAndRestoreBackup(newestRemote)
                    consecutiveUploads = 0 // Reset on successful download
                }
            }
            
            // 3. Upload logic (only if explicitly allowed)
            if allowUpload && localDataExists {
                let shouldUpload: Bool
                if !hasRemoteData {
                    shouldUpload = true
                } else {
                    shouldUpload = await shouldUploadConservatively()
                }
                
                if shouldUpload {
                    await MainActor.run { syncStatus = .uploading }
                    debugLog("📤 MANUAL UPLOAD → Starting upload")
                    try await uploadCurrentState()
                    consecutiveUploads += 1
                }
            }
            
            await MainActor.run {
                syncStatus = .success
                lastSyncDate = Date()
                saveLastSyncDate()
            }
            
            debugLog("✅ Manual sync completed")
            
        } catch {
            debugLog("❌ Manual sync failed: \(error)")
            await MainActor.run {
                syncStatus = .error(error.localizedDescription)
            }
        }
        
        await MainActor.run {
            isSyncing = false
        }
    }
    
    func performDiagnosticSync() async {
        debugLog("🔍 Starting diagnostic sync...")
        
        // Get current user ID
        let currentUserID = UserDefaults.standard.string(forKey: "currentUserID") ?? "unknown"
        let deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let prefixString = String(deviceUUID.prefix(8))
        let currentDeviceID = prefixString.lowercased()
        
        debugLog("📱 Device Info:")
        debugLog("  User ID: \(currentUserID)")
        debugLog("  Device ID: \(currentDeviceID)")
        
        debugLog("📋 Checking WebDAV configuration...")
        
        // Check WebDAV configuration
        let hasWebDAV = hasValidWebDAVConfiguration()
        debugLog("📋 WebDAV configuration: \(hasWebDAV ? "✅ Valid" : "❌ Invalid")")
        
        if !hasWebDAV {
            debugLog("❌ Cannot proceed without WebDAV configuration")
            return
        }
        
        // Check auto-sync status
        debugLog("📋 Auto-sync enabled: \(isAutoSyncEnabled ? "✅ Yes" : "❌ No")")
        debugLog("📋 Sync timer active: \(syncTimer != nil ? "✅ Yes" : "❌ No")")
        
        // Check last sync date
        if let lastSync = lastSyncDate {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            debugLog("📋 Last sync: \(formatDate(lastSync)) (\(Int(timeSinceLastSync))s ago)")
        } else {
            debugLog("📋 Last sync: Never")
        }
        
        // Check local data
        let hasLocalData = await checkLocalDataExists()
        debugLog("📋 Local data present: \(hasLocalData ? "✅ Yes" : "❌ No")")
        
        // Try to fetch remote backups
        debugLog("📋 Attempting to fetch remote backups...")
        do {
            let remoteBackups = try await fetchRemoteBackups()
            debugLog("📋 Remote backups found: \(remoteBackups.count)")
            
            for backup in remoteBackups.prefix(5) {
                debugLog("  📄 \(backup.filename) - \(backup.size) bytes - \(formatDate(backup.timestamp))")
                if let userID = backup.userID {
                    debugLog("     👤 User: \(userID)")
                }
            }
            
            // Use the new multi-user backup selection
            if !remoteBackups.isEmpty {
                let bestBackup = await chooseBestBackupForMultiUser(remoteBackups)
                if let selectedBackup = bestBackup {
                    debugLog("🎯 Best backup selected: \(selectedBackup.filename)")
                    debugLog("  👤 User: \(selectedBackup.userID ?? "unknown")")
                    debugLog("  📱 Device: \(selectedBackup.deviceID)")
                    
                    let shouldDownload = await shouldDownloadConservatively(selectedBackup)
                    debugLog("📋 Should download selected backup: \(shouldDownload ? "✅ Yes" : "❌ No")")
                } else {
                    debugLog("❌ No suitable backup found after multi-user filtering")
                }
            }
            
        } catch {
            debugLog("❌ Failed to fetch remote backups: \(error)")
        }
        
        debugLog("🩺 DIAGNOSTIC SYNC COMPLETED")
    }
    
    /// Diagnostische Funktion zur Überprüfung der aktuellen Datenbank-Situation
    func performDatabaseDiagnostic() async {
        debugLog("🔍 Starting database diagnostic...")
        
        // Get current user ID
        let currentUserID = UserDefaults.standard.string(forKey: "currentUserID") ?? "unknown"
        let deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let prefixString = String(deviceUUID.prefix(8))
        let currentDeviceID = prefixString.lowercased()
        
        debugLog("🔍 Identity Check:")
        debugLog("  Current User ID: \(currentUserID)")
        debugLog("  Current Device ID: \(currentDeviceID)")
        debugLog("  Full Device UUID: \(deviceUUID)")
        
        debugLog("📋 Checking WebDAV configuration...")
        
        // Check WebDAV configuration
        let hasWebDAV = hasValidWebDAVConfiguration()
        debugLog("📋 WebDAV configuration: \(hasWebDAV ? "✅ Valid" : "❌ Invalid")")
        
        if !hasWebDAV {
            debugLog("❌ Cannot proceed without WebDAV configuration")
            return
        }
        
        // Check auto-sync status
        debugLog("📋 Auto-sync enabled: \(isAutoSyncEnabled ? "✅ Yes" : "❌ No")")
        debugLog("📋 Sync timer active: \(syncTimer != nil ? "✅ Yes" : "❌ No")")
        
        // Check last sync date
        if let lastSync = lastSyncDate {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            debugLog("📋 Last sync: \(formatDate(lastSync)) (\(Int(timeSinceLastSync))s ago)")
        } else {
            debugLog("📋 Last sync: Never")
        }
        
        // Check local data
        let hasLocalData = await checkLocalDataExists()
        debugLog("📋 Local data present: \(hasLocalData ? "✅ Yes" : "❌ No")")
        
        // Try to fetch remote backups
        debugLog("📋 Attempting to fetch remote backups...")
        do {
            let remoteBackups = try await fetchRemoteBackups()
            debugLog("📋 Remote backups found: \(remoteBackups.count)")
            
            for backup in remoteBackups.prefix(5) {
                debugLog("  📄 \(backup.filename) - \(backup.size) bytes - \(formatDate(backup.timestamp))")
                if let userID = backup.userID {
                    debugLog("     👤 User: \(userID)")
                }
            }
            
            // Use the new multi-user backup selection
            if !remoteBackups.isEmpty {
                let bestBackup = await chooseBestBackupForMultiUser(remoteBackups)
                if let selectedBackup = bestBackup {
                    debugLog("🎯 Best backup selected: \(selectedBackup.filename)")
                    debugLog("  👤 User: \(selectedBackup.userID ?? "unknown")")
                    debugLog("  📱 Device: \(selectedBackup.deviceID)")
                    
                    let shouldDownload = await shouldDownloadConservatively(selectedBackup)
                    debugLog("📋 Should download selected backup: \(shouldDownload ? "✅ Yes" : "❌ No")")
                } else {
                    debugLog("❌ No suitable backup found after multi-user filtering")
                }
            }
            
        } catch {
            debugLog("❌ Failed to fetch remote backups: \(error)")
        }
        
        debugLog("🩺 DIAGNOSTIC SYNC COMPLETED")
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
            debugLog("❌ Failed to analyze backups: \(error)")
            return []
        }
    }
    
    func restoreSpecificBackup(_ backup: BackupInfo) async {
        do {
            await MainActor.run {
                isSyncing = true
                syncStatus = .downloading
            }
            
            debugLog("🎯 Manually restoring selected backup: \(backup.filename)")
            try await downloadAndRestoreBackup(backup)
            
            await MainActor.run {
                syncStatus = .success
                lastSyncDate = Date()
                saveLastSyncDate()
            }
            
            debugLog("✅ Manual backup restore completed successfully")
            
            // Force comprehensive UI refresh on main thread after successful restore
            await MainActor.run {
                debugLog("🔄 Starting comprehensive UI refresh after restore...")
                
                // Step 1: Force context refresh to ensure all relationships are loaded
                viewModel.getContext().refreshAllObjects()
                
                // Step 2: Refresh all data components
                viewModel.fetchAccountGroups()
                viewModel.fetchCategories()
                
                // Step 3: Force balance recalculation after restore
                viewModel.objectWillChange.send()
                
                // Step 4: Add multiple delayed refreshes to ensure data is properly loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.debugLog("🔄 First delayed refresh...")
                    self.viewModel.getContext().refreshAllObjects()
                    self.viewModel.fetchAccountGroups()
                    self.viewModel.objectWillChange.send()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.debugLog("🔄 Second delayed refresh...")
                    self.viewModel.getContext().refreshAllObjects()
                    self.viewModel.fetchAccountGroups()
                    self.viewModel.objectWillChange.send()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.debugLog("🔄 Final delayed refresh...")
                    self.viewModel.getContext().refreshAllObjects()
                    self.viewModel.fetchAccountGroups()
                    self.viewModel.objectWillChange.send()
                    self.debugLog("🔄 All refresh cycles completed")
                }
                
                debugLog("🔄 Manual restore - comprehensive UI refresh completed on main thread")
            }
            
            // Add a small delay and then verify the data was properly restored
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                debugLog("🔍 Post-restore verification:")
            }
            Task {
                await self.verifyRestoredData()
            }
            
        } catch {
            debugLog("❌ Manual backup restore failed: \(error)")
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
    
    private func hasValidWebDAVConfiguration() -> Bool {
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword"),
              !webdavURL.isEmpty, !webdavUser.isEmpty, !webdavPassword.isEmpty else {
            return false
        }
        return true
    }
    
    private func performAutoSyncWithSafeguards() async {
        guard !isSyncing else {
            debugLog("⏳ Auto-sync skipped: sync already in progress")
            return
        }
        
        await MainActor.run {
            isSyncing = true
            syncStatus = .checking
        }
        
        do {
            // 1. Check local and remote data
            let localDataExists = await checkLocalDataExists()
            let remoteBackups = try await fetchRemoteBackups()
            
            await MainActor.run {
                availableBackups = remoteBackups.sorted { $0.timestamp > $1.timestamp }
            }
            
            let hasRemoteData = !remoteBackups.isEmpty
            debugLog("📊 Auto-sync state: Local=\(localDataExists ? "YES" : "NO"), Remote=\(hasRemoteData ? "YES(\(remoteBackups.count))" : "NO")")
            
            // 2. Download logic (always safe)
            if hasRemoteData, let newestRemote = remoteBackups.max(by: { $0.timestamp < $1.timestamp }) {
                if await shouldDownloadConservatively(newestRemote) {
                    await MainActor.run { syncStatus = .downloading }
                    debugLog("📥 AUTO DOWNLOAD → \(newestRemote.filename)")
                    try await downloadAndRestoreBackup(newestRemote)
                    consecutiveUploads = 0 // Reset on successful download
                }
            }
            
            // 3. Upload logic (only if local data exists and no recent uploads)
            if localDataExists && consecutiveUploads < maxConsecutiveUploads {
                let shouldUpload = await shouldUploadConservatively()
                if shouldUpload {
                    await MainActor.run { syncStatus = .uploading }
                    debugLog("📤 AUTO UPLOAD → Starting upload")
                    try await uploadCurrentState()
                    consecutiveUploads += 1
                }
            }
            
            await MainActor.run {
                syncStatus = .success
                lastSyncDate = Date()
                saveLastSyncDate()
            }
            
            debugLog("✅ Auto-sync completed successfully")
            
            // KRITISCH: SANFTER UI-Update nach Auto-Sync (ohne Fault-Erzeugung)
            await MainActor.run {
                debugLog("🔄 GENTLE UI refresh after auto-sync (no context operations)")
                
                // SANFTE UI-Updates - KEIN Context-Reset, KEINE refreshAllObjects()
                // Nur Daten neu fetchen und UI informieren
                viewModel.fetchAccountGroups()
                viewModel.fetchCategories()
                viewModel.objectWillChange.send()
                NotificationCenter.default.post(name: NSNotification.Name("DataDidChange"), object: nil)
                
                debugLog("✅ Gentle auto-sync UI refresh completed - objects should stay loaded")
            }
            
        } catch {
            debugLog("❌ Auto-sync failed: \(error)")
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
                    
                    self.debugLog("📊 Local data inventory:")
                    self.debugLog("  Account Groups: \(groups.count)")
                    self.debugLog("  Accounts: \(accounts.count)")
                    self.debugLog("  Transactions: \(transactions.count)")
                    self.debugLog("  Has meaningful data: \(hasData)")
                    
                    continuation.resume(returning: hasData)
                } catch {
                    self.debugLog("❌ Error checking local data: \(error)")
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
            debugLog("❌ WebDAV credentials missing or empty")
            debugLog("  URL: \(UserDefaults.standard.string(forKey: "webdavURL") ?? "nil")")
            debugLog("  User: \(UserDefaults.standard.string(forKey: "webdavUser") ?? "nil")")
            debugLog("  Password: \(UserDefaults.standard.string(forKey: "webdavPassword")?.isEmpty == false ? "present" : "missing")")
            throw SyncError.missingCredentials
        }
        
        // First try: Check the configured directory
        let result1 = try await fetchBackupsFromPath(webdavURL, user: webdavUser, password: webdavPassword)
        if !result1.isEmpty {
            return result1
        }
        
        debugLog("🔄 No backups found in configured path, trying alternative paths...")
        
        // Second try: Check if the URL points to a specific file, try the parent directory  
        if webdavURL.hasSuffix(".json") {
            if let url = URL(string: webdavURL) {
                let parentURL = url.deletingLastPathComponent().absoluteString
                debugLog("🔄 Trying parent directory: \(parentURL)")
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
            debugLog("🔄 Trying root WebDAV directory: \(rootWebDAV)")
            let result3 = try await fetchBackupsFromPath(rootWebDAV, user: webdavUser, password: webdavPassword)
            if !result3.isEmpty {
                return result3
            }
        }
        
        // Fourth try: Direct file check - maybe the file still exists
        debugLog("🔄 Trying direct file access to original configured file...")
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
                debugLog("❌ Invalid WebDAV URL: \(path)")
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
            debugLog("❌ Invalid server URL: \(baseURL)")
            throw SyncError.invalidURL
        }
        
        debugLog("🌐 WebDAV PROPFIND Request:")
        debugLog("  Original URL: \(path)")
        debugLog("  Server URL: \(serverURL)")
        debugLog("  User: \(user)")
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        
        // Verbesserte Timeout-Konfiguration
        request.timeoutInterval = 30.0 // 30 Sekunden Timeout
        
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
        
        // Erstelle eine URLSession mit verbesserter Konfiguration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                debugLog("❌ Invalid response type")
                throw SyncError.networkError("Invalid response type")
            }
            
            debugLog("📡 WebDAV Response:")
            debugLog("  Status Code: \(httpResponse.statusCode)")
            debugLog("  Headers: \(httpResponse.allHeaderFields)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                debugLog("  Response Body: \(responseString.prefix(500))...")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = "HTTP \(httpResponse.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                debugLog("❌ HTTP Error: \(errorMessage)")
                throw SyncError.networkError(errorMessage)
            }
            
            return try parseWebDAVResponse(data)
            
        } catch {
            debugLog("❌ Network error: \(error)")
            if let urlError = error as? URLError {
                debugLog("  URLError code: \(urlError.code)")
                debugLog("  URLError description: \(urlError.localizedDescription)")
                
                // Spezifische Behandlung für Timeout-Fehler
                if urlError.code == .timedOut {
                    debugLog("⏰ Network timeout detected - this might be a temporary issue")
                    throw SyncError.networkError("Connection timeout - please check your internet connection and try again")
                }
            }
            throw SyncError.networkError("Network error: \(error.localizedDescription)")
        }
    }
    
    private func checkDirectFileAccess(_ fileURL: String, user: String, password: String) async throws -> BackupInfo? {
        guard let url = URL(string: fileURL) else { return nil }
        
        debugLog("🔍 Direct file check: \(fileURL)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"  // Just check if file exists
        
        let authString = "\(user):\(password)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            
            debugLog("📡 Direct file response: \(httpResponse.statusCode)")
            
            if 200...299 ~= httpResponse.statusCode {
                let filename = url.lastPathComponent
                let size = Int64(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
                
                // Get last modified from headers
                            var timestamp = Date()
            if let lastModifiedString = httpResponse.value(forHTTPHeaderField: "Last-Modified") {
                timestamp = parseWebDAVDate(lastModifiedString) ?? timestamp
                }
                
                debugLog("✅ Found direct file: \(filename) (\(size) bytes)")
                
                return BackupInfo(
                    filename: filename,
                    timestamp: timestamp,
                    size: size,
                    userID: extractUserID(from: filename),
                    deviceID: extractDeviceID(from: filename)
                )
            }
            
        } catch {
            debugLog("❌ Direct file check failed: \(error)")
        }
        
        return nil
    }
    
    private func parseWebDAVResponse(_ data: Data) throws -> [BackupInfo] {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        debugLog("🔍 Parsing WebDAV XML response:")
        debugLog("📄 Full XML: \(xmlString)")
        
        var backups: [BackupInfo] = []
        
        // Split into individual <D:response> blocks
        let responseBlocks = xmlString.components(separatedBy: "<D:response")
        debugLog("📦 Found \(responseBlocks.count - 1) response blocks")
        
        for (index, block) in responseBlocks.enumerated() {
            if index == 0 { continue } // Skip the first empty block
            
            let fullBlock = "<D:response" + block
            debugLog("📋 Processing response block \(index):")
            debugLog("  Content: \(fullBlock.prefix(200))...")
            
            // Extract href (file path)
            var href: String?
            if let hrefStart = fullBlock.range(of: "<D:href>"),
               let hrefEnd = fullBlock.range(of: "</D:href>") {
                let startIndex = hrefStart.upperBound
                let endIndex = hrefEnd.lowerBound
                href = String(fullBlock[startIndex..<endIndex])
                debugLog("  📁 Found href: \(href ?? "nil")")
            }
            
            // Skip directory entries (ending with /)
            guard let filePath = href, !filePath.hasSuffix("/") else {
                debugLog("  ⏭️ Skipping directory entry: \(href ?? "nil")")
                continue
            }
            
            // Extract filename from path
            let filename = URL(string: filePath)?.lastPathComponent ?? filePath
            debugLog("  📄 Filename: \(filename)")
            
            // Only process EuroBlick backup files
            guard filename.contains("EuroBlick") && filename.hasSuffix(".json") else {
                debugLog("  ⏭️ Skipping non-backup file: \(filename)")
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
                debugLog("  📅 Date: \(dateString) -> \(lastModified?.description ?? "nil")")
            }
            
            // Extract content length
            var contentLength: Int64 = 0
            if let sizeStart = fullBlock.range(of: "<lp1:getcontentlength>") ?? fullBlock.range(of: "<D:getcontentlength>"),
               let sizeEnd = fullBlock.range(of: "</lp1:getcontentlength>") ?? fullBlock.range(of: "</D:getcontentlength>") {
                let startIndex = sizeStart.upperBound
                let endIndex = sizeEnd.lowerBound
                let sizeString = String(fullBlock[startIndex..<endIndex])
                contentLength = Int64(sizeString) ?? 0
                debugLog("  📦 Size: \(sizeString) -> \(contentLength)")
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
                debugLog("  ✅ Created backup info: \(backup.filename)")
            } else {
                debugLog("  ❌ Missing timestamp for: \(filename)")
            }
        }
        
        debugLog("🎯 Found \(backups.count) valid backup files:")
        for backup in backups {
            debugLog("  📄 \(backup.filename) - \(backup.size) bytes - \(formatDate(backup.timestamp))")
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
    
    private func shouldUploadLocalData() async -> Bool {
        // Prüfe ob kürzlich schon hochgeladen wurde
        if let lastUpload = UserDefaults.standard.object(forKey: "lastUploadDate") as? Date {
            let timeSinceLastUpload = Date().timeIntervalSince(lastUpload)
            if timeSinceLastUpload < 300 { // 5 Minuten
                debugLog("⏰ Upload skipped: recent upload (< 5 minutes ago)")
                return false
            }
        }
        // Prüfe, ob es bedeutende lokale Änderungen gibt
        let significantChanges = await hasSignificantLocalChanges()
        if !significantChanges {
            debugLog("⏭️ Upload skipped: no significant local changes detected")
            return false
        }
        return true
    }
    
    private func shouldDownloadBackupWithConflictCheck(_ remoteBackup: BackupInfo) async -> Bool {
        // Erweiterte Konfliktprüfung
        guard let lastSync = lastSyncDate else {
            return true // Erste Synchronisation
        }
        
        // Prüfe ob Remote-Backup wirklich neuer ist
        let isNewerThanLastSync = remoteBackup.timestamp > lastSync
        
        // Prüfe ob wir lokale Änderungen haben, die nicht gesichert wurden
        let hasLocalChanges = await backupManager.hasLocalChanges()
        
        if isNewerThanLastSync && hasLocalChanges {
            debugLog("⚠️ CONFLICT DETECTED: Remote backup is newer but local changes exist")
            // In diesem Fall sollte intelligent zusammengeführt werden
            return true // Momentan downloaden und auf Conflict Resolution vertrauen
        }
        
        return isNewerThanLastSync
    }
    
    private func hasSignificantLocalChanges() async -> Bool {
        // Prüfe ob es bedeutende lokale Änderungen gibt, die einen Upload rechtfertigen
        return await withCheckedContinuation { continuation in
            viewModel.getContext().perform {
                // Prüfe Transaktionen der letzten 24 Stunden
                let calendar = Calendar.current
                let dayAgo = calendar.date(byAdding: .day, value: -1, to: Date())!
                
                let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                request.predicate = NSPredicate(format: "date >= %@", dayAgo as NSDate)
                
                do {
                    let recentTransactions = try self.viewModel.getContext().fetch(request)
                    let hasRecentActivity = recentTransactions.count > 0
                    
                    self.debugLog("📊 Recent activity check: \(recentTransactions.count) transactions in last 24h")
                    continuation.resume(returning: hasRecentActivity)
                } catch {
                    self.debugLog("❌ Error checking recent activity: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private func chooseBestBackup(_ backups: [BackupInfo]) async -> BackupInfo? {
        guard !backups.isEmpty else { return nil }
        
        debugLog("🎯 Analyzing \(backups.count) available backups...")
        
        // Sort by timestamp (newest first) but also consider data richness
        let sortedBackups = backups.sorted { $0.timestamp > $1.timestamp }
        
        for backup in sortedBackups.prefix(3) { // Check top 3 newest
            debugLog("📋 Backup: \(backup.filename)")
            debugLog("  📅 Date: \(formatDate(backup.timestamp))")
            debugLog("  📦 Size: \(backup.size) bytes")
            debugLog("  👤 User: \(backup.userID ?? "unknown")")
            debugLog("  📱 Device: \(backup.deviceID)")
        }
        
        // For now, return the newest, but we could add logic to prefer larger backups
        // that might contain more data
        return sortedBackups.first
    }
    
    private func chooseBestBackupForMultiUser(_ backups: [BackupInfo]) async -> BackupInfo? {
        guard !backups.isEmpty else { return nil }
        
        debugLog("🎯 MULTI-USER: Analyzing \(backups.count) available backups for best choice...")
        
        // Bestimme aktuelle User-ID und Device-ID
        let currentUserID = UserDefaults.standard.string(forKey: "currentUserID") ?? "unknown"
        let deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let prefixString = String(deviceUUID.prefix(8))
        let currentDeviceID = prefixString.lowercased()
        
        debugLog("🔍 Current context: User=\(currentUserID), Device=\(currentDeviceID)")
        
        // Separiere Backups nach Kategorien
        var fromOtherUsers: [BackupInfo] = []
        var fromCurrentUser: [BackupInfo] = []
        var fromOtherDevices: [BackupInfo] = []
        
        for backup in backups {
            let backupUserID = backup.userID ?? "unknown"
            let backupDeviceID = backup.deviceID
            
            debugLog("📋 Analyzing backup: \(backup.filename)")
            debugLog("  👤 User: \(backupUserID)")
            debugLog("  📱 Device: \(backupDeviceID)")
            debugLog("  📦 Size: \(backup.size) bytes")
            debugLog("  📅 Date: \(formatDate(backup.timestamp))")
            
            // Skip backups from same device (prevent loops)
            if backupDeviceID == currentDeviceID {
                debugLog("  ⏭️ Skipping: same device")
                continue
            }
            
            // Kategorisiere Backup
            if backupUserID != currentUserID && backupUserID != "unknown" {
                fromOtherUsers.append(backup)
                debugLog("  ✅ Added to OTHER USERS category")
            } else if backupUserID == currentUserID {
                fromCurrentUser.append(backup)
                debugLog("  ✅ Added to CURRENT USER category")
            } else {
                fromOtherDevices.append(backup)
                debugLog("  ✅ Added to OTHER DEVICES category")
            }
        }
        
        // PRIORITÄTEN für Multi-User Synchronisation:
        // 1. Backups von anderen Usern (höchste Priorität - neue Daten!)
        // 2. Backups vom gleichen User aber anderen Geräten (neueste zuerst)
        // 3. Sonstige Backups von anderen Geräten
        
        debugLog("📊 Backup categories:")
        debugLog("  👥 From other users: \(fromOtherUsers.count)")
        debugLog("  👤 From current user: \(fromCurrentUser.count)")
        debugLog("  📱 From other devices: \(fromOtherDevices.count)")
        
        // Priorisiere Backups von anderen Usern (neueste zuerst)
        if !fromOtherUsers.isEmpty {
            let newestFromOtherUser = fromOtherUsers.sorted { $0.timestamp > $1.timestamp }.first!
            debugLog("🎯 SELECTED: Backup from other user (\(newestFromOtherUser.userID ?? "unknown"))")
            debugLog("  📄 File: \(newestFromOtherUser.filename)")
            debugLog("  📅 Date: \(formatDate(newestFromOtherUser.timestamp))")
            return newestFromOtherUser
        }
        
        // Als nächstes: Neueste Backups vom gleichen User aber anderen Geräten
        if !fromCurrentUser.isEmpty {
            let newestFromCurrentUser = fromCurrentUser.sorted { $0.timestamp > $1.timestamp }.first!
            debugLog("🎯 SELECTED: Backup from current user, different device")
            debugLog("  📄 File: \(newestFromCurrentUser.filename)")
            debugLog("  📅 Date: \(formatDate(newestFromCurrentUser.timestamp))")
            return newestFromCurrentUser
        }
        
        // Als letztes: Sonstige Backups von anderen Geräten
        if !fromOtherDevices.isEmpty {
            let newestFromOtherDevice = fromOtherDevices.sorted { $0.timestamp > $1.timestamp }.first!
            debugLog("🎯 SELECTED: Backup from other device")
            debugLog("  📄 File: \(newestFromOtherDevice.filename)")
            debugLog("  📅 Date: \(formatDate(newestFromOtherDevice.timestamp))")
            return newestFromOtherDevice
        }
        
        debugLog("❌ No suitable backup found after filtering")
        return nil
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
        
        debugLog("📥 Downloading backup from: \(fileURL.absoluteString)")
        
        var request = URLRequest(url: fileURL)
        request.httpMethod = "GET"
        
        let authString = "\(webdavUser):\(webdavPassword)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("❌ Invalid response type")
            throw SyncError.networkError("Invalid response type")
        }
        
        debugLog("📡 Download response:")
        debugLog("  Status Code: \(httpResponse.statusCode)")
        debugLog("  Content Length: \(data.count) bytes")
        
        guard 200...299 ~= httpResponse.statusCode else {
            let errorMessage = "HTTP \(httpResponse.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
            debugLog("❌ Download failed: \(errorMessage)")
            throw SyncError.networkError("Failed to download backup: \(errorMessage)")
        }
        
        debugLog("✅ Successfully downloaded \(data.count) bytes")
        
        // Save to temporary file and restore
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(backupInfo.filename)
        try data.write(to: tempURL)
        
        debugLog("📄 Temporary file created at: \(tempURL.path)")
        
        await MainActor.run {
            syncStatus = .syncing
        }
        
        // Restore using multi-user sync manager for conflict resolution
        debugLog("🔄 Starting restore with conflict resolution...")
        let success: Bool = await multiUserSyncManager.restoreWithConflictResolution(from: tempURL, viewModel: viewModel)
        
        if !success {
            debugLog("❌ Restore with conflict resolution failed")
            throw SyncError.restoreError("Failed to restore backup with conflict resolution")
        }
        
        debugLog("✅ Backup successfully restored!")
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
        
        // After successful restore
        refreshUIAfterSync()
    }
    
    public func uploadCurrentState() async throws {
        guard let backup = await backupManager.createEnhancedBackup() else {
            throw SyncError.restoreError("Failed to create backup data")
        }
        
        debugLog("📤 Starting upload with tracking...")
        try await backupManager.uploadBackup(backup)
        
        // Speichere Upload-Zeitstempel um redundante Uploads zu verhindern
        UserDefaults.standard.set(Date(), forKey: "lastUploadDate")
        debugLog("✅ Upload completed and timestamp saved")
        
        // After successful upload
        refreshUIAfterSync()
    }
    
    private func loadLastSyncDate() {
        if let timestamp = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date {
            lastSyncDate = timestamp
        }
    }
    
    private func saveLastSyncDate() {
        UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
    }
    
    func enableAutoSyncIfConfigured() {
        let autoSyncEnabled = UserDefaults.standard.bool(forKey: "autoSyncEnabled")
        if autoSyncEnabled && hasValidWebDAVConfiguration() {
            debugLog("✅ Auto-sync is enabled and configured - starting auto-sync")
            startAutoSync()
            // Setze Sync-Status auf bereit/grün, wenn WebDAV erreichbar
            if hasValidWebDAVConfiguration() {
                syncStatus = .success
            }
        } else if autoSyncEnabled {
            debugLog("⚠️ Auto-sync is enabled but WebDAV configuration is incomplete")
            syncStatus = .error("WebDAV-Konfiguration unvollständig")
        } else {
            debugLog("ℹ️ Auto-sync is disabled by user")
            syncStatus = .idle
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Task {
                await self.forceCoreDataRefresh()
            }
        }
    }
    
    /// Force-Load aller Core Data Objekte beim App-Start
    private func forceCoreDataRefresh() async {
        debugLog("🔄 NON-FAULT Core Data refresh on app start")
        
        // KRITISCH: Fetch mit returnsObjectsAsFaults = false
        // Das lädt alle Eigenschaften direkt und vermeidet Faults
        viewModel.getContext().performAndWait {
            let entities = ["AccountGroup", "Account", "Transaction", "Category"]
            
            for entityName in entities {
                let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                fetchRequest.returnsObjectsAsFaults = false
                fetchRequest.includesPropertyValues = true
                fetchRequest.includesSubentities = true
                // KRITISCH: Force alle Eigenschaften zu laden
                fetchRequest.relationshipKeyPathsForPrefetching = []
                
                do {
                    let objects = try viewModel.getContext().fetch(fetchRequest)
                    debugLog("🔄 NON-FAULT loaded \(objects.count) \(entityName) objects")
                    
                    // Verifiziere dass Namen geladen sind (nur für AccountGroup und Account)
                    if entityName == "AccountGroup" || entityName == "Account" {
                        for (index, object) in objects.prefix(3).enumerated() {
                            if let name = object.value(forKey: "name") as? String {
                                debugLog("  ✅ Object \(index + 1): \(name)")
                            } else {
                                debugLog("  ❌ Object \(index + 1): NO NAME")
                            }
                        }
                    }
                } catch {
                    debugLog("❌ Error non-fault loading \(entityName): \(error)")
                }
            }
        }
        
        // UI-Refresh nach Force-Load mit mehreren Versuchen
        for attempt in 1...3 {
            debugLog("🔄 UI refresh attempt \(attempt)")
            viewModel.fetchAccountGroups()
            viewModel.fetchCategories()
            viewModel.objectWillChange.send()
            
            // Kurze Pause zwischen Versuchen
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 Sekunden
            }
        }
        
        // Zusätzlich: Force balance recalculation
        debugLog("🔄 Force balance recalculation")
        let _ = viewModel.calculateAllBalances()
        
        debugLog("✅ Non-fault Core Data refresh completed")
    }
    
    func setAutoSyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "autoSyncEnabled")
        
        if enabled {
            enableAutoSyncIfConfigured()
        } else {
            stopAutoSync()
        }
    }
    
    var isAutoSyncEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "autoSyncEnabled")
    }
    
    func forceRestoreFromJSON(_ jsonString: String) async -> Bool {
        debugLog("🔧 FORCE RESTORE FROM PROVIDED JSON STARTED")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            debugLog("❌ Failed to convert JSON string to data")
            return false
        }
        
        do {
            // Validate JSON format
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let json = jsonObject else {
                debugLog("❌ Invalid JSON format")
                return false
            }
            
            // Log backup info
            if let version = json["version"] as? String {
                debugLog("📋 Backup version: \(version)")
            }
            if let userID = json["userID"] as? String {
                debugLog("👤 User ID: \(userID)")
            }
            if let deviceName = json["deviceName"] as? String {
                debugLog("📱 Device: \(deviceName)")
            }
            if let timestamp = json["timestamp"] as? Double {
                let date = Date(timeIntervalSinceReferenceDate: timestamp)
                debugLog("📅 Backup date: \(formatDate(date))")
            }
            if let transactions = json["transactions"] as? [[String: Any]] {
                debugLog("💰 Transactions: \(transactions.count)")
            }
            
            // Create temporary file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("force_restore_\(UUID().uuidString).json")
            try jsonData.write(to: tempURL)
            debugLog("📄 Created temporary file: \(tempURL.path)")
            
            await MainActor.run {
                isSyncing = true
                syncStatus = .syncing
            }
            
            // Stop auto-sync temporarily
            let wasAutoSyncRunning = syncTimer != nil
            stopAutoSync()
            
            // Restore using multi-user sync manager
            debugLog("🔄 Starting force restore with conflict resolution...")
            let success: Bool = await multiUserSyncManager.restoreWithConflictResolution(from: tempURL, viewModel: viewModel)
            
            if success {
                debugLog("✅ Force restore completed successfully!")
                
                // Update sync date
                await MainActor.run {
                    lastSyncDate = Date()
                    saveLastSyncDate()
                    syncStatus = .success
                }
                
                // Refresh UI
                await MainActor.run {
                    viewModel.fetchAccountGroups()
                    viewModel.fetchCategories()
                    debugLog("🔄 UI refreshed after force restore")
                }
                
                // Restart auto-sync if it was running
                if wasAutoSyncRunning {
                    enableAutoSyncIfConfigured()
                }
                
            } else {
                debugLog("❌ Force restore failed")
                await MainActor.run {
                    syncStatus = .error("Force restore failed")
                }
            }
            
            // Clean up
            try? FileManager.default.removeItem(at: tempURL)
            debugLog("🗑️ Cleaned up temporary file")
            
            await MainActor.run {
                isSyncing = false
            }
            
            return success
            
        } catch {
            debugLog("❌ Force restore error: \(error)")
            await MainActor.run {
                isSyncing = false
                syncStatus = .error("Force restore error: \(error.localizedDescription)")
            }
            return false
        }
    }
    
    private func shouldUploadConservatively() async -> Bool {
        // SEHR KONSERVATIVE Upload-Prüfung
        
        // 1. Prüfe ob kürzlich schon hochgeladen wurde (mindestens 1 Minute)
        if let lastUpload = UserDefaults.standard.object(forKey: "lastUploadDate") as? Date {
            let timeSinceLastUpload = Date().timeIntervalSince(lastUpload)
            if timeSinceLastUpload < 60 { // 1 Minute
                debugLog("⏰ Conservative upload blocked: recent upload (\(Int(timeSinceLastUpload))s ago)")
                return false
            }
        }
        
        // 2. Prüfe auf echte Datenänderungen (nicht nur Hash-Unterschiede)
        let hasRealChanges = await hasRealDataChanges()
        if !hasRealChanges {
            debugLog("📊 Conservative upload blocked: no real data changes detected")
            return false
        }
        
        // 3. Prüfe auf zu viele aufeinanderfolgende Uploads
        if consecutiveUploads >= maxConsecutiveUploads {
            debugLog("🚫 Conservative upload blocked: too many consecutive uploads")
            return false
        }
        
        debugLog("✅ Conservative upload approved: all safety checks passed")
        return true
    }
    
    private func shouldDownloadConservatively(_ remoteBackup: BackupInfo) async -> Bool {
        // INTELLIGENTE Multi-User Download-Prüfung
        
        // 1. Erstmaliger Sync ist immer erlaubt
        guard let lastSync = lastSyncDate else {
            debugLog("✅ Conservative download approved: first sync")
            return true
        }
        
        // 2. Prüfe ob das Backup von einem anderen Gerät/User stammt
        let deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let prefixString = String(deviceUUID.prefix(8))
        let currentDeviceID = prefixString.lowercased()
        
        // Bestimme aktuelle User-ID
        let currentUserID = UserDefaults.standard.string(forKey: "currentUserID") ?? "unknown"
        let backupUserID = remoteBackup.userID ?? "unknown"
        
        debugLog("🔍 Backup analysis:")
        debugLog("  Current User: \(currentUserID)")
        debugLog("  Backup User: \(backupUserID)")
        debugLog("  Current Device: \(currentDeviceID)")
        debugLog("  Backup Device: \(remoteBackup.deviceID)")
        
        // 3. Skip backups from same device (avoid loops)
        if remoteBackup.deviceID == currentDeviceID {
            debugLog("📱 Conservative download skipped: backup from same device")
            return false
        }
        
        // 4. WICHTIG: Backups von anderen Usern IMMER prioritisieren
        if backupUserID != currentUserID && backupUserID != "unknown" {
            debugLog("👥 Conservative download APPROVED: backup from different user (\(backupUserID))")
            return true
        }
        
        // 5. Für Backups vom gleichen User - prüfe ob es signifikant neuer ist
        let timeDifference = remoteBackup.timestamp.timeIntervalSince(lastSync)
        if timeDifference < 60 { // 1 Minute minimum
            debugLog("⏰ Conservative download skipped: backup not significantly newer (\(Int(timeDifference))s)")
            return false
        }
        
        // 6. Prüfe ob das Backup größer ist (mehr Daten)
        let localDataSize = await getLocalDataSize()
        if remoteBackup.size <= localDataSize {
            debugLog("📊 Conservative download skipped: remote backup not larger than local data")
            return false
        }
        
        debugLog("✅ Conservative download approved: backup is newer and larger")
        return true
    }
    
    private func getLocalDataSize() async -> Int64 {
        return await withCheckedContinuation { continuation in
            viewModel.getContext().perform {
                let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                do {
                    let count = try self.viewModel.getContext().count(for: request)
                    continuation.resume(returning: Int64(count))
                } catch {
                    self.debugLog("❌ Error counting local transactions: \(error)")
                    continuation.resume(returning: 0)
                }
            }
        }
    }
    
    private func hasRealDataChanges() async -> Bool {
        // Prüfe auf echte Datenänderungen, nicht nur Hash-Unterschiede
        return await withCheckedContinuation { continuation in
            viewModel.getContext().perform {
                // Prüfe auf neue Transaktionen in den letzten 24 Stunden (statt 2 Stunden)
                let twentyFourHoursAgo = Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
                
                let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                request.predicate = NSPredicate(format: "date >= %@", twentyFourHoursAgo as NSDate)
                
                do {
                    let recentTransactions = try self.viewModel.getContext().fetch(request)
                    let hasRecentChanges = recentTransactions.count > 0
                    
                    // Zusätzlich prüfe auf Änderungen in den letzten 7 Tagen für konservativere Erkennung
                    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                    let request7Days: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                    request7Days.predicate = NSPredicate(format: "date >= %@", sevenDaysAgo as NSDate)
                    let weekTransactions = try self.viewModel.getContext().fetch(request7Days)
                    
                    // Erlaube Upload wenn es Änderungen in 24h gibt ODER wenn es mehr als 10 Transaktionen in der Woche gibt
                    let shouldAllowUpload = hasRecentChanges || weekTransactions.count > 10
                    
                    self.debugLog("📊 Real data changes check: \(recentTransactions.count) transactions in last 24h, \(weekTransactions.count) in last 7 days")
                    self.debugLog("📊 Upload decision: \(shouldAllowUpload ? "ALLOWED" : "BLOCKED")")
                    
                    continuation.resume(returning: shouldAllowUpload)
                } catch {
                    self.debugLog("❌ Error checking real data changes: \(error)")
                    // Bei Fehlern erlaube Upload für Sicherheit
                    continuation.resume(returning: true)
                }
            }
        }
    }
    
    /// Reset der Upload-Zähler für Notfälle
    func resetUploadCounter() {
        consecutiveUploads = 0
        debugLog("🔄 Upload counter reset to 0")
    }
    
    /// Force Upload - umgeht alle Sicherheitsprüfungen
    func forceUpload() async {
        debugLog("🚀 FORCE UPLOAD: Bypassing all safety checks")
        
        // Reset Upload-Zähler
        consecutiveUploads = 0
        
        // Entferne Upload-Zeitstempel
        UserDefaults.standard.removeObject(forKey: "lastUploadDate")
        
        // Führe Upload durch
        await performManualSync(allowUpload: true)
    }
    
    /// DEBUG-Tool für Benutzer: UI-Problem fixen
    @MainActor
    func fixUIDisplayProblem() async {
        debugLog("🔧 USER TOOL: Fixing UI display problem with GENTLE strategy...")
        
        // NEUE STRATEGIE: Versuche ZUERST ohne Context-Reset
        debugLog("🔧 Phase 1: Gentle refresh attempt...")
        
        // 1. Fetch Daten neu OHNE Context-Reset
        viewModel.fetchAccountGroups()
        viewModel.fetchCategories()
        
        // 2. UI-Update
        viewModel.objectWillChange.send()
        NotificationCenter.default.post(name: NSNotification.Name("DataDidChange"), object: nil)
        
        // 3. Warte und prüfe ob das gereicht hat
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        
        // 4. Nur wenn immer noch Probleme - dann Context-Reset
        let stillHasProblems = await checkForUIFaults()
        if stillHasProblems {
            debugLog("🔧 Phase 2: Gentle refresh didn't work, using context reset...")
            
            // Sanfter Context-Reset
            viewModel.getContext().reset()
            
            // Force reload aller Objekte
            await forceCoreDataRefresh()
            
            // Zusätzliche UI-Updates
            viewModel.objectWillChange.send()
            NotificationCenter.default.post(name: NSNotification.Name("DataDidChange"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("TransactionDataChanged"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("BalanceDataChanged"), object: nil)
            
            // Finale Verifikation
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            let finalCheck = await checkForUIFaults()
            if finalCheck {
                debugLog("🔧 Phase 3: Context reset didn't work, using nuclear option...")
                await forceCompleteUIRefresh()
            }
        }
        
        debugLog("🔧 USER TOOL: GENTLE UI fix completed")
    }
    
    /// Prüft ob noch UI-Faults vorhanden sind
    private func checkForUIFaults() async -> Bool {
        // Einfache Prüfung: Sind alle Gruppen-Namen verfügbar?
        let groupNames = viewModel.accountGroups.compactMap { $0.name }
        let hasEmptyNames = groupNames.contains { $0.isEmpty }
        return hasEmptyNames || groupNames.count < viewModel.accountGroups.count
    }
    
    /// Manueller SUPER UI-Refresh für Notfälle
    @MainActor
    func forceCompleteUIRefresh() async {
        debugLog("🔧 FORCE COMPLETE UI REFRESH STARTED - THIS IS THE NUCLEAR OPTION")
        
        // 1. Comprehensive context reset
        debugLog("🔄 Phase 1: Context reset")
        viewModel.getContext().reset()
        viewModel.getBackgroundContext().reset()
        
        // 2. Force refresh all contexts
        debugLog("🔄 Phase 2: Refreshing all objects")
        viewModel.getContext().refreshAllObjects()
        
        // 3. Multiple data fetches
        debugLog("🔄 Phase 3: Multiple data fetches")
        for i in 1...3 {
            viewModel.fetchAccountGroups()
            viewModel.fetchCategories()
            debugLog("🔄 Data fetch round \(i) completed")
        }
        
        // 3.5. CRITICAL: Force balance recalculation 
        debugLog("🔄 Phase 3.5: Force balance recalculation")
        let _ = viewModel.calculateAllBalances()
        
        // 4. Force UI updates
        debugLog("🔄 Phase 4: UI notifications")
        viewModel.objectWillChange.send()
        NotificationCenter.default.post(name: NSNotification.Name("DataDidChange"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("TransactionDataChanged"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("BalanceDataChanged"), object: nil)
        
        // 5. Additional delayed refreshes with balance recalculation
        debugLog("🔄 Phase 5: Delayed refreshes")
        for i in 1...5 {
            let delay = Double(i) * 0.2 // 0.2, 0.4, 0.6, 0.8, 1.0 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.viewModel.fetchAccountGroups()
                self.viewModel.fetchCategories()
                
                // Force balance recalculation in each wave
                let _ = self.viewModel.calculateAllBalances()
                
                self.viewModel.objectWillChange.send()
                NotificationCenter.default.post(name: NSNotification.Name("DataDidChange"), object: nil)
                NotificationCenter.default.post(name: NSNotification.Name("BalanceDataChanged"), object: nil)
                self.debugLog("🔄 Delayed refresh wave \(i) completed with balance recalc")
            }
        }
        
        // 6. Final verification after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Task {
                await self.debugCurrentDatabaseState()
                self.debugLog("🔧 FORCE COMPLETE UI REFRESH COMPLETED - Check if data is now visible")
            }
        }
    }
    
    /// Zeigt den aktuellen Zustand der Datenbank für Debugging
    @MainActor
    func debugCurrentDatabaseState() async {
        debugLog("🔍 DATABASE STATE DIAGNOSTIC:")
        
        await withCheckedContinuation { continuation in
            viewModel.getContext().perform {
                // Check each entity type
                let entities = ["AccountGroup", "Account", "Transaction", "Category"]
                
                for entityName in entities {
                    let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                    do {
                        let objects = try self.viewModel.getContext().fetch(fetchRequest)
                        self.debugLog("📊 \(entityName): \(objects.count) objects")
                        
                        // Show details for first few objects
                        for (index, object) in objects.prefix(3).enumerated() {
                            if entityName == "Transaction" {
                                // Transaction has different attributes
                                if let type = object.value(forKey: "type") as? String,
                                   let amount = object.value(forKey: "amount") as? Double {
                                    self.debugLog("  \(index + 1). Transaction: \(type) \(amount)€")
                                } else {
                                    self.debugLog("  \(index + 1). Transaction object")
                                }
                            } else {
                                // Other entities have name attribute
                                if let name = object.value(forKey: "name") as? String {
                                    self.debugLog("  \(index + 1). \(name)")
                                } else {
                                    self.debugLog("  \(index + 1). Object without name")
                                }
                            }
                        }
                    } catch {
                        self.debugLog("❌ Error fetching \(entityName): \(error)")
                    }
                }
                
                // Check viewModel state
                DispatchQueue.main.async {
                    self.debugLog("📊 ViewModel state:")
                    self.debugLog("  Account Groups: \(self.viewModel.accountGroups.count)")
                    self.debugLog("  Categories: \(self.viewModel.categories.count)")
                    
                    for (index, group) in self.viewModel.accountGroups.prefix(3).enumerated() {
                        self.debugLog("  Group \(index + 1): \(group.name ?? "unnamed")")
                    }
                    
                    // CRITICAL: Force balance calculation to show current state
                    self.debugLog("🔄 Forcing balance recalculation for diagnostic...")
                    let balanceDict = self.viewModel.calculateAllBalances()
                    self.debugLog("📊 Current Balance Dictionary has \(balanceDict.count) entries")
                    
                    // Show balances for first few accounts
                    let accountGroups = self.viewModel.accountGroups
                    for group in accountGroups.prefix(2) {
                        let accounts = (group.accounts?.allObjects as? [Account]) ?? []
                        for account in accounts.prefix(2) {
                            let balance = self.viewModel.getBalance(for: account)
                            self.debugLog("  💰 \(account.name ?? "unnamed"): \(balance)€")
                        }
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    /// Verifiziert die wiederhergestellten Daten nach einer Backup-Wiederherstellung
    private func verifyRestoredData() async {
        debugLog("🔍 Verifying restored data...")
        
        // 1. Hole alle Kontogruppen
        let accountGroups = viewModel.accountGroups
        debugLog("📊 Verification - Account Groups: \(accountGroups.count)")
        
        // 2. Prüfe jede Gruppe und ihre Konten
        for group in accountGroups {
            debugLog("  📁 Group '\(group.name ?? "unnamed")': \(group.accounts?.count ?? 0) accounts")
            
            // 3. Prüfe jedes Konto
            for account in group.accounts?.allObjects as? [Account] ?? [] {
                debugLog("    💳 Account '\(account.name ?? "unnamed")'")
                
                // 4. Hole alle Transaktionen für das Konto
                let transactions = account.transactions?.allObjects as? [Transaction] ?? []
                debugLog("      💰 Transactions: \(transactions.count)")
                
                // 5. Zeige Details für jede Transaktion
                for (index, transaction) in transactions.enumerated() {
                    debugLog("        🔍 Transaction \(index + 1):")
                    debugLog("          💰 Amount: \(transaction.amount)")
                    debugLog("          📝 Type: '\(transaction.type ?? "unknown")'")
                    debugLog("          🏦 Account: '\(transaction.account?.name ?? "unknown")'")
                    debugLog("          🎯 Target: '\(transaction.targetAccount?.name ?? "nil")'")
                    debugLog("          📅 Date: \(transaction.date.description)")
                    debugLog("          📋 Usage: '\(transaction.usage ?? "")'")
                }
                
                // 6. Berechne und zeige den Kontostand
                var balance: Double = 0
                for transaction in transactions {
                    if transaction.type == "einnahme" {
                        balance += transaction.amount
                        debugLog("        ➕ Adding income: \(transaction.amount)")
                    } else if transaction.type == "ausgabe" {
                        balance -= transaction.amount
                        debugLog("        ➖ Subtracting expense: \(transaction.amount)")
                    }
                }
                debugLog("      💵 Calculated balance: \(balance)")
            }
        }
        
        // 7. Hole und zeige alle Kategorien
        let categories = viewModel.categories
        debugLog("📊 Verification - Categories: \(categories.count)")
        
        // 8. Zeige Gesamtzahl der Transaktionen
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        do {
            let allTransactions = try viewModel.getContext().fetch(fetchRequest)
            debugLog("📊 Verification - Total Transactions: \(allTransactions.count)")
        } catch {
            debugLog("❌ Error fetching transactions: \(error)")
        }
        
        debugLog("✅ Verification completed")
    }
    
    private func refreshUIAfterSync() {
        debugLog("🔄 Starting GENTLE UI refresh after data sync...")
        
        // KRITISCH: SANFTER UI-Refresh OHNE Context-Reset
        // Context-Reset nur bei echten Restore-Operationen, nicht bei normalen Syncs
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // 1. Fetch neue Daten OHNE Context-Reset
            self.viewModel.fetchAccountGroups()
            self.viewModel.fetchCategories()
        
            // 2. UI-Update
            self.viewModel.objectWillChange.send()
            NotificationCenter.default.post(name: NSNotification.Name("DataDidChange"), object: nil)
            
            self.debugLog("🔄 GENTLE UI refresh completed - no faults created")
        }
    }
    
    /// Einmalige UI-State Verifikation ohne Endlosschleife
    private func verifyUIState() async {
        // Verhindere mehrfache gleichzeitige Ausführung
        guard !UserDefaults.standard.bool(forKey: "verificationRunning") else {
            debugLog("⏭️ UI verification skipped - already running")
            return
        }
        
        UserDefaults.standard.set(true, forKey: "verificationRunning")
        defer { UserDefaults.standard.set(false, forKey: "verificationRunning") }
        
        await MainActor.run {
            debugLog("🔍 SINGLE UI STATE VERIFICATION:")
            debugLog("📊 ViewModel Account Groups: \(viewModel.accountGroups.count)")
            
            for (index, group) in viewModel.accountGroups.enumerated() {
                let groupName = group.name ?? "unnamed"
                let accountCount = group.accounts?.count ?? 0
                debugLog("  📁 Group \(index + 1): \(groupName) (\(accountCount) accounts)")
        
                // Kurze Account-Verifikation
                if let accounts = group.accounts?.allObjects as? [Account] {
                    for (accountIndex, account) in accounts.prefix(1).enumerated() {
                        let accountName = account.name ?? "unnamed"
                        let balance = viewModel.getBalance(for: account)
                        debugLog("    💳 Account \(accountIndex + 1): \(accountName) = \(balance)€")
                    }
                    if accounts.count > 1 {
                        debugLog("    💳 ... and \(accounts.count - 1) more accounts")
                    }
            }
        }
        
            debugLog("✅ Single UI State verification completed")
        }
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
    
    static let shared = SynologyBackupSyncService(viewModel: TransactionViewModel.shared)
    
    /// Einfache Backup-Erstellung
    func createBackup() async throws {
        debugLog("📦 Erstelle neues Backup...")
        
        // Lösche alte Backups vor der Erstellung eines neuen Backups
        await cleanupOldBackups()
        
        let backupData = try await exportCurrentData()
        let timestamp = Date()
        let filename = "EuroBlick_Backup_\(formatDateForFilename(timestamp)).json"
        try await uploadBackupToSynology(backupData: backupData, filename: filename)
        debugLog("✅ Backup erfolgreich erstellt: \(filename)")
        await fetchAvailableBackups()
    }
    
    /// Löscht automatisch Backups, die älter als 1 Tag sind
    private func cleanupOldBackups() async {
        debugLog("🧹 Starte automatische Bereinigung alter Backups...")
        let calendar = Calendar.current
        do {
            let allBackups = try await fetchRemoteBackups()
            let oldBackups = allBackups.filter { backup in
                !calendar.isDateInToday(backup.timestamp)
            }
            debugLog("📊 Gefundene Backups: \(allBackups.count)")
            debugLog("🗑️ Zu löschende alte Backups: \(oldBackups.count)")
            for backup in oldBackups {
                do {
                    try await deleteBackup(backup)
                    debugLog("✅ Altes Backup gelöscht: \(backup.filename)")
                } catch {
                    debugLog("❌ Fehler beim Löschen von \(backup.filename): \(error)")
                }
            }
            if oldBackups.isEmpty {
                debugLog("✅ Keine alten Backups zum Löschen gefunden")
            } else {
                debugLog("✅ Bereinigung abgeschlossen: \(oldBackups.count) alte Backups gelöscht")
            }
        } catch {
            debugLog("❌ Fehler bei der Backup-Bereinigung: \(error)")
        }
    }
    
    /// Löscht eine spezifische Backup-Datei vom Synology Drive
    private func deleteBackup(_ backup: BackupInfo) async throws {
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") else {
            throw SyncError.networkError("WebDAV-Konfiguration fehlt")
        }
        
        // Konstruiere die vollständige URL für die zu löschende Datei
        let baseURL: String
        if webdavURL.hasSuffix(".json") {
            // URL zeigt auf eine spezifische Datei, verwende das Verzeichnis
            guard let url = URL(string: webdavURL) else {
                throw SyncError.invalidURL
            }
            baseURL = url.deletingLastPathComponent().absoluteString
        } else {
            // URL ist ein Verzeichnis, verwende es direkt
            baseURL = webdavURL
        }
        
        let fileURL = URL(string: baseURL)!.appendingPathComponent(backup.filename)
        
        var request = URLRequest(url: fileURL)
        request.httpMethod = "DELETE"
        
        let authString = "\(webdavUser):\(webdavPassword)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError("Ungültige Antwort beim Löschen")
        }
        
        // WebDAV DELETE sollte 204 (No Content) oder 200 (OK) zurückgeben
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            throw SyncError.networkError("Löschen fehlgeschlagen: HTTP \(httpResponse.statusCode)")
        }
    }
    
    /// Backup wiederherstellen
    func restoreBackup(_ backup: BackupInfo) async throws {
        debugLog("🔄 Wiederherstellung von Backup: \(backup.filename)")
        try await downloadAndRestoreBackup(backup)
        debugLog("✅ Backup erfolgreich wiederhergestellt: \(backup.filename)")
    }
    /// Verfügbare Backups abrufen
    func fetchAvailableBackups() async {
        do {
            let backups = try await fetchRemoteBackups()
            await MainActor.run {
                self.availableBackups = backups.sorted { $0.timestamp > $1.timestamp }
            }
            debugLog("📋 Verfügbare Backups aktualisiert: \(backups.count)")
        } catch {
            debugLog("❌ Fehler beim Laden der Backups: \(error)")
        }
    }
    /// Hilfsfunktion für Dateinamen
    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
    /// Exportiert aktuelle Daten als JSON
    private func exportCurrentData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            viewModel.getContext().performAndWait {
                do {
                    let exportData = ExportData(
                        version: "2.0",
                        userID: self.userID,
                        deviceName: UIDevice.current.name,
                        timestamp: Date().timeIntervalSince1970,
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                        deviceID: self.deviceID,
                        accountGroups: self.fetchAccountGroupsForExport(),
                        accounts: self.fetchAccountsForExport(),
                        transactions: self.fetchTransactionsForExport(),
                        categories: self.fetchCategoriesForExport()
                    )
                    let data = try JSONEncoder().encode(exportData)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Data Fetching for Export
    
    private func fetchAccountGroupsForExport() -> [AccountGroupExport] {
        let request: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
        
        do {
            let accountGroups = try viewModel.getContext().fetch(request)
            return accountGroups.map { group in
                AccountGroupExport(
                    id: group.id ?? UUID(),
                    name: group.name ?? "",
                    color: "#000000", // Standardfarbe
                    icon: "folder", // Standardicon
                    order: 0 // Standardreihenfolge
                )
            }
        } catch {
            debugLog("❌ Fehler beim Exportieren der Kontogruppen: \(error)")
            return []
        }
    }
    
    private func fetchAccountsForExport() -> [AccountExport] {
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        
        do {
            let accounts = try viewModel.getContext().fetch(request)
            return accounts.map { account in
                AccountExport(
                    id: account.id ?? UUID(),
                    name: account.name ?? "",
                    balance: 0.0, // Balance wird aus Transaktionen berechnet
                    accountGroupID: account.group?.id ?? UUID(),
                    icon: "wallet.pass", // Standardicon
                    iconColor: "#000000", // Standardfarbe
                    order: 0 // Standardreihenfolge
                )
            }
        } catch {
            debugLog("❌ Fehler beim Exportieren der Konten: \(error)")
            return []
        }
    }
    
    private func fetchTransactionsForExport() -> [TransactionExport] {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        
        do {
            let transactions = try viewModel.getContext().fetch(request)
            return transactions.map { transaction in
                TransactionExport(
                    id: transaction.id,
                    amount: transaction.amount,
                    date: transaction.date,
                    note: transaction.usage ?? "",
                    accountID: transaction.account?.id ?? UUID(),
                    categoryID: UUID(), // Neue UUID für Category, da Category keine ID hat
                    type: transaction.type ?? "expense"
                )
            }
        } catch {
            debugLog("❌ Fehler beim Exportieren der Transaktionen: \(error)")
            return []
        }
    }
    
    private func fetchCategoriesForExport() -> [CategoryExport] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        
        do {
            let categories = try viewModel.getContext().fetch(request)
            return categories.map { category in
                CategoryExport(
                    id: UUID(), // Neue UUID für Category
                    name: category.name ?? "",
                    color: "#000000", // Standardfarbe
                    icon: "tag", // Standardicon
                    order: 0 // Standardreihenfolge
                )
            }
        } catch {
            debugLog("❌ Fehler beim Exportieren der Kategorien: \(error)")
            return []
        }
    }
    
    // MARK: - Data Importing
    
    private func importAccountGroups(_ accountGroups: [AccountGroupExport]) {
        for groupData in accountGroups {
            let group = AccountGroup(context: viewModel.getContext())
            group.id = groupData.id
            group.name = groupData.name
        }
    }
    
    private func importAccounts(_ accounts: [AccountExport]) {
        for accountData in accounts {
            let account = Account(context: viewModel.getContext())
            account.id = accountData.id
            account.name = accountData.name
            
            // AccountGroup verknüpfen
            let groupRequest: NSFetchRequest<AccountGroup> = AccountGroup.fetchRequest()
            groupRequest.predicate = NSPredicate(format: "id == %@", accountData.accountGroupID as CVarArg)
            if let group = try? viewModel.getContext().fetch(groupRequest).first {
                account.group = group
            }
        }
    }
    
    private func importCategories(_ categories: [CategoryExport]) {
        for categoryData in categories {
            let category = Category(context: viewModel.getContext())
            category.name = categoryData.name
        }
    }
    
    private func importTransactions(_ transactions: [TransactionExport]) {
        for transactionData in transactions {
            let transaction = Transaction(context: viewModel.getContext())
            transaction.id = transactionData.id
            transaction.amount = transactionData.amount
            transaction.date = transactionData.date
            transaction.usage = transactionData.note
            transaction.type = transactionData.type
            
            // Account verknüpfen
            let accountRequest: NSFetchRequest<Account> = Account.fetchRequest()
            accountRequest.predicate = NSPredicate(format: "id == %@", transactionData.accountID as CVarArg)
            if let account = try? viewModel.getContext().fetch(accountRequest).first {
                transaction.account = account
            }
            
            // Category verknüpfen
            let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
            categoryRequest.predicate = NSPredicate(format: "name == %@", transactionData.note)
            if let category = try? viewModel.getContext().fetch(categoryRequest).first {
                transaction.categoryRelationship = category
            }
        }
    }
    
    private func uploadBackupToSynology(backupData: Data, filename: String) async throws {
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") else {
            throw SyncError.networkError("WebDAV-Konfiguration fehlt")
        }
        let url = URL(string: webdavURL)!.appendingPathComponent(filename)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = backupData
        let authString = "\(webdavUser):\(webdavPassword)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            throw SyncError.networkError("Upload fehlgeschlagen")
        }
    }
    
    /// Manuelle Bereinigung alter Backups (öffentliche Funktion für UI)
    func cleanupOldBackupsManually() async -> (deletedCount: Int, errorCount: Int) {
        debugLog("🧹 Manuelle Bereinigung alter Backups gestartet...")
        let calendar = Calendar.current
        var deletedCount = 0
        var errorCount = 0
        do {
            let allBackups = try await fetchRemoteBackups()
            
            // Sortiere Backups nach Datum (neueste zuerst)
            let sortedBackups = allBackups.sorted { $0.timestamp > $1.timestamp }
            
            // Das neueste Backup darf NIE gelöscht werden
            let backupsToCheck = sortedBackups.dropFirst() // Alle außer dem neuesten
            
            let oldBackups = backupsToCheck.filter { backup in
                !calendar.isDateInToday(backup.timestamp)
            }
            
            debugLog("📊 Gefundene Backups: \(allBackups.count)")
            debugLog("🛡️ Neuestes Backup wird geschützt: \(sortedBackups.first?.filename ?? "keines")")
            debugLog("🗑️ Zu löschende alte Backups: \(oldBackups.count)")
            
            for backup in oldBackups {
                do {
                    try await deleteBackup(backup)
                    deletedCount += 1
                    debugLog("✅ Altes Backup gelöscht: \(backup.filename)")
                } catch {
                    errorCount += 1
                    debugLog("❌ Fehler beim Löschen von \(backup.filename): \(error)")
                }
            }
            
            if oldBackups.isEmpty {
                debugLog("✅ Keine alten Backups zum Löschen gefunden")
            } else {
                debugLog("✅ Manuelle Bereinigung abgeschlossen: \(deletedCount) Backups gelöscht, \(errorCount) Fehler")
                debugLog("🛡️ Neuestes Backup wurde geschützt und bleibt erhalten")
            }
        } catch {
            debugLog("❌ Fehler bei der manuellen Backup-Bereinigung: \(error)")
            errorCount += 1
        }
        return (deletedCount, errorCount)
    }
    
    // MARK: - Enhanced Sync Methods
    
    /// Enhanced sync with retry mechanism and detailed progress tracking
    func performEnhancedSync(allowUpload: Bool = false) async {
        syncStartTime = Date()
        syncMetrics.removeAll()
        
        debugLog("🚀 ENHANCED SYNC started", level: .info, context: "EnhancedSync")
        
        await MainActor.run {
            isSyncing = true
            syncStatus = .checking
            syncProgress = 0.0
            syncDetails = "Initializing enhanced sync..."
        }
        
        do {
            // Phase 1: Configuration Check (10%)
            await updateProgress(0.1, "Checking configuration...")
                    guard hasValidWebDAVConfiguration() else {
            throw NSError(domain: "SyncError", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebDAV configuration incomplete"])
        }
            
            // Phase 2: Network Connectivity Test (20%)
            await updateProgress(0.2, "Testing network connectivity...")
            try await testNetworkConnectivity()
            
            // Phase 3: Fetch Remote Backups with Retry (30%)
            await updateProgress(0.3, "Fetching remote backups...")
            let remoteBackups = try await retryManager.executeWithRetry {
                try await self.fetchRemoteBackups()
            }
            
            await MainActor.run {
                availableBackups = remoteBackups.sorted { $0.timestamp > $1.timestamp }
            }
            
            // Phase 4: Local Data Analysis (40%)
            await updateProgress(0.4, "Analyzing local data...")
            let localDataExists = await checkLocalDataExists()
            
            // Phase 5: Download Logic (60%)
            if !remoteBackups.isEmpty, let newestRemote = remoteBackups.max(by: { $0.timestamp < $1.timestamp }) {
                await updateProgress(0.5, "Checking for newer remote data...")
                
                if await shouldDownloadConservatively(newestRemote) || allowUpload {
                    await updateProgress(0.6, "Downloading backup...")
                    await MainActor.run { syncStatus = .downloading }
                    
                    try await retryManager.executeWithRetry {
                        try await self.downloadAndRestoreBackup(newestRemote)
                    }
                    
                    consecutiveUploads = 0 // Reset on successful download
                    await updateProgress(0.8, "Download completed")
                }
            }
            
            // Phase 6: Upload Logic (80%)
            if allowUpload && localDataExists {
                await updateProgress(0.8, "Preparing upload...")
                
                let shouldUpload = await shouldUploadConservatively()
                if shouldUpload {
                    await updateProgress(0.9, "Uploading backup...")
                    await MainActor.run { syncStatus = .uploading }
                    
                    try await retryManager.executeWithRetry {
                        try await self.uploadCurrentState()
                    }
                    
                    consecutiveUploads += 1
                }
            }
            
            // Phase 7: Completion (100%)
            await updateProgress(1.0, "Sync completed successfully")
            
            await MainActor.run {
                syncStatus = .success
                lastSyncDate = Date()
                saveLastSyncDate()
            }
            
            // Log sync metrics
            if let startTime = syncStartTime {
                let duration = Date().timeIntervalSince(startTime)
                debugLog("📊 Enhanced sync completed in \(String(format: "%.2f", duration))s", level: .info, context: "Metrics")
            }
            
        } catch {
            debugLog("❌ Enhanced sync failed: \(error)", level: .error, context: "EnhancedSync")
            await MainActor.run {
                syncStatus = .error(error.localizedDescription)
            }
        }
        
        await MainActor.run {
            isSyncing = false
            syncProgress = 0.0
            syncDetails = ""
        }
    }
    
    /// Test network connectivity with detailed diagnostics
    private func testNetworkConnectivity() async throws {
        debugLog("🌐 Testing network connectivity...", level: .info, context: "NetworkTest")
        
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") else {
            throw NSError(domain: "SyncError", code: 2, userInfo: [NSLocalizedDescriptionKey: "WebDAV credentials missing"])
        }
        
        // Test 1: Basic URL reachability
        guard let url = URL(string: webdavURL) else {
            throw NSError(domain: "SyncError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid WebDAV URL"])
        }
        
        // Test 2: Authentication test
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        
        let authString = "\(webdavUser):\(webdavPassword)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError("Invalid server response")
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw NSError(domain: "SyncError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Authentication failed: HTTP \(httpResponse.statusCode)"])
        }
        
        debugLog("✅ Network connectivity test passed", level: .info, context: "NetworkTest")
    }
    
    /// Update sync progress with detailed information
    private func updateProgress(_ progress: Double, _ details: String) async {
        await MainActor.run {
            syncProgress = progress
            syncDetails = details
        }
        
        debugLog("📊 Progress: \(Int(progress * 100))% - \(details)", level: .debug, context: "Progress")
    }
    
    /// Enhanced backup analysis with detailed metrics
    func performEnhancedBackupAnalysis() async -> BackupAnalysisReport {
        debugLog("🔍 Starting enhanced backup analysis...", level: .info, context: "Analysis")
        
        var report = BackupAnalysisReport()
        
        do {
            let backups = try await fetchRemoteBackups()
            report.totalBackups = backups.count
            
            for backup in backups {
                let analysis = await analyzeBackupContent(backup)
                report.backupAnalyses.append(BackupAnalysis(
                    filename: backup.filename,
                    timestamp: backup.timestamp,
                    size: backup.size,
                    analysis: analysis,
                    userID: backup.userID,
                    deviceID: backup.deviceID
                ))
            }
            
            // Calculate metrics
            if !backups.isEmpty {
                let sizes = backups.map { $0.size }
                report.averageSize = sizes.reduce(0, +) / Int64(sizes.count)
                report.largestBackup = sizes.max() ?? 0
                report.smallestBackup = sizes.min() ?? 0
                
                let timestamps = backups.map { $0.timestamp }
                report.oldestBackup = timestamps.min()
                report.newestBackup = timestamps.max()
            }
            
            debugLog("✅ Enhanced backup analysis completed", level: .info, context: "Analysis")
            
        } catch {
            debugLog("❌ Enhanced backup analysis failed: \(error)", level: .error, context: "Analysis")
            report.error = error.localizedDescription
        }
        
        return report
    }
    
    /// Get sync performance metrics
    func getSyncMetrics() -> [String: TimeInterval] {
        return syncMetrics
    }
    
    /// Clear sync metrics
    func clearSyncMetrics() {
        syncMetrics.removeAll()
    }
}

// MARK: - Enhanced Data Structures

struct BackupAnalysisReport {
    var totalBackups: Int = 0
    var averageSize: Int64 = 0
    var largestBackup: Int64 = 0
    var smallestBackup: Int64 = 0
    var oldestBackup: Date?
    var newestBackup: Date?
    var backupAnalyses: [BackupAnalysis] = []
    var error: String?
}

struct BackupAnalysis {
    let filename: String
    let timestamp: Date
    let size: Int64
    let analysis: String
    let userID: String?
    let deviceID: String
}


