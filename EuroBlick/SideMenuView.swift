import SwiftUI

struct SideMenuView: View {
    @Binding var showSideMenu: Bool
    @State private var showLogoutAlert = false
    @State private var showColorSchemeSheet = false
    @State private var showFeedbackSheet = false
    @State private var showInfoLegalSheet = false
    @State private var showSyncView = false
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var syncService: SynologyBackupSyncService
    @EnvironmentObject var multiUserManager: MultiUserSyncManager
    
    // Dynamische Benutzerdaten
    private var userName: String {
        authManager.getLastAuthenticatedUser() ?? "Benutzer"
    }
    
    private var userInitials: String {
        let name = userName
        let components = name.components(separatedBy: " ")
        
        if components.count >= 2 {
            // Erste Buchstaben von Vor- und Nachnamen
            let firstInitial = components[0].prefix(1).uppercased()
            let lastInitial = components[1].prefix(1).uppercased()
            return "\(firstInitial)\(lastInitial)"
        } else if !name.isEmpty {
            // Erste zwei Buchstaben des Namens
            let firstTwo = name.prefix(2).uppercased()
            return String(firstTwo)
        }
        return "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profilbereich
            HStack(spacing: 16) {
                Button(action: { showLogoutAlert = true }) {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Text(userInitials)
                                .foregroundColor(.orange)
                                .font(.system(size: 20, weight: .bold))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .alert("Abmelden", isPresented: $showLogoutAlert) {
                    Button("Abbrechen", role: .cancel) { }
                    Button("Abmelden", role: .destructive) {
                        NotificationCenter.default.post(name: NSNotification.Name("SideMenuLogout"), object: nil)
                    }
                } message: {
                    Text("Möchten Sie sich wirklich abmelden?")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(userName)
                        .font(.headline)
                        .foregroundColor(Color.primary)
                    Text("EuroBlick Benutzer")
                        .font(.subheadline)
                        .foregroundColor(Color.secondary)
                }
            }
            .padding(.bottom, 32)
            .padding(.horizontal)

            // Navigationspunkte
            VStack(alignment: .leading, spacing: 8) {
                SideMenuItem(icon: "creditcard", title: "Konten") {
                    NotificationCenter.default.post(name: NSNotification.Name("SideMenuShowAccounts"), object: nil)
                    showSideMenu = false
                }
                SideMenuItem(icon: "chart.pie", title: "Auswertungen") {
                    NotificationCenter.default.post(name: NSNotification.Name("SideMenuShowAnalysis"), object: nil)
                    showSideMenu = false
                }
                
                // Neuer Sync-Menüpunkt mit Status-Indikator
                SideMenuSyncItem(
                    icon: "icloud.and.arrow.up",
                    title: "Synology Drive",
                    syncStatus: syncService.syncStatus,
                    isSyncing: syncService.isSyncing
                ) {
                    showSyncView = true
                }
                
                SideMenuItem(icon: "paintpalette", title: "Farbdesign") {
                    showColorSchemeSheet = true
                }
                SideMenuItem(icon: "paperplane", title: "Feedback senden") {
                    showFeedbackSheet = true
                }
                SideMenuItem(icon: "gear", title: "Einstellungen") {
                    NotificationCenter.default.post(name: NSNotification.Name("SideMenuShowSettings"), object: nil)
                    showSideMenu = false
                }
                SideMenuItem(icon: "info.circle", title: "Info / Rechtliches") {
                    showInfoLegalSheet = true
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.top, 56)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Color(.systemBackground))
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showColorSchemeSheet) {
            ColorSchemeSheetView()
        }
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackSheetView()
        }
        .sheet(isPresented: $showInfoLegalSheet) {
            InfoLegalSheetView()
        }
        .sheet(isPresented: $showSyncView) {
            SynologyDriveSyncView(syncService: syncService, multiUserManager: multiUserManager)
        }
    }
}

struct SideMenuItem: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.orange)
                    .frame(width: 24, height: 24)
                Text(title)
                    .foregroundColor(Color.primary)
                    .font(.system(size: 18, weight: .medium))
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SideMenuSyncItem: View {
    let icon: String
    let title: String
    let syncStatus: SynologyBackupSyncService.SyncStatus
    let isSyncing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Image(systemName: icon)
                        .foregroundColor(.orange)
                        .frame(width: 24, height: 24)
                    
                    if isSyncing {
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                            .frame(width: 8, height: 8)
                            .offset(x: 12, y: -12)
                            .overlay(
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 4, height: 4)
                                    .offset(x: 12, y: -12)
                            )
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .offset(x: 12, y: -12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(Color.primary)
                        .font(.system(size: 18, weight: .medium))
                    
                    Text(statusText)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var statusColor: Color {
        switch syncStatus {
        case .idle:
            return .gray
        case .checking, .downloading, .uploading, .syncing:
            return .blue
        case .error:
            return .red
        case .success:
            return .green
        }
    }
    
    private var statusText: String {
        switch syncStatus {
        case .idle:
            return "Bereit"
        case .checking:
            return "Überprüft..."
        case .downloading:
            return "Lädt herunter..."
        case .uploading:
            return "Lädt hoch..."
        case .syncing:
            return "Synchronisiert..."
        case .error:
            return "Fehler"
        case .success:
            return "Aktuell"
        }
    }
} 