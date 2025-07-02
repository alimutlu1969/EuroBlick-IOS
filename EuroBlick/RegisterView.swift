import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) var dismiss
    let authManager: AuthenticationManager
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var passwordRepeat = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Benutzername", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                TextField("E-Mail", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 16)

                SecureField("Passwort", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 16)

                SecureField("Passwort wiederholen", text: $passwordRepeat)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 16)

                if showError {
                    Text("Bitte alle Felder korrekt ausfüllen und Passwörter müssen übereinstimmen!")
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                }

                Button(action: {
                    resignKeyboard()
                    if !username.isEmpty && !email.isEmpty && !password.isEmpty && !passwordRepeat.isEmpty {
                        if password == passwordRepeat {
                            if authManager.register(username: username, email: email, password: password) {
                                showError = false
                                dismiss()
                            } else {
                                showError = true
                            }
                        } else {
                            showError = true
                        }
                    } else {
                        showError = true
                    }
                }) {
                    Text("Registrieren")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Registrierung")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .background(Color(hex: "#000000"))
    }

    private func resignKeyboard() {
        // Implementation of resignKeyboard function
    }
}

#Preview {
    RegisterView(authManager: AuthenticationManager())
}
