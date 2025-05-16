import SwiftUI
import CoreData
import UniformTypeIdentifiers // Für UIDocumentPickerViewController
import UIKit // Für UIImpactFeedbackGenerator

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

// IconSelectionView
struct IconSelectionView: View {
    let selectedIcon: String
    let selectedColor: Color
    let onIconSelected: (String) -> Void
    
    private let availableIcons = [
        "banknote.fill",
        "building.columns.fill",
        "person.circle.fill",
        "creditcard.fill",
        "wallet.pass.fill",
        "eurosign.circle.fill",
        "dollarsign.circle.fill",
        "lock.fill"
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(availableIcons, id: \.self) { icon in
                    Button(action: {
                        onIconSelected(icon)
                    }) {
                        Image(systemName: icon)
                            .font(.system(size: 24))
                            .foregroundColor(selectedIcon == icon ? selectedColor : .gray)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(selectedIcon == icon ? Color.gray.opacity(0.3) : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.black)
    }
}

// ColorSelectionView
struct ColorSelectionView: View {
    let selectedColor: Color
    let onColorSelected: (Color) -> Void
    
    private let availableColors: [Color] = [
        .blue, .green, .orange, .red, .purple, .yellow, .gray
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(availableColors, id: \.self) { color in
                    Button(action: {
                        onColorSelected(color)
                    }) {
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.black)
    }
}

// EditAccountView
struct EditAccountView: View {
    @Environment(\.dismiss) var dismiss
    let viewModel: TransactionViewModel
    let account: Account
    let onSave: () -> Void  // Neuer Callback
    
    @State private var accountName: String
    @State private var selectedIcon: String
    @State private var selectedColor: Color
    
    init(viewModel: TransactionViewModel, account: Account, onSave: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.account = account
        self.onSave = onSave
        _accountName = State(initialValue: account.name ?? "")
        _selectedIcon = State(initialValue: account.value(forKey: "icon") as? String ?? "building.columns.fill")
        _selectedColor = State(initialValue: Color(hex: account.value(forKey: "iconColor") as? String ?? "#007AFF") ?? .blue)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Kontodetails").foregroundColor(.white)) {
                    TextField("Kontoname", text: $accountName)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                    
                    IconSelectionView(
                        selectedIcon: selectedIcon,
                        selectedColor: selectedColor,
                        onIconSelected: { icon in
                            selectedIcon = icon
                            print("Icon selected: \(icon)")
                        }
                    )
                    
                    ColorSelectionView(
                        selectedColor: selectedColor,
                        onColorSelected: { color in
                            selectedColor = color
                            print("Color selected: \(color.toHex())")
                        }
                    )
                }
                .listRowBackground(Color.black)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .preferredColorScheme(.dark)
            .navigationTitle("Konto bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        saveChanges()
                    }
                    .disabled(accountName.isEmpty)
                }
            }
        }
    }
    
    private func saveChanges() {
        print("Saving changes...")
        print("Name: \(accountName)")
        print("Icon: \(selectedIcon)")
        print("Color: \(selectedColor.toHex())")
        
        account.name = accountName
        account.setValue(selectedIcon, forKey: "icon")
        account.setValue(selectedColor.toHex(), forKey: "iconColor")
        
        if let context = account.managedObjectContext {
            do {
                try context.save()
                print("Changes saved successfully")
                
                // Aktualisiere ViewModel und UI
                viewModel.objectWillChange.send()
                viewModel.refreshContextIfNeeded()
                viewModel.fetchAccountGroups()
                
                // Rufe den onSave callback auf
                onSave()
                
                // Verzögerte UI-Aktualisierung
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.objectWillChange.send()
                }
                
                dismiss()
            } catch {
                print("Error saving changes: \(error)")
            }
        } else {
            print("No managed object context found")
        }
    }
}

// Erweitere Color um Hex-Unterstützung
extension Color {
    func toHex() -> String {
        let components = UIColor(self).cgColor.components
        let r = components?[0] ?? 0
        let g = components?[1] ?? 0
        let b = components?[2] ?? 0
        
        return String(
            format: "#%02lX%02lX%02lX",
            lroundf(Float(r * 255)),
            lroundf(Float(g * 255)),
            lroundf(Float(b * 255))
        )
    }
}

// Hilfsklasse für haptisches Feedback
enum HapticManager {
    static func impact() {
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
    }
}

// Modifiziere AccountRowView
struct AccountRowView: View {
    let account: Account
    let balance: Double
    let viewModel: TransactionViewModel
    @State private var showEditSheet = false
    @State private var navigateToTransactions = false
    @State private var refreshToggle = false  // Neuer State für Force-Refresh

    private var accountIcon: (systemName: String, color: Color) {
        // Force view refresh when refreshToggle changes
        _ = refreshToggle
        let icon = account.value(forKey: "icon") as? String ?? "building.columns.fill"
        let colorHex = account.value(forKey: "iconColor") as? String ?? "#007AFF"
        return (icon, Color(hex: colorHex) ?? .blue)
    }

    var body: some View {
        NavigationStack {
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
            .contentShape(Rectangle())
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
            )
            .onTapGesture {
                navigateToTransactions = true
            }
            .navigationDestination(isPresented: $navigateToTransactions) {
                TransactionView(account: account, viewModel: viewModel)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    showEditSheet = true
                }
        )
        .padding(.horizontal)
        .sheet(isPresented: $showEditSheet, onDismiss: {
            // Force refresh on dismiss
            refreshToggle.toggle()
            viewModel.objectWillChange.send()
            viewModel.refreshContextIfNeeded()
            
            // Verzögerte zweite Aktualisierung für sicherere UI-Updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                refreshToggle.toggle()
                viewModel.objectWillChange.send()
            }
        }) {
            EditAccountView(viewModel: viewModel, account: account, onSave: {
                // Force refresh on save
                refreshToggle.toggle()
            })
        }
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
                    .font(.title2)
                    .padding(.trailing, 4)
                Text(group.name ?? "Unbekannte Gruppe")
                    .font(.title2)
                    .foregroundColor(.white)
                    .bold()
                Spacer()
                Text("\(String(format: "%.2f €", groupBalance))")
                    .foregroundColor(groupBalance >= 0 ? Color.green : Color.red)
                    .font(.subheadline) // Gleiche Größe wie Kontosalden
                Button(action: {
                    groupToEdit = group
                    newGroupName = group.name ?? ""
                    showEditGroupSheet = true
                    print("Bearbeiten von Kontogruppe \(group.name ?? "unknown") ausgelöst")
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
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
                    .padding(.vertical, 2)
            }

            // Trennlinie und BK-Konten
            if !bkAccounts.isEmpty {
                Divider()
                    .background(Color.gray.opacity(0.5))
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                ForEach(bkAccounts, id: \.account.objectID) { item in
                    AccountRowView(account: item.account, balance: item.balance, viewModel: viewModel)
                        .padding(.vertical, 2)
                }
            }

            // Link zu Auswertungen
            NavigationLink(
                destination: EvaluationView(accounts: accountBalances.map { $0.account }, viewModel: viewModel)
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                    Text("Auswertung")
                        .font(.system(size: 15))
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    Group {
                        if (group.name ?? "").lowercased().contains("kaffee") {
                            Color.brown
                        } else if (group.name ?? "").lowercased().contains("drinks") {
                            Color.purple
                        } else {
                            Color.blue
                        }
                    }
                )
                .cornerRadius(8)
                .shadow(radius: 2)
            }
            .padding(.horizontal)
            .padding(.top, 5)
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
                    .font(.system(size: 20))
            }
            .foregroundStyle(.white)
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
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
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Titel mit Wallet-Icon
                    HStack(spacing: 12) {
                        Image(systemName: "wallet.pass.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 24))
                        Text("Konten")
                            .foregroundColor(.white)
                            .font(.title)
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ContentToolbar(
                    showAddSheet: $showAddSheet,
                    showAddGroupSheet: $showAddGroupSheet,
                    showSelectGroupSheet: $showSelectGroupSheet,
                    showAboutView: $showAboutView
                )
            }
        }
        .preferredColorScheme(.dark)
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
                .frame(width: 40, height: 40) // Behalte die Größe, aber füge .scaledToFit() hinzu
                .foregroundColor(.blue)
            Text("EuroBlick")
                .font(.title)
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
