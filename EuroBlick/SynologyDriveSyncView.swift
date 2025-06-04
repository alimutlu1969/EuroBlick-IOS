import SwiftUI

struct SynologyDriveSyncView: View {
    @ObservedObject var syncService: SynologyBackupSyncService
    @ObservedObject var multiUserManager: MultiUserSyncManager
    @State private var showSyncSettings = false
    @State private var showAvailableBackups = false
    
    var body: some View {
        NavigationView {
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
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await syncService.performManualSync()
                        }
                    }) {
                        HStack {
                            if syncService.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(syncService.isSyncing ? "Synchronisiert..." : "Manueller Sync")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(syncService.isSyncing ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(syncService.isSyncing)
                    
                    Button("Sync-Einstellungen") {
                        showSyncSettings = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSyncSettings) {
                SyncSettingsView(multiUserManager: multiUserManager)
            }
            .sheet(isPresented: $showAvailableBackups) {
                AvailableBackupsView(backups: syncService.availableBackups)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var syncStatusText: String {
        switch syncService.syncStatus {
        case .idle:
            return "Bereit"
        case .checking:
            return "Überprüfe Backups..."
        case .downloading:
            return "Lade Backup herunter..."
        case .uploading:
            return "Lade Backup hoch..."
        case .syncing:
            return "Synchronisiert..."
        case .error(let message):
            return "Fehler: \(message)"
        case .success:
            return "Erfolgreich"
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
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
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
    
    var body: some View {
        NavigationView {
            Form {
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
        }
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

#Preview {
    // For preview purposes
    let viewModel = TransactionViewModel()
    let syncService = SynologyBackupSyncService(viewModel: viewModel)
    let multiUserManager = MultiUserSyncManager()
    
    SynologyDriveSyncView(syncService: syncService, multiUserManager: multiUserManager)
} 