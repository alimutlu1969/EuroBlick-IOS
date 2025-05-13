import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) var dismiss
    let authManager: AuthenticationManager
    @State private var username = ""
    @State private var password = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Benutzername", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                SecureField("Passwort", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                if showError {
                    Text("Benutzername existiert bereits!")
                        .foregroundColor(.red)
                        .padding()
                }

                Button(action: {
                    if authManager.register(username: username, password: password) {
                        dismiss()
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
}

#Preview {
    RegisterView(authManager: AuthenticationManager())
}
