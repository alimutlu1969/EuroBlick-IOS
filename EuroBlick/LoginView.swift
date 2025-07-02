import SwiftUI
import LocalAuthentication

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager()
    @Environment(\.managedObjectContext) private var viewContext
    @State private var username = ""
    @State private var password = ""
    @State private var showRegisterSheet = false
    @State private var showError = false
    @State private var showFaceIDError = false

    var body: some View {
        if authManager.isAuthenticated {
            ContentView(context: viewContext)
                .environmentObject(authManager)
        } else {
            NavigationStack {
                ZStack {
                    Color.black
                        .edgesIgnoringSafeArea(.all)

                    ScrollView {
                        VStack(spacing: 12) {
                            // Benutzername
                            CustomTextField(text: $username, placeholder: "Benutzername", isSecure: false)
                                .onSubmit {
                                    resignKeyboard()
                                }
                                .padding(.horizontal, 16)

                            // Passwort
                            CustomTextField(text: $password, placeholder: "Passwort", isSecure: true)
                                .onSubmit {
                                    resignKeyboard()
                                }
                                .padding(.horizontal, 16)

                            // Fehlermeldungen
                            if showError {
                                Text("Falscher Benutzername oder Passwort!")
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 16)
                            }
                            if showFaceIDError {
                                Text("Face ID-Authentifizierung fehlgeschlagen!")
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 16)
                            }

                            // Anmelden-Button
                            Button("Anmelden") {
                                resignKeyboard()
                                if authManager.login(username: username, password: password) {
                                    showError = false
                                } else {
                                    showError = true
                                }
                            }
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(8)
                            .padding(.horizontal, 16)

                            // Face ID-Button
                            Button("Mit Face ID anmelden") {
                                resignKeyboard()
                                authenticateWithFaceID()
                            }
                            .foregroundColor(.blue)
                            .padding()

                            // Passwort vergessen? Button
                            Button("Passwort vergessen?") {
                                if let email = authManager.getEmail(for: username), !email.isEmpty {
                                    let subject = "EuroBlick Passwort zurücksetzen"
                                    let body = "Hallo, bitte setzen Sie mein Passwort für den Benutzer \(username) zurück."
                                    let urlString = "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                                    if let url = URL(string: urlString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            }
                            .foregroundColor(.blue)
                            .padding(.bottom, 8)

                            // Registrieren-Button
                            Button("Registrieren") {
                                resignKeyboard()
                                showRegisterSheet = true
                            }
                            .foregroundColor(.blue)
                            .padding()
                        }
                        .padding(.vertical, 12)
                    }
                    .ignoresSafeArea(.keyboard) // Ignoriere Tastatur für Layout
                }
                .onTapGesture { resignKeyboard() }
                .navigationTitle("Anmeldung")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showRegisterSheet) {
                    RegisterView(authManager: authManager)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // Tastatur ausblenden
    private func resignKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    // Face ID
    private func authenticateWithFaceID() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Anmeldung mit Face ID"
            ) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        authManager.isAuthenticated = true
                        showFaceIDError = false
                    } else {
                        showFaceIDError = true
                        print("Face ID failed:", authError?.localizedDescription ?? "Unknown")
                    }
                }
            }
        } else {
            showFaceIDError = true
            print("Face ID not available:", error?.localizedDescription ?? "Unknown")
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return LoginView()
        .environment(\.managedObjectContext, context)
}
