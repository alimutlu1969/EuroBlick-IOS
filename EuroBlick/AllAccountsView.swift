import SwiftUI
import CoreData

struct AllAccountsView: View {
    let accountGroups: [AccountGroup]
    let balances: [AccountBalance]
    let viewModel: TransactionViewModel
    @State private var expanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Kopfzeile
            HStack {
                Text("Alle Konten")
                    .font(.title2)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { expanded.toggle() }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
            .onTapGesture { expanded.toggle() }

            // Gruppenliste
            if expanded {
                VStack(spacing: 12) {
                    ForEach(accountGroups) { group in
                        AllAccountsGroupRowView(group: group)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

struct AllAccountsGroupRowView: View {
    let group: AccountGroup
    @State private var expanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(group.name ?? "Unbekannte Gruppe")
                    .foregroundColor(.white)
                Spacer()
                Button(action: { expanded.toggle() }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(10)
            .onTapGesture { expanded.toggle() }

            if expanded {
                Text("Hier könnten die Konten stehen…")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
    }
} 