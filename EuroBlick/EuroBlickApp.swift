import SwiftUI

@main
struct EuroBlickApp: App {
    let persistenceController = PersistenceController.shared
    @State private var isDataLoaded = false

    init() {
        // Set global appearance for UIKit components
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        // Apply to all navigation bars
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        
        // Set tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = .black
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isDataLoaded {
                    AppContentView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .preferredColorScheme(.dark)
                } else {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView("Lade Daten...")
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .foregroundColor(.white)
                            
                            Text("Initialisiere Sync-Services...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .onAppear {
                // Stelle sicher, dass Core Data vollständig geladen ist
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isDataLoaded = true
                }
            }
        }
    }
}

// Neue View, die die Sync-Services initialisiert
struct AppContentView: View {
    @StateObject private var viewModel = TransactionViewModel()
    @StateObject private var multiUserManager = MultiUserSyncManager()
    @State private var syncService: SynologyBackupSyncService?
    
    var body: some View {
        Group {
            if let syncService = syncService {
                LoginView()
                    .environmentObject(viewModel)
                    .environmentObject(syncService)
                    .environmentObject(multiUserManager)
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView("Initialisiere Sync...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            if syncService == nil {
                // Erstelle den SynologyBackupSyncService nach der View-Initialisierung
                syncService = SynologyBackupSyncService(viewModel: viewModel)
            }
        }
    }
}
