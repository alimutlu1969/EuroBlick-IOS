import SwiftUI
import CoreData
import UniformTypeIdentifiers // Für UIDocumentPickerViewController

struct AuthenticationView: View {
    @Binding var isAuthenticated: Bool
    @EnvironmentObject var authManager: AuthenticationManager // Verwende den AuthenticationManager
    @State private var errorMessage: String? // Für Fehlermeldungen bei fehlgeschlagener Authentifizierung

    var body: some View {
        VStack {
            Text("Bitte authentifizieren")
                .foregroundColor(.white)
                .font(.headline)
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.bottom, 10)
            }
            Button("Anmelden mit Face ID") {
                authManager.authenticateWithFaceID { success, error in
                    if success {
                        isAuthenticated = true // Wird auch im AuthenticationManager gesetzt, aber für Sicherheit
                    } else {
                        errorMessage = error
                    }
                }
            }
            .foregroundColor(.blue)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
        }
        .background(Color.black)
    }
}

// Struktur für Kontostand-Anzeige
struct AccountBalance: Identifiable {
    let id: NSManagedObjectID // Verwende die Core Data-ID für Eindeutigkeit
    let name: String
    let balance: Double
}

// View für ein einzelnes Konto
struct AccountRowView: View {
    let account: Account
    let balance: Double
    let viewModel: TransactionViewModel

    private var accountIcon: (systemName: String, color: Color) {
        let accountName = (account.name ?? "").lowercased()
        if accountName.contains("bar") || accountName.contains("kasse") {
            return ("banknote.fill", .green)
        } else if accountName.contains("giro") {
            return ("building.columns.fill", .blue)
        } else if accountName == "bk" {
            return ("person.circle.fill", .orange)
        } else if accountName.contains("konto") {
            return ("building.columns.fill", .blue)
        } else {
            return ("building.columns.fill", .gray)
        }
    }

    var body: some View {
        NavigationLink(
            destination: TransactionView(account: account, viewModel: viewModel)
        ) {
            HStack {
                Image(systemName: accountIcon.systemName)
                    .foregroundColor(accountIcon.color)
                    .font(.system(size: 19))
                    .padding(.trailing, 8)
                Text(account.name ?? "Unbekanntes Konto")
                    .foregroundColor(.white)
                    .font(.system(size: 17))
                Spacer()
                Text("\(String(format: "%.2f €", balance))")
                    .foregroundColor(balance >= 0 ? Color.green : Color.red)
                    .font(.system(size: 16))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
            )
        }
        .padding(.horizontal)
        .buttonStyle(PlainButtonStyle())
    }
}

// View für eine einzelne Kontogruppe
struct AccountGroupView: View {
    let group: AccountGroup
    let viewModel: TransactionViewModel
    let balances: [AccountBalance]
    @Binding var showEditGroupSheet: Bool
    @Binding var groupToEdit: AccountGroup?
    @Binding var newGroupName: String

    @State private var groupBalance: Double = 0.0
    @State private var accountBalances: [(account: Account, balance: Double)] = []

    private var groupIcon: (systemName: String, color: Color) {
        let groupName = (group.name ?? "").lowercased()
        if groupName.contains("kaffee") {
            return ("cup.and.saucer.fill", .brown)
        } else if groupName.contains("bank") || groupName.contains("giro") {
            return ("building.columns.fill", .blue)
        } else if groupName.contains("bar") || groupName.contains("kasse") {
            return ("banknote.fill", .green)
        } else {
            return ("folder.fill", .gray)
        }
    }

    private var regularAccounts: [(account: Account, balance: Double)] {
        accountBalances.filter { ($0.account.name ?? "").lowercased() != "bk" }
    }

    private var bkAccounts: [(account: Account, balance: Double)] {
        accountBalances.filter { ($0.account.name ?? "").lowercased() == "bk" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Gruppenkopf mit Name und Gesamtbilanz
            HStack {
                Image(systemName: groupIcon.systemName)
                    .foregroundColor(groupIcon.color)
                    .font(.system(size: 21))
                    .padding(.trailing, 6)
                Text(group.name ?? "Unbekannte Gruppe")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(String(format: "%.2f €", groupBalance))")
                    .foregroundColor(groupBalance >= 0 ? Color.green : Color.red)
                    .font(.system(size: 16))
                Button(action: {
                    groupToEdit = group
                    newGroupName = group.name ?? ""
                    showEditGroupSheet = true
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                        .font(.system(size: 17))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(.horizontal),
                alignment: .bottom
            )

            // Reguläre Konten
            ForEach(regularAccounts, id: \.account.objectID) { item in
                AccountRowView(account: item.account, balance: item.balance, viewModel: viewModel)
                    .padding(.vertical, 1)
            }

            // Trennlinie und BK-Konten
            if !bkAccounts.isEmpty {
                Divider()
                    .background(Color.gray.opacity(0.5))
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                ForEach(bkAccounts, id: \.account.objectID) { item in
                    AccountRowView(account: item.account, balance: item.balance, viewModel: viewModel)
                        .padding(.vertical, 1)
                }
            }

            // Link zu Auswertungen
            NavigationLink(
                destination: EvaluationView(accounts: accountBalances.map { $0.account }, viewModel: viewModel)
            ) {
                HStack(spacing: 6) {
                    ZStack {
                        Image(systemName: "chart.pie.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 16))
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                            .offset(x: 3, y: 3)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.orange)
                            .font(.system(size: 10))
                    }
                    Text("Auswertungen")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical)
        .onAppear {
            calculateBalances()
        }
        .onChange(of: viewModel.transactionsUpdated) { _, _ in
            calculateBalances()
        }
    }

    private func calculateBalances() {
        let accounts = (group.accounts?.allObjects as? [Account]) ?? []
        
        // Berechne alle Kontostände
        accountBalances = accounts
            .sorted { $0.name ?? "" < $1.name ?? "" }
            .map { account in
                let balance = balances.first { $0.id == account.objectID }?.balance ?? viewModel.getBalance(for: account)
                return (account, balance)
            }
        
        // Berechne Gruppensaldo ohne BK-Konten
        groupBalance = accountBalances
            .filter { ($0.account.name ?? "").lowercased() != "bk" }
            .reduce(0.0) { total, item in
                total + item.balance
            }
    }
}

// View für Programminformationen
struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header mit Logo
                    HStack {
                        Image(systemName: "eurosign.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("EuroBlick")
                                .font(.title)
                                .bold()
                            Text("Version 1.0.0")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 20)
                    
                    // Funktionen
                    GroupBox(label: Text("Funktionen").bold()) {
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureRow(icon: "banknote.fill", title: "Kontoführung", description: "Verwalten Sie Ihre Bankkonten und Bargeldbestände")
                            FeatureRow(icon: "folder.fill", title: "Kontogruppen", description: "Organisieren Sie Ihre Konten in übersichtlichen Gruppen")
                            FeatureRow(icon: "arrow.left.arrow.right", title: "Transaktionen", description: "Erfassen Sie Einnahmen, Ausgaben und Umbuchungen")
                            FeatureRow(icon: "chart.pie.fill", title: "Auswertungen", description: "Detaillierte Analysen Ihrer Finanzen mit Diagrammen")
                            FeatureRow(icon: "tag.fill", title: "Kategorisierung", description: "Ordnen Sie Transaktionen Kategorien zu")
                            FeatureRow(icon: "arrow.clockwise", title: "Backup", description: "Sichern und Wiederherstellen Ihrer Daten")
                            FeatureRow(icon: "faceid", title: "Sicherheit", description: "Geschützt durch Face ID / Touch ID")
                        }
                        .padding(.vertical, 8)
                    }
                    .groupBoxStyle(TransparentGroupBoxStyle())
                    
                    // Datenschutz
                    GroupBox(label: Text("Datenschutz").bold()) {
                        Text("Ihre Daten werden ausschließlich lokal auf Ihrem Gerät gespeichert. Es erfolgt keine Übertragung an externe Server.")
                            .padding(.vertical, 8)
                    }
                    .groupBoxStyle(TransparentGroupBoxStyle())
                    
                    // Copyright
                    GroupBox(label: Text("Rechtliches").bold()) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("© 2025 A.E.M.")
                            Text("Alle Rechte vorbehalten")
                        }
                        .padding(.vertical, 8)
                    }
                    .groupBoxStyle(TransparentGroupBoxStyle())
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Über EuroBlick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .foregroundColor(.white)
    }
}

// Hilfsstruct für Feature-Zeilen
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title2)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }
}

// Transparenter GroupBox Style
struct TransparentGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label
                .font(.headline)
                .foregroundColor(.white)
            configuration.content
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}

// View für die Toolbar
struct ContentToolbar: ToolbarContent {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @Binding var showAddSheet: Bool
    @Binding var showAddGroupSheet: Bool
    @Binding var showSelectGroupSheet: Bool
    @Binding var showAboutView: Bool

    // Manuelle Steuerung für Debug-Buttons
    private let isDebugMode = true // Aktiviere Debug-Buttons

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: {
                authManager.logout()
                print("Abmelden ausgelöst")
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(.system(size: 16))
                    Text("Abmelden")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.2))
                )
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button(action: {
                    showSelectGroupSheet = true
                    print("Konto hinzufügen ausgelöst")
                }) {
                    Label("Konto hinzufügen", systemImage: "creditcard")
                }
                Button(action: {
                    showAddGroupSheet = true
                    print("Kontogruppe hinzufügen ausgelöst")
                }) {
                    Label("Kontogruppe hinzufügen", systemImage: "folder.badge.plus")
                }
                #if DEBUG
                if isDebugMode {
                    Button(action: {
                        PersistenceController.shared.resetCoreData()
                        print("Core Data zurückgesetzt")
                    }) {
                        Label("Core Data zurücksetzen (Debug)", systemImage: "trash")
                    }
                    Button(action: {
                        authManager.resetUserDefaults()
                        print("UserDefaults zurückgesetzt")
                    }) {
                        Label("UserDefaults zurücksetzen (Debug)", systemImage: "gear")
                    }
                }
                #endif
                Divider()
                Button(action: {
                    showAboutView = true
                }) {
                    Label("Über EuroBlick", systemImage: "info.circle")
                }
            } label: {
                Image(systemName: "plus")
                    .foregroundColor(.white)
            }
            .onAppear {
                print("Rendering ContentToolbar")
            }
        }
    }
}

// View für die Hauptinhalte (Kontogruppen)
struct ContentMainView: View {
    let accountGroups: [AccountGroup]
    let balances: [AccountBalance]
    let viewModel: TransactionViewModel
    @Binding var showAddGroupSheet: Bool
    @Binding var showSelectGroupSheet: Bool
    @Binding var showEditGroupSheet: Bool
    @Binding var groupToEdit: AccountGroup?
    @Binding var newGroupName: String

    var body: some View {
        if accountGroups.isEmpty {
            VStack {
                Text("Keine Kontogruppen vorhanden")
                    .foregroundColor(.white)
                    .font(.headline)
                Text("Tippe auf das Plus-Symbol (+), um eine Kontogruppe hinzuzufügen.")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        } else {
            VStack {
                ForEach(accountGroups) { group in
                    AccountGroupView(
                        group: group,
                        viewModel: viewModel,
                        balances: balances,
                        showEditGroupSheet: $showEditGroupSheet,
                        groupToEdit: $groupToEdit,
                        newGroupName: $newGroupName
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deleteAccountGroup(group)
                            print("Löschen von Kontogruppe \(group.name ?? "unknown") ausgelöst")
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel: TransactionViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var showAddSheet = false
    @State private var showAddGroupSheet = false
    @State private var showAddAccountSheet = false
    @State private var showSelectGroupSheet = false
    @State private var showEditGroupSheet = false
    @State private var showAboutView = false
    @State private var groupToEdit: AccountGroup?
    @State private var newGroupName = ""
    @State private var accountName = ""
    @State private var accountBalances: [AccountBalance] = []
    @State private var didLoadInitialData = false
    // Zustände für die Bestätigungsalerts
    @State private var showBackupAlert = false
    @State private var showRestoreAlert = false

    // Manuelle Steuerung für Debug-Buttons
    private let isDebugMode = true // Aktiviere Debug-Buttons

    init() {
        let newViewModel = TransactionViewModel()
        self._viewModel = StateObject(wrappedValue: newViewModel)
        
        // Initialisierung im Konstruktor
        //newViewModel.fetchAccountGroups()
        //newViewModel.fetchCategories()
        
        // Bereinige die Datenbank vor der Synchronisation
        //newViewModel.cleanInvalidTransactions()
        // Temporäre manuelle Bereinigung
        //newViewModel.forceCleanInvalidTransactions()
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ContentView

        init(parent: ContentView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            if parent.viewModel.restoreData(from: url) {
                print("Wiederherstellung erfolgreich")
            } else {
                print("Wiederherstellung fehlgeschlagen")
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("Dokumentauswahl abgebrochen")
        }
    }

    func makeCoordinator(parent: ContentView) -> Coordinator {
        Coordinator(parent: parent)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Titel mit Wallet-Icon
                HStack(spacing: 12) {
                    Image(systemName: "wallet.pass.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                    Text("Konten")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                // Hauptinhalt
                VStack {
                    AppLogoView()
                    ContentMainView(
                        accountGroups: viewModel.accountGroups,
                        balances: accountBalances,
                        viewModel: viewModel,
                        showAddGroupSheet: $showAddGroupSheet,
                        showSelectGroupSheet: $showSelectGroupSheet,
                        showEditGroupSheet: $showEditGroupSheet,
                        groupToEdit: $groupToEdit,
                        newGroupName: $newGroupName
                    )
                    .padding(.bottom, 20)
                }
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        authManager.logout()
                        print("Abmelden ausgelöst")
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                                .font(.system(size: 16))
                            Text("Abmelden")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.2))
                        )
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            showSelectGroupSheet = true
                            print("Konto hinzufügen ausgelöst")
                        }) {
                            Label("Konto hinzufügen", systemImage: "creditcard")
                        }
                        Button(action: {
                            showAddGroupSheet = true
                            print("Kontogruppe hinzufügen ausgelöst")
                        }) {
                            Label("Kontogruppe hinzufügen", systemImage: "folder.badge.plus")
                        }
                        #if DEBUG
                        if isDebugMode {
                            Button(action: {
                                PersistenceController.shared.resetCoreData()
                                print("Core Data zurückgesetzt")
                            }) {
                                Label("Core Data zurücksetzen (Debug)", systemImage: "trash")
                            }
                            Button(action: {
                                authManager.resetUserDefaults()
                                print("UserDefaults zurückgesetzt")
                            }) {
                                Label("UserDefaults zurücksetzen (Debug)", systemImage: "gear")
                            }
                        }
                        #endif
                        Divider()
                        Button(action: {
                            showAboutView = true
                        }) {
                            Label("Über EuroBlick", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                    }
                }

                // Toolbar für die untere Leiste
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        // Backup wiederherstellen
                        Button(action: {
                            showRestoreAlert = true
                        }) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.gray)
                                .padding(8)
                        }
                        .alert("Backup wiederherstellen?", isPresented: $showRestoreAlert) {
                            Button("Ja", role: .destructive) {
                                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                                let meinDrivePath = documentsDirectory.appendingPathComponent("MeinDrive")

                                do {
                                    let files = try FileManager.default.contentsOfDirectory(at: meinDrivePath, includingPropertiesForKeys: nil)
                                    let backupFiles = files.filter { $0.lastPathComponent.hasPrefix("EuroBlickBackup_") && $0.pathExtension == "json" }

                                    if let latestBackupFile = backupFiles.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first {
                                        print("Neueste Backup-Datei gefunden: \(latestBackupFile.path)")
                                        let restored = viewModel.restoreData(from: latestBackupFile)
                                        if restored {
                                            print("Wiederherstellung erfolgreich")
                                            refreshBalances()
                                        } else {
                                            print("Wiederherstellung fehlgeschlagen")
                                        }
                                    } else {
                                        print("Keine Backup-Datei gefunden")
                                    }
                                } catch {
                                    print("Fehler beim Abrufen der Dateien aus MeinDrive: \(error.localizedDescription)")
                                }
                            }
                            Button("Abbrechen", role: .cancel) {
                                print("Wiederherstellung abgebrochen")
                            }
                        } message: {
                            Text("Möchtest du wirklich das letzte Backup wiederherstellen? Alle aktuellen Daten werden überschrieben.")
                        }

                        // Backup erstellen
                        Button(action: {
                            showBackupAlert = true
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.gray)
                                .padding(8)
                        }
                        .alert("Backup erstellen?", isPresented: $showBackupAlert) {
                            Button("Ja", role: .destructive) {
                                if let backupURL = viewModel.backupData() {
                                    let activityController = UIActivityViewController(activityItems: [backupURL], applicationActivities: nil)
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let rootViewController = windowScene.windows.first?.rootViewController {
                                        rootViewController.present(activityController, animated: true, completion: nil)
                                    }
                                    print("Backup erfolgreich erstellt: \(backupURL)")
                                } else {
                                    print("Fehler beim Erstellen des Backups")
                                }
                            }
                            Button("Abbrechen", role: .cancel) {
                                print("Backup-Erstellung abgebrochen")
                            }
                        } message: {
                            Text("Möchtest du wirklich ein neues Backup erstellen?")
                        }

                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAboutView) {
                AboutView()
            }
            .sheet(isPresented: $showAddGroupSheet) {
                AddAccountGroupView(viewModel: viewModel)
                    .onDisappear {
                        viewModel.refreshContextIfNeeded()
                        viewModel.fetchAccountGroups()
                        refreshBalances()
                        print("AddAccountGroupView geschlossen")
                    }
            }
            .sheet(isPresented: $showSelectGroupSheet) {
                SelectAccountGroupView(viewModel: viewModel, showAddAccountSheet: $showAddAccountSheet, groupToEdit: $groupToEdit)
                    .onDisappear {
                        viewModel.refreshContextIfNeeded()
                        viewModel.fetchAccountGroups()
                        refreshBalances()
                        print("SelectAccountGroupView geschlossen")
                    }
            }
            .sheet(isPresented: $showAddAccountSheet) {
                if let group = groupToEdit {
                    AddAccountView(viewModel: viewModel, group: group)
                        .onDisappear {
                            viewModel.refreshContextIfNeeded()
                            viewModel.fetchAccountGroups()
                            refreshBalances()
                            print("AddAccountView geschlossen")
                        }
                }
            }
            .sheet(isPresented: $showEditGroupSheet) {
                if let group = groupToEdit {
                    EditAccountGroupView(viewModel: viewModel, group: group, newGroupName: $newGroupName)
                        .onDisappear {
                            viewModel.refreshContextIfNeeded()
                            viewModel.fetchAccountGroups()
                            refreshBalances()
                            print("EditAccountGroupView geschlossen")
                        }
                }
            }
            .onAppear {
                guard !didLoadInitialData else { return }
                didLoadInitialData = true
                print("📦 Initialdaten werden geladen …")
                viewModel.fetchAccountGroups()
                viewModel.fetchCategories()
                viewModel.cleanInvalidTransactions()
                viewModel.forceCleanInvalidTransactions()
                refreshBalances()
            }
            .onChange(of: viewModel.accountGroups) { _, _ in
                print("Kontogruppen aktualisiert: \(viewModel.accountGroups.count) Gruppen")
                refreshBalances()
            }
            .onChange(of: viewModel.transactionsUpdated) { _, _ in
                refreshBalances() // Aktualisiere Kontostände, wenn Transaktionen geändert werden
                print("Kontostände aktualisiert bei Transaktionsänderung: \(accountBalances.count) Konten")
            }
        }
    }

    private func refreshBalances() {
        DispatchQueue.global(qos: .userInitiated).async {
            let allBalances = viewModel.calculateAllBalances()
            var newBalances: [AccountBalance] = []

            for group in viewModel.accountGroups {
                let accounts = (group.accounts?.allObjects as? [Account]) ?? []
                for account in accounts {
                    let balance = allBalances[account.objectID] ?? 0.0
                    newBalances.append(AccountBalance(id: account.objectID, name: account.name ?? "Unbekanntes Konto", balance: balance))
                }
            }

            DispatchQueue.main.async {
                accountBalances = newBalances
                print("Kontostände aktualisiert: \(newBalances.count) Konten")
            }
        }
    }
}
// MARK: - Subviews

struct EditAccountGroupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TransactionViewModel
    let group: AccountGroup
    @Binding var newGroupName: String

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Kontogruppe bearbeiten").foregroundColor(.white)) {
                    TextField("Neuer Gruppenname", text: $newGroupName)
                        .foregroundColor(.black)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(5)
                }
            }
            .background(Color.black)
            .scrollContentBackground(.hidden)
            .navigationTitle("Kontogruppe bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        viewModel.updateAccountGroup(group: group, name: newGroupName)
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .disabled(newGroupName.isEmpty)
                }
            }
            .onAppear {
                print("EditAccountGroupView erschienen für \(group.name ?? "unknown")")
            }
        }
    }
}

// Neues View für das Logo
struct AppLogoView: View {
    var body: some View {
        HStack {
            Image(systemName: "eurosign.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundColor(.blue)
            Text("EuroBlick")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .bold()
        }
        .padding()
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = TransactionViewModel(context: context)
    ContentView()
        .environment(\.managedObjectContext, context)
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
