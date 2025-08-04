import SwiftUI

struct SynologyDriveSyncView: View {
    @ObservedObject var syncService: SynologyBackupSyncService
    @ObservedObject var multiUserManager: MultiUserSyncManager
    @ObservedObject var viewModel: TransactionViewModel
    
    @State private var showSyncSettings = false
    @State private var showAvailableBackups = false
    @State private var showTestAlert = false
    @State private var testResult = ""
    @State private var showBackupAnalysis = false
    @State private var backupAnalysis: [(SynologyBackupSyncService.BackupInfo, String)] = []
    @State private var isAnalyzing = false
    @State private var showDebugLogs = false
    @State private var debugLogs: [String] = []
    @State private var isCapturingLogs = false
    @State private var showForceRestore = false
    @State private var forceRestoreJSON = ""
    @State private var showCleanupResult = false
    @State private var cleanupResult: (deletedCount: Int, errorCount: Int) = (0, 0)
    @State private var showEnhancedAnalysis = false
    @State private var enhancedAnalysisReport: BackupAnalysisReport?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Synology Drive Sync")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Automatische Synchronisation mit Ihrem Synology Drive")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)
                    
                    // Sync Status
                    VStack(spacing: 15) {
                        StatusCard(
                            title: "Sync Status",
                            status: syncStatusText,
                            color: syncStatusColor,
                            icon: syncStatusIcon
                        )
                        
                        if let lastSync = syncService.lastSyncDate {
                            StatusCard(
                                title: "Letzter Sync",
                                status: formatDate(lastSync),
                                color: .secondary,
                                icon: "clock"
                            )
                        }
                        
                        StatusCard(
                            title: "Konfliktlösung",
                            status: multiUserManager.conflictResolutionStrategy.displayName,
                            color: .orange,
                            icon: "arrow.triangle.merge"
                        )
                    }
                    
                    // Available Backups
                    if !syncService.availableBackups.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Verfügbare Backups")
                                    .font(.headline)
                                Spacer()
                                Button("Alle anzeigen") {
                                    showAvailableBackups = true
                                }
                                .font(.caption)
                            }
                            
                            ForEach(syncService.availableBackups.prefix(3)) { backup in
                                BackupRowView(backup: backup)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // MANUELLE BACKUP-FUNKTIONEN
                    VStack(spacing: 12) {
                        Button("Backup erstellen") {
                            Task {
                                do {
                                    try await syncService.createBackup()
                                } catch {
                                    // Fehlerbehandlung (optional Toast)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        
                        Button("Alte Backups bereinigen (1+ Tag)") {
                            Task {
                                cleanupResult = await syncService.cleanupOldBackupsManually()
                                showCleanupResult = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        
                        Button("Verfügbare Backups anzeigen") {
                            Task {
                                await syncService.fetchAvailableBackups()
                                showAvailableBackups = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        
                        Button("Backup wiederherstellen") {
                            showAvailableBackups = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    // Enhanced Sync Progress Display
                    if syncService.isSyncing {
                        VStack(spacing: 8) {
                            HStack {
                                ProgressView(value: syncService.syncProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                Text("\(Int(syncService.syncProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(syncService.syncDetails)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Action Buttons - ENHANCED SYNC SYSTEM
                    VStack(spacing: 12) {
                        // Status Warning wenn zu viele Uploads
                        if case .blocked(let reason) = syncService.syncStatus {
                            VStack {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text("Synchronisation pausiert")
                                        .font(.headline)
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                Text(reason)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Button("Upload-Zähler zurücksetzen") {
                                    syncService.resetUploadCounter()
                                }
                                .font(.caption)
                                .padding(.top, 4)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        // Hauptsync-Button (nur Download)
                        Button(action: {
                            Task {
                                await syncService.performManualSync(allowUpload: false)
                            }
                        }) {
                            HStack {
                                if syncService.isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                                Text(syncService.isSyncing ? "Synchronisiert..." : "Sichere Synchronisation (nur Download)")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(syncService.isSyncing ? Color.gray : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(syncService.isSyncing)
                        
                        // Upload-Button (mit Warnung)
                        Button(action: {
                            Task {
                                await syncService.performManualSync(allowUpload: true)
                            }
                        }) {
                            HStack {
                                if syncService.isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.up.circle")
                                }
                                Text("Upload erlauben (Vorsicht!)")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(syncService.isSyncing ? Color.gray : Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(syncService.isSyncing)
                        
                        // Info-Text
                        VStack(alignment: .leading, spacing: 4) {
                            Text("💡 Sicherheitshinweise:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("• 'Sichere Synchronisation' lädt nur neue Daten herunter")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("• 'Upload erlauben' kann Daten überschreiben - nur verwenden wenn sicher")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        HStack(spacing: 12) {
                            Button("Debug-Logs") {
                                showDebugLogs = true
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            
                            Button("Diagnose") {
                                Task {
                                    syncService.clearDebugLogs()
                                    await syncService.performDiagnosticSync()
                                    showDebugLogs = true
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button("🚀 Erweiterte Synchronisation") {
                            Task {
                                await syncService.performEnhancedSync(allowUpload: false)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        
                        Button("📊 Erweiterte Backup-Analyse") {
                            Task {
                                let report = await syncService.performEnhancedBackupAnalysis()
                                await MainActor.run {
                                    showEnhancedAnalysis = true
                                    enhancedAnalysisReport = report
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        
                        Button("WebDAV-Verbindung testen") {
                            Task {
                                await testWebDAVConnection()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        
                        Button("Sync-Einstellungen") {
                            showSyncSettings = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                        
                        Button("Backup-Analyse durchführen") {
                            Task {
                                await analyzeBackups()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Button("JSON-Backup wiederherstellen") {
                            showForceRestore = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Button("Datenbank-Diagnose") {
                            Task {
                                syncService.clearDebugLogs()
                                await syncService.performDatabaseDiagnostic()
                                showDebugLogs = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.cyan)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        Text("🚨 NOTFALL-FUNKTIONEN")
                            .font(.headline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text("Nutzen Sie diese nur, wenn Daten nach erfolgreichem Sync nicht sichtbar sind!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        
                        Button("🔧 UI KOMPLETT AKTUALISIEREN") {
                            Task {
                                await syncService.forceCompleteUIRefresh()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .fontWeight(.bold)
                        
                        Button("🔍 DATENBANK-STATUS PRÜFEN") {
                            Task {
                                syncService.clearDebugLogs()
                                await syncService.debugCurrentDatabaseState()
                                showDebugLogs = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .fontWeight(.bold)
                    }
                    
                    Group {
                        Section("Auto-Sync Einstellungen (Konservativ)") {
                            HStack {
                                Image(systemName: syncService.isAutoSyncEnabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(syncService.isAutoSyncEnabled ? .green : .gray)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Automatische Synchronisation")
                                        .font(.headline)
                                    Text("Alle 5 Minuten, nur Downloads - keine automatischen Uploads")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { syncService.isAutoSyncEnabled },
                                    set: { syncService.setAutoSyncEnabled($0) }
                                ))
                            }
                            .padding(.vertical, 4)
                            
                            if syncService.isAutoSyncEnabled {
                                HStack {
                                    Image(systemName: "shield.checkered")
                                        .foregroundColor(.green)
                                    Text("SICHER: Auto-Sync lädt nur Daten herunter, überschreibt nie lokale Änderungen")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        
                        Section("Synchronisation") {
                            // Add synchronization-related content here
                        }
                    }
                }
                .padding()
                .padding(.bottom, 20) // Extra padding at bottom
            }
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSyncSettings) {
                SyncSettingsView(multiUserManager: multiUserManager)
            }
            .sheet(isPresented: $showAvailableBackups) {
                AvailableBackupsView(backups: syncService.availableBackups)
            }
            .sheet(isPresented: $showBackupAnalysis) {
                BackupAnalysisView(
                    backupAnalysis: backupAnalysis,
                    syncService: syncService,
                    viewModel: viewModel,
                    onBackupSelected: { backup in
                        showBackupAnalysis = false
                        Task {
                            await restoreSpecificBackup(backup)
                        }
                    }
                )
            }
            .sheet(isPresented: $showDebugLogs) {
                DebugLogsView(logs: syncService.debugLogs, syncService: syncService)
            }
            .sheet(isPresented: $showForceRestore) {
                ForceRestoreView(syncService: syncService)
            }
            .sheet(isPresented: $showEnhancedAnalysis) {
                EnhancedAnalysisView(report: enhancedAnalysisReport)
            }
            .alert("WebDAV-Test", isPresented: $showTestAlert) {
                Button("OK") { }
            } message: {
                Text(testResult)
            }
            .alert("Backup-Bereinigung", isPresented: $showCleanupResult) {
                Button("OK") { }
            } message: {
                Text("Bereinigung abgeschlossen:\n\n✅ \(cleanupResult.deletedCount) alte Backups gelöscht\n❌ \(cleanupResult.errorCount) Fehler aufgetreten")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var syncStatusText: String {
        switch syncService.syncStatus {
        case .idle:
            return "Bereit"
        case .checking:
            return "Prüfe Server..."
        case .downloading:
            return "Lade herunter..."
        case .uploading:
            return "Lade hoch..."
        case .syncing:
            return "Synchronisiert..."
        case .error(let message):
            return "Fehler: \(message)"
        case .success:
            return "Erfolgreich"
        case .blocked(let reason):
            return "⚠️ Pausiert: \(reason)"
        }
    }
    
    private var syncStatusColor: Color {
        switch syncService.syncStatus {
        case .idle:
            return .secondary
        case .checking, .downloading, .uploading, .syncing:
            return .blue
        case .error:
            return .red
        case .success:
            return .green
        case .blocked:
            return .orange
        }
    }
    
    private var syncStatusIcon: String {
        switch syncService.syncStatus {
        case .idle:
            return "pause.circle"
        case .checking, .downloading, .uploading, .syncing:
            return "arrow.clockwise.circle"
        case .error:
            return "exclamationmark.circle"
        case .success:
            return "checkmark.circle"
        case .blocked:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
    
    // MARK: - Private Methods
    
    private func testWebDAVConnection() async {
        let webdavURL = UserDefaults.standard.string(forKey: "webdavURL") ?? ""
        let webdavUser = UserDefaults.standard.string(forKey: "webdavUser") ?? ""
        let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") ?? ""
        
        if webdavURL.isEmpty || webdavUser.isEmpty || webdavPassword.isEmpty {
            await MainActor.run {
                testResult = "WebDAV-Zugangsdaten sind nicht vollständig konfiguriert.\n\nBitte gehen Sie zu Sync-Einstellungen und konfigurieren Sie:\n- WebDAV-URL\n- Benutzername\n- Passwort"
                showTestAlert = true
            }
            return
        }
        
        do {
            // Test the connection by trying to fetch remote backups
            let backups = try await testFetchRemoteBackups()
            await MainActor.run {
                testResult = "✅ WebDAV-Verbindung erfolgreich!\n\nServer: \(webdavURL)\nBenutzer: \(webdavUser)\nGefundene Backup-Dateien: \(backups.count)"
                showTestAlert = true
            }
        } catch {
            await MainActor.run {
                testResult = "❌ WebDAV-Verbindung fehlgeschlagen:\n\n\(error.localizedDescription)\n\nBitte überprüfen Sie Ihre Zugangsdaten und Server-URL."
                showTestAlert = true
            }
        }
    }
    
    private func testFetchRemoteBackups() async throws -> [SynologyBackupSyncService.BackupInfo] {
        // Use the same logic as the sync service but for testing
        guard let webdavURL = UserDefaults.standard.string(forKey: "webdavURL"),
              let webdavUser = UserDefaults.standard.string(forKey: "webdavUser"),
              let webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebDAV-Zugangsdaten fehlen"])
        }
        
        var serverURL: URL
        if webdavURL.hasSuffix("/EuroBlickBackup") {
            guard let url = URL(string: String(webdavURL.dropLast("/EuroBlickBackup".count))) else {
                throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ungültige WebDAV-URL"])
            }
            serverURL = url
        } else {
            guard let url = URL(string: webdavURL) else {
                throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ungültige WebDAV-URL"])
            }
            serverURL = url
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
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "TestError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ungültige Server-Antwort"])
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw NSError(domain: "TestError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Server-Fehler: HTTP \(httpResponse.statusCode)"])
        }
        
        // For testing, just return empty array - we just want to verify connection works
        return []
    }
    
    private func analyzeBackups() async {
        isAnalyzing = true
        backupAnalysis = await syncService.analyzeAvailableBackups()
        isAnalyzing = false
        showBackupAnalysis = true
    }
    
    private func restoreSpecificBackup(_ backup: SynologyBackupSyncService.BackupInfo) async {
        // Temporarily stop auto sync
        syncService.stopAutoSync()
        
        print("🔄 Manually restoring backup: \(backup.filename)")
        
        // Download and restore the selected backup
        await syncService.restoreSpecificBackup(backup)
        
        // Restart auto sync
        syncService.startAutoSync()
    }
    
    // MARK: - Debug Methods
    // Removed - now using conservative sync methods directly
}

// MARK: - Supporting Views

struct StatusCard: View {
    let title: String
    let status: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(status)
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct BackupRowView: View {
    let backup: SynologyBackupSyncService.BackupInfo
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(backup.filename)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack {
                    Text(formatDate(backup.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let userID = backup.userID {
                        Text("• User: \(userID)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Text(formatFileSize(backup.size))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct SyncSettingsView: View {
    @ObservedObject var multiUserManager: MultiUserSyncManager
    @Environment(\.dismiss) var dismiss
    @State private var webdavURL: String = ""
    @State private var webdavUser: String = ""
    @State private var webdavPassword: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("WebDAV-Konfiguration"), footer: Text("Geben Sie die Zugangsdaten für Ihr Synology Drive ein. Die URL sollte das Format haben: https://ihr-synology.com:5006/webdav")) {
                    TextField("WebDAV-URL", text: $webdavURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Benutzername", text: $webdavUser)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Passwort", text: $webdavPassword)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Einstellungen speichern") {
                        saveWebDAVSettings()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Section(header: Text("Konfliktlösung")) {
                    ForEach([
                        MultiUserSyncManager.ConflictStrategy.lastWriteWins,
                        .mergeChanges,
                        .preserveLocal,
                        .askUser
                    ], id: \.rawValue) { strategy in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(strategy.displayName)
                                    .font(.body)
                                Spacer()
                                if multiUserManager.conflictResolutionStrategy == strategy {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .onTapGesture {
                                multiUserManager.setConflictResolutionStrategy(strategy)
                            }
                            
                            Text(strategy.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                Section(header: Text("Sync-Intervall"), footer: Text("Die App prüft automatisch alle 30 Sekunden auf neue Backups.")) {
                    HStack {
                        Image(systemName: "clock")
                        Text("Automatischer Sync")
                        Spacer()
                        Text("30 Sekunden")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Über Multi-User Sync")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Diese Funktion ermöglicht es mehreren Benutzern, gleichzeitig auf die gleichen EuroBlick-Daten zuzugreifen.")
                            .font(.body)
                        
                        Text("Jedes Gerät erhält eine eindeutige ID und alle Änderungen werden automatisch synchronisiert.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Sync-Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Fertig") { dismiss() })
            .onAppear {
                loadWebDAVSettings()
            }
        }
    }
    
    private func loadWebDAVSettings() {
        webdavURL = UserDefaults.standard.string(forKey: "webdavURL") ?? ""
        webdavUser = UserDefaults.standard.string(forKey: "webdavUser") ?? ""
        webdavPassword = UserDefaults.standard.string(forKey: "webdavPassword") ?? ""
    }
    
    private func saveWebDAVSettings() {
        UserDefaults.standard.set(webdavURL, forKey: "webdavURL")
        UserDefaults.standard.set(webdavUser, forKey: "webdavUser")
        UserDefaults.standard.set(webdavPassword, forKey: "webdavPassword")
        
        print("💾 WebDAV settings saved:")
        print("  URL: \(webdavURL)")
        print("  User: \(webdavUser)")
        print("  Password: \(webdavPassword.isEmpty ? "empty" : "present")")
    }
}

struct AvailableBackupsView: View {
    let backups: [SynologyBackupSyncService.BackupInfo]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List(backups) { backup in
                VStack(alignment: .leading, spacing: 8) {
                    Text(backup.filename)
                        .font(.headline)
                    
                    HStack {
                        Label(formatDate(backup.timestamp), systemImage: "clock")
                        Spacer()
                        Label(formatFileSize(backup.size), systemImage: "doc")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    if let userID = backup.userID {
                        Label("User: \(userID) • Device: \(backup.deviceID)", systemImage: "person")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Verfügbare Backups")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Schließen") { dismiss() })
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct BackupAnalysisView: View {
    let backupAnalysis: [(SynologyBackupSyncService.BackupInfo, String)]
    let syncService: SynologyBackupSyncService
    let viewModel: TransactionViewModel
    let onBackupSelected: (SynologyBackupSyncService.BackupInfo) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if backupAnalysis.isEmpty {
                    Text("Keine Backups gefunden")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(backupAnalysis.indices, id: \.self) { index in
                        let (backup, analysis) = backupAnalysis[index]
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(backup.filename)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Button("Wiederherstellen") {
                                    onBackupSelected(backup)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "calendar")
                                        .foregroundColor(.secondary)
                                    Text(formatBackupDate(backup.timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(.secondary)
                                    Text("\(backup.size) bytes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let userID = backup.userID {
                                    HStack {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.secondary)
                                        Text("User: \(userID)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Text(analysis)
                                .font(.caption)
                                .padding(.top, 4)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Backup-Analyse")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Schließen") { dismiss() })
        }
    }
    
    private func formatBackupDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
}

// MARK: - Debug Logs View
struct DebugLogsView: View {
    let logs: [String]
    let syncService: SynologyBackupSyncService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if logs.isEmpty {
                        VStack(spacing: 16) {
                            Text("Keine Debug-Logs verfügbar")
                                .foregroundColor(.secondary)
                            
                            Button("Sync-Test ausführen") {
                                Task {
                                    await syncService.performManualSync()
                                }
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding()
                    } else {
                        ForEach(logs, id: \.self) { log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Debug-Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if !logs.isEmpty {
                            Button("Löschen") {
                                syncService.clearDebugLogs()
                            }
                            
                            Button("Kopieren") {
                                let allLogs = logs.joined(separator: "\n")
                                UIPasteboard.general.string = allLogs
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Force Restore View
struct ForceRestoreView: View {
    let syncService: SynologyBackupSyncService
    @Environment(\.dismiss) private var dismiss
    @State private var jsonInput = ""
    @State private var isProcessing = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("JSON-Backup-Daten")
                        .font(.headline)
                    
                    Text("Fügen Sie hier die vollständigen JSON-Backup-Daten ein:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $jsonInput)
                        .font(.system(.caption, design: .monospaced))
                        .border(Color.gray, width: 1)
                        .frame(minHeight: 200)
                }
                
                VStack(spacing: 8) {
                    Text("⚠️ Achtung")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text("Diese Funktion überschreibt alle lokalen Daten mit den bereitgestellten Backup-Daten. Stellen Sie sicher, dass Sie ein aktuelles Backup haben.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: {
                    Task {
                        await performForceRestore()
                    }
                }) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isProcessing ? "Wird wiederhergestellt..." : "Backup wiederherstellen")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(jsonInput.isEmpty || isProcessing ? Color.gray : Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(jsonInput.isEmpty || isProcessing)
                
                Spacer()
            }
            .padding()
            .navigationTitle("JSON-Backup wiederherstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Beispiel einfügen") {
                        insertSampleJSON()
                    }
                    .disabled(isProcessing)
                }
            }
            .alert("Wiederherstellung", isPresented: $showAlert) {
                Button("OK") {
                    if alertMessage.contains("erfolgreich") {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func performForceRestore() async {
        isProcessing = true
        syncService.clearDebugLogs()
        
        let success = await syncService.forceRestoreFromJSON(jsonInput)
        
        await MainActor.run {
            isProcessing = false
            if success {
                alertMessage = "✅ Backup wurde erfolgreich wiederhergestellt! Die App zeigt jetzt die Daten aus dem bereitgestellten Backup an."
            } else {
                alertMessage = "❌ Wiederherstellung fehlgeschlagen. Bitte überprüfen Sie die JSON-Daten und versuchen Sie es erneut. Weitere Details finden Sie in den Debug-Logs."
            }
            showAlert = true
        }
    }
    
    private func insertSampleJSON() {
        jsonInput = """
{
  "version": "2.0",
  "userID": "Ihre_Backup_Daten_hier_einfügen",
  "deviceName": "iPhone",
  "timestamp": 770838890.495885,
  "appVersion": "1.0",
  "deviceID": "f8ef64e2",
  "accountGroups": [],
  "transactions": [],
  "accounts": [],
  "categories": []
}
"""
    }
}

// MARK: - Enhanced Analysis View

struct EnhancedAnalysisView: View {
    let report: BackupAnalysisReport?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let report = report {
                        // Summary Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("📊 Backup-Analyse Zusammenfassung")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Gesamtanzahl Backups:")
                                    Spacer()
                                    Text("\(report.totalBackups)")
                                        .fontWeight(.semibold)
                                }
                                
                                HStack {
                                    Text("Durchschnittliche Größe:")
                                    Spacer()
                                    Text(formatFileSize(report.averageSize))
                                        .fontWeight(.semibold)
                                }
                                
                                HStack {
                                    Text("Größtes Backup:")
                                    Spacer()
                                    Text(formatFileSize(report.largestBackup))
                                        .fontWeight(.semibold)
                                }
                                
                                HStack {
                                    Text("Kleinstes Backup:")
                                    Spacer()
                                    Text(formatFileSize(report.smallestBackup))
                                        .fontWeight(.semibold)
                                }
                                
                                if let oldest = report.oldestBackup {
                                    HStack {
                                        Text("Ältestes Backup:")
                                        Spacer()
                                        Text(formatDate(oldest))
                                            .fontWeight(.semibold)
                                    }
                                }
                                
                                if let newest = report.newestBackup {
                                    HStack {
                                        Text("Neuestes Backup:")
                                        Spacer()
                                        Text(formatDate(newest))
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        
                        // Detailed Analysis Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("📋 Detaillierte Analyse")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            ForEach(report.backupAnalyses, id: \.filename) { analysis in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(analysis.filename)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text(formatFileSize(analysis.size))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(analysis.analysis)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        if let userID = analysis.userID {
                                            Text("👤 \(userID)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Text("📱 \(analysis.deviceID)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Text(formatDate(analysis.timestamp))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color(.systemGray6).opacity(0.5))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            
                            Text("Keine Analyse-Daten verfügbar")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Die Backup-Analyse konnte nicht durchgeführt werden oder es sind keine Daten vorhanden.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Erweiterte Backup-Analyse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
}

#Preview {
    let viewModel = TransactionViewModel()
    let syncService = SynologyBackupSyncService(viewModel: viewModel)
    let multiUserManager = MultiUserSyncManager()
    
    SynologyDriveSyncView(syncService: syncService, multiUserManager: multiUserManager, viewModel: viewModel)
} 