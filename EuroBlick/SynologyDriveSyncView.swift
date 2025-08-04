import SwiftUI

struct SynologyDriveSyncView: View {
    @ObservedObject var syncService: SynologyBackupSyncService
    @ObservedObject var multiUserManager: MultiUserSyncManager
    @ObservedObject var viewModel: TransactionViewModel
    
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
                    
                    // Auto-Sync Settings - NUR DIESER TEIL BLEIBT
                    VStack(spacing: 12) {
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
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
                .padding(.bottom, 20)
            }
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    let viewModel = TransactionViewModel()
    let syncService = SynologyBackupSyncService(viewModel: viewModel)
    let multiUserManager = MultiUserSyncManager()
    
    SynologyDriveSyncView(syncService: syncService, multiUserManager: multiUserManager, viewModel: viewModel)
} 