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
                .font(.system(size: AppFontSize.sectionTitle))
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
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

    private func formatBalance(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        let number = NSNumber(value: abs(amount))
        let formattedAmount = formatter.string(from: number) ?? String(format: "%.2f", abs(amount))
        return "\(formattedAmount) €"
    }

    var body: some View {
        NavigationStack {
            HStack {
                Image(systemName: accountIcon.systemName)
                    .foregroundColor(accountIcon.color)
                    .font(.system(size: AppFontSize.contentIcon))
                    .frame(width: 30)
                Text(account.name ?? "Unbekanntes Konto")
                    .foregroundColor(.white)
                    .font(.system(size: AppFontSize.bodyLarge))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(formatBalance(balance))
                    .foregroundColor(balance >= 0 ? Color.green : Color.red)
                    .font(.system(size: AppFontSize.bodyMedium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        let groupName = (group.name ?? "").lowercased()
        
        if groupName.contains("drinks") {
            // Sortierung für Drinks-Gruppe: Kasa, Banka, [andere]
            return accountBalances
                .filter { account in
                    let name = (account.account.name ?? "").lowercased()
                    return name != "bize"
                }
                .sorted { first, second in
                    let firstName = (first.account.name ?? "").lowercased()
                    let secondName = (second.account.name ?? "").lowercased()
                    
                    let order = ["kasa", "banka"]
                    let firstIndex = order.firstIndex(of: firstName) ?? order.count
                    let secondIndex = order.firstIndex(of: secondName) ?? order.count
                    
                    if firstIndex != secondIndex {
                        return firstIndex < secondIndex
                    }
                    return firstName < secondName
                }
        } else if groupName.contains("kaffee") {
            // Sortierung für Kaffee-Gruppe: Bargeld, Giro, [andere]
            return accountBalances
                .filter { ($0.account.name ?? "").lowercased() != "bk" }
                .sorted { first, second in
                    let firstName = (first.account.name ?? "").lowercased()
                    let secondName = (second.account.name ?? "").lowercased()
                    
                    let order = ["bargeld", "giro"]
                    let firstIndex = order.firstIndex(of: firstName) ?? order.count
                    let secondIndex = order.firstIndex(of: secondName) ?? order.count
                    
                    if firstIndex != secondIndex {
                        return firstIndex < secondIndex
                    }
                    return firstName < secondName
                }
        }
        
        // Standardsortierung für andere Gruppen
        return accountBalances
    }

    private var specialAccounts: [(account: Account, balance: Double)] {
        let groupName = (group.name ?? "").lowercased()
        
        if groupName.contains("drinks") {
            // Bize-Konten für Drinks-Gruppe
            return accountBalances.filter { ($0.account.name ?? "").lowercased() == "bize" }
        } else if groupName.contains("kaffee") {
            // BK-Konten für Kaffee-Gruppe
            return accountBalances.filter { ($0.account.name ?? "").lowercased() == "bk" }
        }
        
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Gruppenkopf mit Name und Gesamtbilanz
            HStack {
                Image(systemName: groupIcon.systemName)
                    .foregroundColor(groupIcon.color)
                    .font(.system(size: AppFontSize.groupIcon))
                    .padding(.trailing, 6)
                Text(group.name ?? "Unbekannte Gruppe")
                    .font(.system(size: AppFontSize.groupTitle, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(String(format: "%.2f €", groupBalance))")
                    .foregroundColor(groupBalance >= 0 ? Color.green : Color.red)
                    .font(.system(size: AppFontSize.bodyMedium))
                Button(action: {
                    groupToEdit = group
                    newGroupName = group.name ?? ""
                    showEditGroupSheet = true
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                        .font(.system(size: AppFontSize.smallIcon))
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

            // Trennlinie und spezielle Konten
            if !specialAccounts.isEmpty {
                Divider()
                    .background(Color.gray.opacity(0.5))
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                ForEach(specialAccounts, id: \.account.objectID) { item in
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
                        .font(.system(size: AppFontSize.smallIcon))
                    Text("Auswertung")
                        .font(.system(size: AppFontSize.bodySmall))
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
            viewModel.fetchAccountGroups()
        }
        .id(group.objectID)
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
        
        // Berechne Gruppensaldo inklusive aller Konten
        groupBalance = accountBalances.reduce(0.0) { total, item in
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
                                .font(.system(size: AppFontSize.appTitle))
                                .bold()
                            Text("Version 1.0.0")
                                .font(.system(size: AppFontSize.bodySmall))
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
        .foregroundColor(.white)
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
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: AppFontSize.bodySmall))
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
    @State private var showOptionsActionSheet = false

    private let isDebugMode = true

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Group {
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
                    
                    Button(action: {
                        showAboutView = true
                    }) {
                        Label("Über EuroBlick", systemImage: "info.circle")
                    }
                    
                    #if DEBUG
                    Divider()
                    
                    Button(role: .destructive, action: {
                        PersistenceController.shared.resetCoreData()
                        print("Core Data zurückgesetzt")
                    }) {
                        Label("Core Data zurücksetzen", systemImage: "trash")
                    }
                    
                    Button(role: .destructive, action: {
                        authManager.resetUserDefaults()
                        print("UserDefaults zurückgesetzt")
                    }) {
                        Label("UserDefaults zurücksetzen", systemImage: "trash")
                }
                #endif
                }
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
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

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var viewModel: TransactionViewModel
    @State private var sheetState: SheetPresentationState = .none
    @State private var showSettingsSheet = false
    @State private var showLogoutAlert = false
    @State private var accountBalances: [AccountBalance] = []
    @State private var showAddAccountGroupSheet = false
    
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: TransactionViewModel(context: context))
    }
    
    private var headerView: some View {
        VStack(spacing: 20) {
            // Obere Zeile mit Abmelden-Button und Settings
            HStack {
                // Abmelden Button - kleiner und links
                Button(action: {
                    showLogoutAlert = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .font(.system(size: 14))
                        Text("Abmelden")
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(6)
                }
                
                Spacer()
                
                // Settings Menu - rechts oben
                settingsMenu
            }
            .padding(.bottom, 36)
            
            // EuroBlick Logo - mittig
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "eurosign.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.blue)
                    Text("EuroBlick")
                        .font(.title3)
                        .bold()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    private var settingsMenu: some View {
        Menu {
            Button(action: {
                sheetState = .selectGroup
            }) {
                Label("Konto hinzufügen", systemImage: "plus.circle")
            }
            Button(action: {
                showAddAccountGroupSheet = true
            }) {
                Label("Kontogruppe hinzufügen", systemImage: "folder.badge.plus")
            }
            Button(action: {
                showSettingsSheet = true
            }) {
                Label("Einstellungen", systemImage: "gear")
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .foregroundColor(.white)
        }
    }

    private var accountGroupsList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                ForEach(viewModel.accountGroups) { accountGroup in
                    AccountGroupView(
                        group: accountGroup,
                        viewModel: viewModel,
                        balances: accountBalances,
                        showEditGroupSheet: .constant(false),
                        groupToEdit: .constant(nil),
                        newGroupName: .constant("")
                    )
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20) // Add bottom padding to ensure last item is visible
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                accountGroupsList
            }
            .background(Color.black)
            .sheet(item: Binding(
                get: { sheetState == .selectGroup ? sheetState : nil },
                set: { _ in sheetState = .none }
            )) { _ in
                SelectAccountGroupView(
                    viewModel: viewModel,
                    onGroupSelected: { group in
                        sheetState = .addAccount(group: group)
                    }
                )
            }
            .sheet(item: Binding(
                get: {
                    if case .addAccount = sheetState {
                        return sheetState
                    }
                    return nil
                },
                set: { _ in sheetState = .none }
            )) { state in
                if case .addAccount(let group) = state {
                    AddAccountView(viewModel: viewModel, group: group)
                }
            }
            .sheet(isPresented: $showAddAccountGroupSheet) {
                AddAccountGroupView(viewModel: viewModel)
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView()
            }
            .alert("Abmelden", isPresented: $showLogoutAlert) {
                Button("Abbrechen", role: .cancel) { }
                Button("Abmelden", role: .destructive) {
                    authManager.logout()
                }
            } message: {
                Text("Möchten Sie sich wirklich abmelden?")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            migrateExistingAccounts()
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
                let balance = allBalances[account.objectID] ?? 0.0
                newBalances.append(AccountBalance(id: account.objectID, name: account.name ?? "Unbekanntes Konto", balance: balance))
            }
        }

        accountBalances = newBalances
    }

    // Fügt eine Methode hinzu, um bestehende Konten zu migrieren
    private func migrateExistingAccounts() {
        let context = viewModel.getContext()
        
        // Hole alle Konten
        let fetchRequest: NSFetchRequest<Account> = Account.fetchRequest()
        
        do {
            let accounts = try context.fetch(fetchRequest)
            var updated = false
            
            for account in accounts {
                // Wenn das Konto noch keinen Typ hat oder der Typ leer ist
                if account.value(forKey: "type") == nil || (account.value(forKey: "type") as? String) == "" {
                    let accountName = account.name?.lowercased() ?? ""
                    
                    // Setze Typ basierend auf dem Namen
                    if accountName.contains("giro") || accountName.contains("banka") {
                        account.setValue("bankkonto", forKey: "type")
                        print("Konto \(account.name ?? "unbekannt") auf Typ 'bankkonto' gesetzt")
                        updated = true
                    } else if accountName.contains("bar") || accountName.contains("kasse") {
                        account.setValue("bargeld", forKey: "type")
                        print("Konto \(account.name ?? "unbekannt") auf Typ 'bargeld' gesetzt")
                        updated = true
                    } else {
                        account.setValue("offline", forKey: "type")
                        print("Konto \(account.name ?? "unbekannt") auf Typ 'offline' gesetzt")
                        updated = true
                    }
                }
            }
            
            if updated {
                try context.save()
                print("Kontotypen erfolgreich migriert")
            }
        } catch {
            print("Fehler bei der Migration von Konten: \(error.localizedDescription)")
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
                let balance = allBalances[account.objectID] ?? 0.0
                newBalances.append(AccountBalance(id: account.objectID, name: account.name ?? "Unbekanntes Konto", balance: balance))
            }
        }
        
        accountBalances = newBalances
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Allgemein").foregroundColor(.white)) {
                    NavigationLink(destination: AboutView()) {
                        Label("Über EuroBlick", systemImage: "info.circle")
                            .foregroundColor(.white)
                    }
                }
                
                Section(header: Text("Sicherheit").foregroundColor(.white)) {
                    Button(action: {
                        authManager.logout()
                        dismiss()
                    }) {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
                
                #if DEBUG
                Section(header: Text("Debug").foregroundColor(.white)) {
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
        .preferredColorScheme(.dark)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return ContentView(context: context)
        .environment(\.managedObjectContext, context)
        .environmentObject(AuthenticationManager())
}
