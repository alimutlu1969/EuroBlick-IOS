import SwiftUI
import CoreData
import UniformTypeIdentifiers // Für UIDocumentPickerViewController
import UIKit // Für UIImpactFeedbackGenerator

fileprivate func formatBalance(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "de_DE")
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    
    let number = NSNumber(value: abs(amount))
    let formattedAmount = formatter.string(from: number) ?? String(format: "%.2f", abs(amount))
    return amount >= 0 ? "\(formattedAmount) €" : "-\(formattedAmount) €"
}

struct AuthenticationView: View {
    @Binding var isAuthenticated: Bool
    @EnvironmentObject var authManager: AuthenticationManager // Verwende den AuthenticationManager
    @State private var errorMessage: String? // Für Fehlermeldungen bei fehlgeschlagener Authentifizierung

    var body: some View {
        VStack {
            Text("Bitte authentifizieren")
                .font(.system(size: AppFontSize.sectionTitle))
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: AppFontSize.bodySmall))
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
            .font(.system(size: AppFontSize.bodyLarge))
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
                            .font(.system(size: AppFontSize.groupIcon))
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
    let onSave: () -> Void
    
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
                Section(header: Text("Kontodetails").foregroundColor(.primary)) {
                    TextField("Kontoname", text: $accountName)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .foregroundColor(.primary)
                    
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
    @State private var refreshToggle = false
    @State private var showDeleteConfirmation = false
    @State private var showContextMenu = false

    private var accountIcon: (systemName: String, color: Color) {
        _ = refreshToggle // Force view update when refreshToggle changes
        let icon = account.value(forKey: "icon") as? String ?? "building.columns.fill"
        let colorHex = account.value(forKey: "iconColor") as? String ?? "#007AFF"
        return (icon, Color(hex: colorHex) ?? .blue)
    }
    
    private func getSafeAccountName(_ account: Account) -> String {
        // NEUE STRATEGIE: ViewModel-basierte Namensauflösung
        // Das vermeidet Core Data Objektreferenz-Probleme komplett
        
        // 1. Versuche über ViewModel (aktuellste Objektreferenzen)
        let viewModelName = getAccountNameFromViewModel(account)
        if !viewModelName.isEmpty && viewModelName != "Unbekanntes Konto" {
            // Reset Fault-Counter bei erfolgreichem ViewModel-Abruf
            UserDefaults.standard.set(0, forKey: "faultCounter")
            return viewModelName
        }
        
        // 2. Fallback: Direkter Zugriff
        if let directName = account.name, !directName.isEmpty {
            UserDefaults.standard.set(0, forKey: "faultCounter")
            return directName
        }
        
        // 3. Fallback: Value(forKey:) Zugriff
        if let keyName = account.value(forKey: "name") as? String, !keyName.isEmpty {
            return keyName
        }
        
        print("🔍 FAULT: Account \(account.objectID) hat keinen Namen geladen")
        
        // Auto-Fix nach 3 aufeinanderfolgenden Faults
        UserDefaults.standard.set((UserDefaults.standard.integer(forKey: "faultCounter") + 1), forKey: "faultCounter")
        if UserDefaults.standard.integer(forKey: "faultCounter") >= 3 {
            UserDefaults.standard.set(0, forKey: "faultCounter")
            DispatchQueue.main.async {
                // Trigger Auto-Fix über Notification
                NotificationCenter.default.post(name: NSNotification.Name("AutoFixUIFaults"), object: nil)
            }
        }
        
        return "Unbekanntes Konto"
    }
    
    private func getAccountNameFromViewModel(_ account: Account) -> String {
        // Finde Account im ViewModel anhand ObjectID
        for group in viewModel.accountGroups {
            if let accounts = group.accounts?.allObjects as? [Account] {
                for vmAccount in accounts {
                    if vmAccount.objectID == account.objectID {
                        return vmAccount.name ?? ""
                    }
                }
            }
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            HStack {
                Image(systemName: accountIcon.systemName)
                    .foregroundColor(accountIcon.color)
                    .font(.system(size: AppFontSize.contentIcon))
                    .frame(width: 30)
                Text(getSafeAccountName(account))
                    .font(.system(size: (AppFontSize.bodyLarge + AppFontSize.bodyMedium) / 2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                let formattedBalance = formatBalance(balance)
                Text(formattedBalance)
                    .foregroundColor(balance >= 0 ? .green : .red)
                    .font(.system(size: (AppFontSize.bodyMedium + AppFontSize.bodySmall) / 2 + 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .onAppear {
                let formattedBalance = formatBalance(balance)
                print("UI: \(account.name ?? "-") | balance: \(balance) | formatted: \(formattedBalance)")
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(
                            width: min(geometry.size.width, UIScreen.main.bounds.width - 40),
                            height: geometry.size.height
                        )
                }
            )
            .onTapGesture {
                navigateToTransactions = true
            }
            .navigationDestination(isPresented: $navigateToTransactions) {
                TransactionView(account: account, viewModel: viewModel)
            }
            .buttonStyle(PlainButtonStyle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        showContextMenu = true
                    }
            )
            .confirmationDialog(
                "Konto verwalten",
                isPresented: $showContextMenu,
                titleVisibility: .visible
            ) {
                Button("Bearbeiten") {
                    showEditSheet = true
                }
                Button("Löschen", role: .destructive) {
                    showDeleteConfirmation = true
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .padding(.horizontal)
            .sheet(isPresented: $showEditSheet) {
                EditAccountView(viewModel: viewModel, account: account) {
                    // Callback nach dem Speichern
                    DispatchQueue.main.async {
                        refreshToggle.toggle() // Trigger UI update
                        viewModel.objectWillChange.send()
                        viewModel.refreshContextIfNeeded()
                    }
                }
            }
            .confirmationDialog(
                "Konto löschen",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    viewModel.deleteAccount(account)
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Möchten Sie das Konto '\(account.name ?? "")' wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.")
            }
            .id(refreshToggle) // Force view refresh when refreshToggle changes
        }
    }
}

// View für eine einzelne Kontogruppe
struct AccountGroupView: View {
    let group: AccountGroup
    let viewModel: TransactionViewModel
    let balances: [AccountBalance]
    let onAccountTapped: (Account) -> Void
    @Binding var showEditGroupSheet: Bool
    @Binding var groupToEdit: AccountGroup?
    @Binding var newGroupName: String

    @State private var groupBalance: Double = 0.0
    @State private var accountBalances: [(account: Account, balance: Double)] = []
    @State private var expanded: Bool = false
    @State private var showEditAlert = false
    @State private var showSortSheet = false
    @State private var showActionDialog = false
    @State private var showDeleteConfirmation = false
    @State private var editedName = ""
    @State private var showAccountContextMenu = false
    @State private var selectedAccount: (account: Account, balance: Double)? = nil
    @State private var navigateToTransactions = false
    @State private var showEditSheet = false

    private var groupIcon: (systemName: String, color: Color) {
        // Versuche gespeicherte Icon-Daten zu verwenden
        let savedIcon = group.value(forKey: "icon") as? String
        let savedColorHex = group.value(forKey: "iconColor") as? String
        
        if let icon = savedIcon, let colorHex = savedColorHex {
            return (icon, Color(hex: colorHex) ?? .gray)
        }
        
        // Fallback: Intelligente Icon-Auswahl basierend auf Namen (OHNE Auto-Save)
        let groupName = (group.name ?? "").lowercased()
        return getDefaultIconForGroup(groupName)
    }
    
    private func getDefaultIconForGroup(_ groupName: String) -> (String, Color) {
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
    
    private func getSafeGroupName(_ group: AccountGroup) -> String {
        // NEUE STRATEGIE: ViewModel-basierte Namensauflösung
        // Das vermeidet Core Data Objektreferenz-Probleme komplett
        
        // 1. Versuche über ViewModel (aktuellste Objektreferenzen)
        let viewModelName = getGroupNameFromViewModel(group)
        if !viewModelName.isEmpty && viewModelName != "Unbekannte Gruppe" {
            // Reset Fault-Counter bei erfolgreichem ViewModel-Abruf
            UserDefaults.standard.set(0, forKey: "faultCounter")
            return viewModelName
        }
        
        // 2. Fallback: Direkter Zugriff
        if let directName = group.name, !directName.isEmpty {
            UserDefaults.standard.set(0, forKey: "faultCounter")
            return directName
        }
        
        // 3. Fallback: Value(forKey:) Zugriff
        if let keyName = group.value(forKey: "name") as? String, !keyName.isEmpty {
            return keyName
        }
        
        print("🔍 FAULT: AccountGroup \(group.objectID) hat keinen Namen geladen")
        
        // Auto-Fix nach 3 aufeinanderfolgenden Faults
        UserDefaults.standard.set((UserDefaults.standard.integer(forKey: "faultCounter") + 1), forKey: "faultCounter")
        if UserDefaults.standard.integer(forKey: "faultCounter") >= 3 {
            UserDefaults.standard.set(0, forKey: "faultCounter")
            DispatchQueue.main.async {
                // Trigger Auto-Fix über Notification
                NotificationCenter.default.post(name: NSNotification.Name("AutoFixUIFaults"), object: nil)
            }
        }
        
        return "Unbekannte Gruppe"
    }
    
    private func getGroupNameFromViewModel(_ group: AccountGroup) -> String {
        // Finde AccountGroup im ViewModel anhand ObjectID
        for vmGroup in viewModel.accountGroups {
            if vmGroup.objectID == group.objectID {
                return vmGroup.name ?? ""
            }
        }
        return ""
    }

    private var regularAccounts: [(account: Account, balance: Double)] {
        // Sortiere nach order-Feld
        accountBalances.sorted { 
            let o1 = $0.account.value(forKey: "order") as? Int16 ?? 0
            let o2 = $1.account.value(forKey: "order") as? Int16 ?? 0
            return o1 < o2
        }
    }

    private var specialAccounts: [(account: Account, balance: Double)] {
        // Keine speziellen Konten
        []
    }

    private func isAccountIncludedInBalance(_ account: Account) -> Bool {
        return account.value(forKey: "includeInBalance") as? Bool ?? true
    }

    private func toggleAccountBalanceInclusion(_ account: Account) {
        let currentValue = isAccountIncludedInBalance(account)
        account.setValue(!currentValue, forKey: "includeInBalance")
        
        if let context = account.managedObjectContext {
            do {
                try context.save()
                calculateBalances()
            } catch {
                print("Error saving account balance inclusion: \(error)")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Kopf der Karte
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(groupIcon.color.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Image(systemName: groupIcon.systemName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundColor(groupIcon.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(getSafeGroupName(group))
                        .font(.system(size: AppFontSize.groupTitle, weight: .semibold))
                    Text("\(regularAccounts.count + specialAccounts.count) Konten")
                        .font(.caption)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatBalance(groupBalance))
                        .foregroundColor(groupBalance >= 0 ? .green : .red)
                        .font(.system(size: AppFontSize.bodyMedium))
                }
                Button(action: { expanded.toggle() }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.title3)
                }
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.15))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(groupIcon.color.opacity(0.3), lineWidth: 1)
            )
            .onTapGesture { expanded.toggle() }
            .onLongPressGesture {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                showActionDialog = true
            }
            .confirmationDialog(
                "Aktion wählen",
                isPresented: $showActionDialog,
                titleVisibility: .visible
            ) {
                Button("Gruppe umbenennen") {
                    editedName = group.name ?? ""
                    showEditAlert = true
                }
                Button("Konten sortieren") {
                    showSortSheet = true
                }
                Button("Löschen", role: .destructive) {
                    showDeleteConfirmation = true
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .alert("Kontogruppe bearbeiten", isPresented: $showEditAlert) {
                TextField("Name", text: $editedName)
                Button("Abbrechen", role: .cancel) { }
                Button("Speichern") {
                    viewModel.updateAccountGroup(group: group, name: editedName)
                }
            } message: {
                Text("Geben Sie einen neuen Namen für die Kontogruppe ein")
            }
            .alert("Kontogruppe löschen", isPresented: $showDeleteConfirmation) {
                Button("Abbrechen", role: .cancel) { }
                Button("Löschen", role: .destructive) {
                    viewModel.deleteAccountGroup(group)
                }
            } message: {
                Text("Möchten Sie die Kontogruppe '\(group.name ?? "")' wirklich löschen? Alle Konten und Transaktionen in dieser Gruppe werden ebenfalls gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.")
            }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(regularAccounts + specialAccounts, id: \.account.objectID) { item in
                        AccountGroupRowView(
                            item: item,
                            isAccountIncludedInBalance: isAccountIncludedInBalance,
                            onAccountTapped: onAccountTapped,
                            selectedAccount: $selectedAccount,
                            showAccountContextMenu: $showAccountContextMenu,
                            showEditSheet: $showEditSheet
                        )
                        Divider().background(Color.gray)
                    }
                }
                .background(Color(.systemGray6).opacity(0.10))
                .cornerRadius(12)
                .padding(.horizontal, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(groupIcon.color.opacity(0.2), lineWidth: 1)
                )
                .confirmationDialog(
                    "Konto verwalten",
                    isPresented: $showAccountContextMenu,
                    titleVisibility: .visible
                ) {
                    if let account = selectedAccount?.account {
                        Button(isAccountIncludedInBalance(account) ? "Aus Bilanz ausschließen" : "In Bilanz einbeziehen") {
                            toggleAccountBalanceInclusion(account)
                        }
                        Button("Bearbeiten") {
                            showEditSheet = true
                        }
                        Button("Abbrechen", role: .cancel) {}
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .onAppear { calculateBalances() }
        .onChange(of: viewModel.transactionsUpdated) { _, _ in
            calculateBalances()
            viewModel.fetchAccountGroups()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataDidChange"))) { _ in
            print("🔄 AccountGroupView received DataDidChange - recalculating balances for group: \(group.name ?? "-")")
            calculateBalances()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BalanceDataChanged"))) { _ in
            print("🔄 AccountGroupView received BalanceDataChanged - recalculating balances for group: \(group.name ?? "-")")
            calculateBalances()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AutoFixUIFaults"))) { _ in
            print("🔄 AccountGroupView received AutoFixUIFaults - recalculating balances for group: \(group.name ?? "-")")
            calculateBalances()
        }
        .id(group.objectID)
        .sheet(isPresented: $showSortSheet) {
            AccountSortSheet(group: group, onSave: {
                calculateBalances()
                viewModel.fetchAccountGroups()
            })
        }
        .sheet(isPresented: $showEditSheet) {
            if let account = selectedAccount?.account {
                EditAccountView(viewModel: viewModel, account: account) {
                    // Callback nach dem Speichern
                    DispatchQueue.main.async {
                        viewModel.objectWillChange.send()
                        viewModel.refreshContextIfNeeded()
                        viewModel.fetchAccountGroups()
                        calculateBalances()
                    }
                }
            }
        }
    }

    private func calculateBalances() {
        print("🔄 calculateBalances() called for group: \(group.name ?? "-")")
        
        let accounts = (group.accounts?.allObjects as? [Account]) ?? []
        print("🔄 Found \(accounts.count) accounts in group")
        
        accountBalances = accounts
            .sorted { $0.name ?? "" < $1.name ?? "" }
            .map { account in
                // Use viewModel.getBalance directly instead of relying on balances parameter
                let balance = viewModel.getBalance(for: account)
                print("🔄 Account: \(account.name ?? "-") | includeInBalance: \(isAccountIncludedInBalance(account)) | Balance: \(balance)")
                return (account, balance)
            }
        
        // Gruppensaldo = Summe aller eingeschlossenen Konten
        let includedAccounts = accountBalances.filter { isAccountIncludedInBalance($0.account) }
        groupBalance = includedAccounts.reduce(0.0) { total, item in
            total + item.balance
        }
        
        print("🔄 Group: \(group.name ?? "-") | Included accounts: \(includedAccounts.map { $0.account.name ?? "-" }) | GroupBalance: \(groupBalance)")
        
        // Force UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}

struct AccountGroupRowView: View {
    let item: (account: Account, balance: Double)
    let isAccountIncludedInBalance: (Account) -> Bool
    let onAccountTapped: (Account) -> Void
    @Binding var selectedAccount: (account: Account, balance: Double)?
    @Binding var showAccountContextMenu: Bool
    @Binding var showEditSheet: Bool
    
    private func getSafeAccountNameInGroup(_ account: Account) -> String {
        // NEUE STRATEGIE: Vereinfachter ViewModel-basierter Abruf für Gruppen-Konten
        
        // 1. Direkter Zugriff (meist erfolgreich in Gruppen-Kontext)
        if let directName = account.name, !directName.isEmpty {
            UserDefaults.standard.set(0, forKey: "faultCounter")
            return directName
        }
        
        // 2. Value(forKey:) Zugriff
        if let keyName = account.value(forKey: "name") as? String, !keyName.isEmpty {
            return keyName
        }
        
        print("🔍 FAULT: Account \(account.objectID) in group hat keinen Namen geladen")
        return "Unbekanntes Konto"
    }

    var body: some View {
        let icon = item.account.value(forKey: "icon") as? String ?? "building.columns.fill"
        let colorHex = item.account.value(forKey: "iconColor") as? String ?? "#007AFF"
        let formattedBalance = formatBalance(item.balance)
        let accountName = getSafeAccountNameInGroup(item.account)
        let isIncluded = isAccountIncludedInBalance(item.account)
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color(hex: colorHex) ?? .blue)
                .frame(width: 24, height: 24)
            Text(accountName)
                .font(.system(size: (AppFontSize.bodyLarge + AppFontSize.bodyMedium) / 2))
            Spacer()
            Text(formattedBalance)
                .foregroundColor(item.balance >= 0 ? .green : .red)
                .font(.system(size: (AppFontSize.bodyMedium + AppFontSize.bodySmall) / 2 + 0.5))
            if !isIncluded {
                Image(systemName: "slash.circle")
                    .font(.system(size: 16))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onAccountTapped(item.account)
        }
        .onLongPressGesture {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            selectedAccount = item
            showAccountContextMenu = true
        }
        .onAppear {
            print("UI: \(accountName) | balance: \(item.balance) | formatted: \(formattedBalance)")
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
                                .font(.system(size: AppFontSize.appTitle))
                                .bold()
                            Text("Version 1.0.0")
                                .font(.system(size: AppFontSize.bodySmall))
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
                            .font(.system(size: AppFontSize.bodyMedium))
                            .padding(.vertical, 8)
                    }
                    .groupBoxStyle(TransparentGroupBoxStyle())
                    
                    // Copyright
                    GroupBox(label: Text("Rechtliches").bold()) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("© 2025 A.E.M.")
                                .font(.system(size: AppFontSize.bodyMedium))
                            Text("Alle Rechte vorbehalten")
                                .font(.system(size: AppFontSize.bodySmall))
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
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.system(size: AppFontSize.groupIcon))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: AppFontSize.bodyLarge))
                Text(description)
                    .font(.system(size: AppFontSize.bodySmall))
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
            configuration.content
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}

// View für die Hauptinhalte (Kontogruppen)
struct ContentMainView: View {
    let accountGroups: [AccountGroup]
    let balances: [AccountBalance]
    let viewModel: TransactionViewModel
    let onAccountTapped: (Account) -> Void
    @Binding var showAddGroupSheet: Bool
    @Binding var showSelectGroupSheet: Bool
    @Binding var showEditGroupSheet: Bool
    @Binding var groupToEdit: AccountGroup?
    @Binding var newGroupName: String

    var body: some View {
        if accountGroups.isEmpty {
            VStack {
                Text("Keine Kontogruppen vorhanden")
                    .font(.headline)
                Text("Tippe auf das Plus-Symbol (+), um eine Kontogruppe hinzuzufügen.")
                    .font(.caption)
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
                        onAccountTapped: { account in
                            onAccountTapped(account)
                        },
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

// Add this enum before ContentView
enum SheetPresentationState: Equatable, Identifiable {
    case none
    case selectGroup
    case addAccount(group: AccountGroup)
    
    var id: String {
        switch self {
        case .none:
            return "none"
        case .selectGroup:
            return "selectGroup"
        case .addAccount(let group):
            return "addAccount-\(group.objectID)"
        }
    }
    
    static func == (lhs: SheetPresentationState, rhs: SheetPresentationState) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.selectGroup, .selectGroup):
            return true
        case (.addAccount(let lhsGroup), .addAccount(let rhsGroup)):
            return lhsGroup.objectID == rhsGroup.objectID
        default:
            return false
        }
    }
}

// Enum für Hauptansicht
enum MainViewState {
    case accounts
    case analysis(group: AccountGroup?)
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var syncService: SynologyBackupSyncService
    @EnvironmentObject var multiUserManager: MultiUserSyncManager
    @StateObject private var viewModel: TransactionViewModel
    @State private var sheetState: SheetPresentationState = .none
    @State private var showSettingsSheet = false
    @State private var showLogoutAlert = false
    @State private var accountBalances: [AccountBalance] = []
    @State private var showAddAccountGroupSheet = false
    @State private var showSideMenu = false
    @State private var mainViewState: MainViewState = .accounts
    @State private var showGroupSelectionSheet = false
    @State private var selectedAnalysisGroup: AccountGroup? = nil
    @State private var selectedAccount: Account? = nil
    @State private var showEditGroupSheet = false
    @State private var groupToEdit: AccountGroup? = nil
    @State private var newGroupName = ""
    @AppStorage("selectedColorScheme") private var selectedColorScheme: String = "system"
    @AppStorage("accentColor") private var accentColor: String = "orange"
    @State private var showWebDAVAlert = false
    @State private var webDAVAlertMessage = ""
    @State private var webDAVAlertIsError = true
    
    init(context: NSManagedObjectContext) {
        // Stelle sicher, dass der Context gültig ist
        do {
            // Teste ob der Context funktioniert
            _ = try context.count(for: NSFetchRequest<Account>(entityName: "Account"))
            _viewModel = StateObject(wrappedValue: TransactionViewModel(context: context))
        } catch {
            print("Core Data Context nicht bereit: \(error)")
            // Erstelle einen temporären Context als Fallback
            let tempContext = PersistenceController.shared.container.viewContext
            _viewModel = StateObject(wrappedValue: TransactionViewModel(context: tempContext))
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: {
                    withAnimation { showSideMenu.toggle() }
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Menu {
                    Button(action: { sheetState = .selectGroup }) {
                        Label("Konto hinzufügen", systemImage: "creditcard")
                    }
                    Button(action: { showAddAccountGroupSheet = true }) {
                        Label("Kontogruppe hinzufügen", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 36)
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "eurosign.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.blue)
                    Text("EuroBlick")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    private var accountGroupsListWithNavigation: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                ForEach(viewModel.accountGroups) { group in
                    AccountGroupView(
                        group: group,
                        viewModel: viewModel,
                        balances: accountBalances,
                        onAccountTapped: { account in selectedAccount = account },
                        showEditGroupSheet: $showEditGroupSheet,
                        groupToEdit: $groupToEdit,
                        newGroupName: $newGroupName
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deleteAccountGroup(group)
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .refreshable {
            await refreshAllData()
        }
    }
    
    @MainActor
    private func refreshAllData() async {
        print("🔄 Pull-to-refresh triggered - NON-FAULT refresh...")
        
        // KRITISCH: KEIN context.reset() oder refreshAllObjects() - das macht Faults!
        // Stattdessen: Sanfte Datenaktualisierung
        
        // 1. Fetch neue Daten ohne Context-Reset
        viewModel.fetchAccountGroups()
        viewModel.fetchCategories()
        
        // 2. Berechne Kontostände neu 
        refreshBalances()
        
        // 3. UI-Update
        viewModel.objectWillChange.send()
        
        print("✅ NON-FAULT pull-to-refresh completed")
    }
    
    private var mainView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ContentMainView(
                accountGroups: viewModel.accountGroups,
                balances: accountBalances,
                viewModel: viewModel,
                onAccountTapped: { account in selectedAccount = account },
                showAddGroupSheet: $showAddAccountGroupSheet,
                showSelectGroupSheet: $showGroupSelectionSheet,
                showEditGroupSheet: $showEditGroupSheet,
                groupToEdit: $groupToEdit,
                newGroupName: $newGroupName
            )
            .padding(.bottom, 20)
        }
        .refreshable {
            await refreshAllData()
        }
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                VStack(spacing: 0) {
                    if case .accounts = mainViewState {
                        headerView
                    }
                    Group {
                        switch mainViewState {
                        case .accounts:
                            accountGroupsListWithNavigation
                        case .analysis(let group):
                            if let group = group {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Button(action: { mainViewState = .accounts }) {
                                            Image(systemName: "chevron.left")
                                                .font(.system(size: 20, weight: .medium))
                                                .padding(.trailing, 4)
                                        }
                                        Text(group.name ?? "Auswertung")
                                            .font(.headline)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.top, 12)
                                    EvaluationMenuView(accounts: (group.accounts?.allObjects as? [Account]) ?? [], viewModel: viewModel)
                                }
                            } else {
                                VStack {
                                    HStack {
                                        Button(action: { mainViewState = .accounts }) {
                                            Image(systemName: "chevron.left")
                                                .font(.system(size: 20, weight: .medium))
                                                .padding(.trailing, 4)
                                        }
                                        Text("Auswertung")
                                            .font(.headline)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.top, 12)
                                    
                                    Spacer()
                                    Text("Keine Kontogruppe ausgewählt")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Button(action: { showGroupSelectionSheet = true }) {
                                        Text("Kontogruppe auswählen")
                                            .foregroundColor(.blue)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .background(Color.black)
                .navigationDestination(item: $selectedAccount) { account in
                    TransactionView(account: account, viewModel: viewModel)
                }
                .toolbar {
                    // Sync-Buttons entfernt - Backup/Restore wird über andere Wege gehandhabt
                }
                .onChange(of: viewModel.transactionsUpdated) { _, _ in
                    refreshBalances()
                    print("Kontostände aktualisiert bei Transaktionsänderung: \(accountBalances.count) Konten")
                    
                    // Neue automatische Synchronisation - prüft lokale Änderungen und synchronisiert wenn nötig
                    Task {
                        print("🔄 Triggering sync check due to transaction changes...")
                        // Der Sync-Service wird automatisch prüfen, ob lokale Änderungen vorhanden sind
                        // und diese entsprechend hochladen
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataDidChange"))) { _ in
                    print("🔄 DataDidChange notification received - refreshing balances...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.refreshBalances()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BalanceDataChanged"))) { _ in
                    print("🔄 BalanceDataChanged notification received - refreshing balances...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.refreshBalances()
                    }
                }
                .onAppear {
                    NotificationCenter.default.addObserver(forName: NSNotification.Name("SideMenuShowSettings"), object: nil, queue: .main) { _ in
                        showSettingsSheet = true
                    }
                    NotificationCenter.default.addObserver(forName: NSNotification.Name("SideMenuShowAnalysis"), object: nil, queue: .main) { _ in
                        if viewModel.accountGroups.isEmpty {
                            mainViewState = .accounts
                        } else {
                            mainViewState = .analysis(group: nil)
                            showGroupSelectionSheet = true
                        }
                        showSideMenu = false
                    }
                    // Bereinige die fehlerhafte Bankgebühren-Kategorie
                    viewModel.cleanupBankgebuehrenCategory()
                    
                    // Bereinige SB-Zahlungen und markiere sie als Umbuchungen
                    viewModel.cleanupSBZahlungen()
                    
                    // WebDAV Benachrichtigungen
                    NotificationCenter.default.addObserver(forName: Notification.Name("WebDAVError"), object: nil, queue: .main) { notification in
                        if let message = notification.userInfo?["message"] as? String {
                            webDAVAlertMessage = message
                            webDAVAlertIsError = true
                            showWebDAVAlert = true
                        }
                    }
                    
                    NotificationCenter.default.addObserver(forName: Notification.Name("WebDAVSuccess"), object: nil, queue: .main) { notification in
                        if let message = notification.userInfo?["message"] as? String {
                            webDAVAlertMessage = message
                            webDAVAlertIsError = false
                            showWebDAVAlert = true
                        }
                    }
                }
                .sheet(isPresented: $showSettingsSheet) {
                    SettingsView()
                        .environmentObject(authManager)
                }
                .sheet(isPresented: $showGroupSelectionSheet) {
                    GroupSelectionSheet(groups: viewModel.accountGroups) { group in
                        mainViewState = .analysis(group: group)
                    }
                }
                // Sheet für das Hinzufügen einer neuen Kontogruppe
                .sheet(isPresented: $showAddAccountGroupSheet) {
                    AddAccountGroupView(viewModel: viewModel)
                }
                // Sheet für sheetState (Kontoauswahl und Hinzufügen)
                .sheet(item: Binding<SheetPresentationState?>(
                    get: { sheetState == .none ? nil : sheetState },
                    set: { sheetState = $0 ?? .none }
                )) { state in
                    switch state {
                    case .selectGroup:
                        SelectGroupForAccountView(
                            groups: viewModel.accountGroups,
                            onSelect: { group in
                                sheetState = .addAccount(group: group)
                            }
                        )
                    case .addAccount(let group):
                        AddAccountView(viewModel: viewModel, group: group)
                    case .none:
                        EmptyView()
                    }
                }
            }
            if showSideMenu {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { showSideMenu = false }
                    }
            }
            if showSideMenu {
                SideMenuView(showSideMenu: $showSideMenu)
                    .environmentObject(authManager)
                    .environmentObject(syncService)
                    .environmentObject(multiUserManager)
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
        }
        .fixKeyboardAssistant()
        // Farbschema und Akzentfarbe global anwenden
        .preferredColorScheme(selectedColorScheme == "light" ? .light : selectedColorScheme == "dark" ? .dark : nil)
        .accentColor(colorFromString(accentColor))
        .alert(isPresented: $showWebDAVAlert) {
            Alert(
                title: Text(webDAVAlertIsError ? "WebDAV Fehler" : "WebDAV Backup"),
                message: Text(webDAVAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func refreshBalances() {
        print("🔄 refreshBalances() called - viewModel.accountGroups.count: \(viewModel.accountGroups.count)")
        
        // Force fetch account groups first to ensure we have the latest data
        viewModel.fetchAccountGroups()
        
        // Wait a moment for the fetch to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let allBalances = self.viewModel.calculateAllBalances()
            var newBalances: [AccountBalance] = []
            
            print("🔄 refreshBalances() after fetch - viewModel.accountGroups.count: \(self.viewModel.accountGroups.count)")
            
            // Calculate group balances and force UI update
            for group in self.viewModel.accountGroups {
                let accounts = (group.accounts?.allObjects as? [Account]) ?? []
                print("🔄 Gruppe: \(group.name ?? "-") | Konten: \(accounts.map { $0.name ?? "-" })")
                
                // Calculate group balance
                var groupBalance: Double = 0.0
                for account in accounts {
                    let balance = allBalances[account.objectID] ?? self.viewModel.getBalance(for: account)
                    let includeInBalance = account.value(forKey: "includeInBalance") as? Bool ?? true
                    print("🔄   Konto: \(account.name ?? "-") | Balance: \(balance) | includeInBalance: \(includeInBalance)")
                    
                    if includeInBalance {
                        groupBalance += balance
                    }
                    newBalances.append(AccountBalance(id: account.objectID, name: account.name ?? "Unbekanntes Konto", balance: balance))
                }
                print("🔄   Group Balance for \(group.name ?? "-"): \(groupBalance)")
            }
            
            self.accountBalances = newBalances
            print("🔄 refreshBalances() completed - accountBalances.count: \(newBalances.count)")
            
            // Force UI update for all AccountGroupViews
            DispatchQueue.main.async {
                self.viewModel.objectWillChange.send()
                NotificationCenter.default.post(name: NSNotification.Name("BalanceDataChanged"), object: nil)
            }
        }
    }

    private func migrateExistingAccounts() {
        let context = viewModel.getContext()
        let fetchRequest: NSFetchRequest<Account> = Account.fetchRequest()
        
        do {
            let accounts = try context.fetch(fetchRequest)
            var updated = false
            
            for account in accounts {
                if account.value(forKey: "type") == nil || (account.value(forKey: "type") as? String) == "" {
                    let accountName = account.name?.lowercased() ?? ""
                    
                    if accountName.contains("giro") || accountName.contains("banka") {
                        account.setValue("bankkonto", forKey: "type")
                        updated = true
                    } else if accountName.contains("bar") || accountName.contains("kasse") {
                        account.setValue("bargeld", forKey: "type")
                        updated = true
                    } else {
                        account.setValue("offline", forKey: "type")
                        updated = true
                    }
                }
            }
            
            if updated {
                try context.save()
            }
        } catch {
            print("Fehler bei der Migration von Konten: \(error.localizedDescription)")
        }
    }

    // Hilfsfunktion für Akzentfarbe
    private func colorFromString(_ name: String) -> Color {
        switch name.lowercased() {
        case "orange": return .orange
        case "blau": return .blue
        case "grün": return .green
        case "rot": return .red
        case "lila": return .purple
        default: return .accentColor
        }
    }
}

// MARK: - Subviews

struct EditAccountGroupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TransactionViewModel
    let group: AccountGroup
    @State private var editedName: String
    
    init(viewModel: TransactionViewModel, group: AccountGroup) {
        self.viewModel = viewModel
        self.group = group
        // Initialize the state property directly
        self._editedName = State(initialValue: group.name ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    TextField("Neuer Gruppenname", text: $editedName)
                        .foregroundColor(.primary)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                .padding(.top)
            }
            .navigationTitle("Kontogruppe bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { 
                        dismiss() 
                    }
                    .foregroundColor(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        viewModel.updateAccountGroup(group: group, name: editedName)
                        dismiss()
                    }
                    .foregroundColor(.primary)
                    .disabled(editedName.isEmpty)
                }
            }
        }
        .onAppear {
            // Ensure the name is set when the view appears
            editedName = group.name ?? ""
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
                .foregroundColor(.primary)
                .bold()
        }
        .padding()
    }
}

struct AccountListView: View {
    @ObservedObject var viewModel: TransactionViewModel
    @State private var accountBalances: [AccountBalance] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(viewModel.accountGroups) { group in
                    AccountGroupView(
                        group: group,
                        viewModel: viewModel,
                        balances: accountBalances,
                        onAccountTapped: { _ in },
                        showEditGroupSheet: .constant(false),
                        groupToEdit: .constant(nil),
                        newGroupName: .constant("")
                    )
                }
            }
            .padding(.vertical)
        }
        .onAppear {
            refreshBalances()
        }
        .onChange(of: viewModel.transactionsUpdated) { _, _ in
            refreshBalances()
        }
    }
    
    private func refreshBalances() {
        let allBalances = viewModel.calculateAllBalances()
        var newBalances: [AccountBalance] = []
        
        for group in viewModel.accountGroups {
            let accounts = (group.accounts?.allObjects as? [Account]) ?? []
            for account in accounts {
                let balance = allBalances[account.objectID] ?? viewModel.getBalance(for: account)
                newBalances.append(AccountBalance(id: account.objectID, name: account.name ?? "Unbekanntes Konto", balance: balance))
            }
        }
        
        accountBalances = newBalances
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @AppStorage("webdavURL") private var webdavURL: String = ""
    @AppStorage("webdavUser") private var webdavUser: String = ""
    @AppStorage("webdavPassword") private var webdavPassword: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Allgemein").foregroundColor(.primary)) {
                    NavigationLink(destination: AboutView()) {
                        Label("Über EuroBlick", systemImage: "info.circle")
                            .foregroundColor(.primary)
                    }
                }
                
                Section(header: Text("WebDAV-Backup").foregroundColor(.primary)) {
                    TextField("WebDAV-URL", text: $webdavURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .foregroundColor(.primary)
                    TextField("Benutzername", text: $webdavUser)
                        .autocapitalization(.none)
                        .foregroundColor(.primary)
                    SecureField("Passwort", text: $webdavPassword)
                        .foregroundColor(.primary)
                }
                
                Section(header: Text("Sicherheit").foregroundColor(.primary)) {
                    Button(action: {
                        authManager.logout()
                        dismiss()
                    }) {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
                
                #if DEBUG
                Section(header: Text("Debug").foregroundColor(.primary)) {
                    Button(action: {
                        PersistenceController.shared.resetCoreData()
                    }) {
                        Label("Core Data zurücksetzen", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    
                    Button(action: {
                        authManager.resetUserDefaults()
                    }) {
                        Label("UserDefaults zurücksetzen", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
                #endif
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return ContentView(context: context)
        .environment(\.managedObjectContext, context)
        .environmentObject(AuthenticationManager())
}

// Sheet für Gruppenauswahl
struct GroupSelectionSheet: View {
    let groups: [AccountGroup]
    let onSelect: (AccountGroup) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(groups, id: \.objectID) { group in
                Button(action: {
                    onSelect(group)
                    dismiss()
                }) {
                    Text(group.name ?? "Unbekannte Gruppe")
                        .foregroundColor(.primary)
                }
            }
            .navigationTitle("Kontogruppe wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

// View für die Gruppenauswahl beim Hinzufügen eines Kontos
struct SelectGroupForAccountView: View {
    let groups: [AccountGroup]
    let onSelect: (AccountGroup) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(groups, id: \.objectID) { group in
                Button(action: {
                    onSelect(group)
                }) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        Text(group.name ?? "Unbekannte Gruppe")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\((group.accounts?.count ?? 0)) Konten")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Gruppe für neues Konto wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

// Platzhalter für die Auswertungs-View
struct AnalysisView: View {
    let group: AccountGroup
    let viewModel: TransactionViewModel
    var body: some View {
        Text("Auswertung für \(group.name ?? "Unbekannt")")
            .font(.title2)
            .padding()
        // Hier kann später die echte Auswertungs-Logik rein
    }
}

struct AccountSortSheet: View {
    @Environment(\.dismiss) var dismiss
    let group: AccountGroup
    let onSave: () -> Void
    @State private var accounts: [Account] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                        .padding()
                } else {
                    List {
                        ForEach(accounts, id: \.objectID) { account in
                            HStack {
                                Image(systemName: account.value(forKey: "icon") as? String ?? "building.columns.fill")
                                    .foregroundColor(Color(hex: account.value(forKey: "iconColor") as? String ?? "#007AFF") ?? .blue)
                                Text(account.name ?? "Unbekanntes Konto")
                                    .foregroundColor(.primary)
                            }
                        }
                        .onMove(perform: moveAccount)
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("Konten sortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        saveOrder()
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                let acc = (group.accounts?.allObjects as? [Account]) ?? []
                accounts = acc.sorted { ($0.value(forKey: "order") as? Int16 ?? 0) < ($1.value(forKey: "order") as? Int16 ?? 0) }
                isLoading = false
            }
        }
    }

    private func moveAccount(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
    }

    private func saveOrder() {
        for (idx, account) in accounts.enumerated() {
            account.setValue(Int16(idx), forKey: "order")
        }
        if let context = group.managedObjectContext {
            do {
                try context.save()
            } catch {
                print("Fehler beim Speichern der Kontenreihenfolge: \(error)")
            }
        }
    }
}

extension UIApplication {
    var keyWindow: UIWindow? {
        return UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first(where: { $0 is UIWindowScene })
            .flatMap({ $0 as? UIWindowScene })?.windows
            .first(where: \.isKeyWindow)
    }
}

extension View {
    func fixKeyboardAssistant() -> some View {
        self.onAppear {
            // Finde und konfiguriere die SystemInputAssistantView
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let keyWindow = UIApplication.shared.keyWindow else { return }
                
                keyWindow.subviews.forEach { view in
                    view.recursiveSubviews.forEach { subview in
                        if String(describing: type(of: subview)).contains("SystemInputAssistantView") {
                            // Setze die Höhe auf einen flexiblen Wert
                            subview.removeConstraints(subview.constraints.filter {
                                String(describing: $0).contains("assistantHeight")
                            })
                        }
                    }
                }
            }
        }
    }
}

private extension UIView {
    var recursiveSubviews: [UIView] {
        return subviews + subviews.flatMap { $0.recursiveSubviews }
    }
}
