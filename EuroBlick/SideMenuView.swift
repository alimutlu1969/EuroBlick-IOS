import SwiftUI

struct SideMenuView: View {
    @Binding var showSideMenu: Bool
    @State private var showLogoutAlert = false
    // Dummy-Daten für Profil
    let userName: String = "Ali Mutlu"
    let userEmail: String = "ali.mutlu@me.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profilbereich
            HStack(spacing: 16) {
                Button(action: { showLogoutAlert = true }) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.white)
                                .font(.system(size: 24, weight: .bold))
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
                        .foregroundColor(.white)
                    Text(userEmail)
                        .font(.subheadline)
                        .foregroundColor(.gray)
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
                SideMenuItem(icon: "paintpalette", title: "Farbdesign") {
                    showSideMenu = false
                }
                SideMenuItem(icon: "paperplane", title: "Feedback senden") {
                    showSideMenu = false
                }
                SideMenuItem(icon: "gear", title: "Einstellungen") {
                    NotificationCenter.default.post(name: NSNotification.Name("SideMenuShowSettings"), object: nil)
                    showSideMenu = false
                }
                SideMenuItem(icon: "info.circle", title: "Info / Rechtliches") {
                    showSideMenu = false
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.top, 56)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Color(.black))
        .edgesIgnoringSafeArea(.all)
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
                    .foregroundColor(.white)
                    .font(.system(size: 18, weight: .medium))
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
} 