import Foundation
import SwiftUI
import KeychainAccess
import CryptoKit
import LocalAuthentication // Importiere das LocalAuthentication-Framework

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated: Bool {
        didSet {
            userDefaults.set(isAuthenticated, forKey: isAuthenticatedKey)
            print("isAuthenticated updated: \(isAuthenticated)")
        }
    }
    private let userDefaults = UserDefaults.standard
    private let keychain = Keychain(service: "com.euroblick.auth")
    private let usersKey = "users"
    private let isAuthenticatedKey = "isAuthenticated"
    private let lastAuthenticatedUserKey = "lastAuthenticatedUser"

    // Initialisiere isAuthenticated aus UserDefaults
    init() {
        self.isAuthenticated = userDefaults.bool(forKey: isAuthenticatedKey)
        print("isAuthenticated initialized: \(isAuthenticated)")
        print("UserDefaults isAuthenticated: \(userDefaults.bool(forKey: isAuthenticatedKey))")
    }

    // Struktur für Benutzerdaten (nur Benutzername)
    struct User: Codable {
        let username: String
    }

    // Hash-Funktion für Passwörter
    private func hashPassword(_ password: String) -> String {
        let data = Data(password.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // Speichere einen neuen Benutzer
    func register(username: String, password: String) -> Bool {
        var users = getUsers()
        // Überprüfe, ob der Benutzername bereits existiert
        if users.contains(where: { $0.username == username }) {
            print("Registration failed: Username \(username) already exists")
            return false
        }
        // Hash das Passwort
        let hashedPassword = hashPassword(password)
        // Speichere den Hash im Keychain
        do {
            try keychain.set(hashedPassword, key: username)
            // Füge neuen Benutzer hinzu (nur Benutzername)
            users.append(User(username: username))
            // Speichere Benutzer in UserDefaults
            if let encoded = try? JSONEncoder().encode(users) {
                userDefaults.set(encoded, forKey: usersKey)
                print("Registration successful: \(username)")
                return true
            }
            print("Registration failed: Could not encode users")
            return false
        } catch {
            print("Keychain error during registration: \(error)")
            return false
        }
    }

    // Überprüfe Anmeldedaten
    func login(username: String, password: String) -> Bool {
        let users = getUsers()
        let hashedPassword = hashPassword(password)
        // Überprüfe, ob der Benutzer existiert und das Passwort korrekt ist
        if users.contains(where: { $0.username == username }),
           let storedHash = try? keychain.get(username),
           storedHash == hashedPassword {
            isAuthenticated = true
            userDefaults.set(username, forKey: lastAuthenticatedUserKey)
            print("Login successful: \(username)")
            return true
        }
        print("Login failed: Invalid username or password")
        return false
    }

    // Hole alle Benutzer aus UserDefaults
    private func getUsers() -> [User] {
        if let data = userDefaults.data(forKey: usersKey),
           let users = try? JSONDecoder().decode([User].self, from: data) {
            print("Loaded users: \(users.map { $0.username })")
            return users
        }
        print("No users found in UserDefaults")
        return []
    }

    // Melde den Benutzer ab
    func logout() {
        isAuthenticated = false
        userDefaults.set(false, forKey: isAuthenticatedKey)
        userDefaults.removeObject(forKey: lastAuthenticatedUserKey)
        print("User logged out")
        print("UserDefaults isAuthenticated after logout: \(userDefaults.bool(forKey: isAuthenticatedKey))")
    }

    // Debug-Methode zum Zurücksetzen von UserDefaults und Keychain
    func resetUserDefaults() {
        userDefaults.removeObject(forKey: usersKey)
        userDefaults.removeObject(forKey: isAuthenticatedKey)
        userDefaults.removeObject(forKey: lastAuthenticatedUserKey)
        isAuthenticated = false
        // Lösche alle Keychain-Einträge
        do {
            try keychain.removeAll()
            print("Keychain cleared")
        } catch {
            print("Error clearing Keychain: \(error)")
        }
        print("UserDefaults and Keychain reset")
        print("UserDefaults isAuthenticated after reset: \(userDefaults.bool(forKey: isAuthenticatedKey))")
    }

    // Hole den letzten authentifizierten Benutzer für Face ID
    func getLastAuthenticatedUser() -> String? {
        return userDefaults.string(forKey: lastAuthenticatedUserKey)
    }

    // Methode zum Zurücksetzen des Passworts für einen Benutzer
    func resetPasswordForUser(username: String, newPassword: String) -> Bool {
        let users = getUsers()
        // Überprüfe, ob der Benutzer existiert
        guard users.contains(where: { $0.username == username }) else {
            print("Reset failed: Username \(username) does not exist")
            return false
        }
        // Hash das neue Passwort
        let hashedPassword = hashPassword(newPassword)
        // Speichere den Hash im Keychain
        do {
            try keychain.set(hashedPassword, key: username)
            print("Password reset successful for \(username)")
            return true
        } catch {
            print("Keychain error during password reset: \(error)")
            return false
        }
    }

    // Methode für Face ID/Touch ID-Authentifizierung
    func authenticateWithFaceID(completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        var error: NSError?

        // Prüfe, ob Face ID, Touch ID oder Gerätepasscode verfügbar ist
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Bitte authentifizieren Sie sich, um sich anzumelden."

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        // Authentifizierung erfolgreich (entweder Face ID, Touch ID oder Passcode)
                        if let lastUser = self.getLastAuthenticatedUser() {
                            self.isAuthenticated = true
                            print("Benutzer authentifiziert mit Face ID/Touch ID: \(lastUser)")
                            completion(true, nil)
                        } else {
                            let errorMsg = "Kein letzter Benutzer gefunden. Bitte melden Sie sich zunächst mit Benutzername und Passwort an."
                            print(errorMsg)
                            completion(false, errorMsg)
                        }
                    } else {
                        // Authentifizierung fehlgeschlagen
                        if let error = authenticationError as NSError? {
                            let errorMsg: String
                            switch error.code {
                            case LAError.userCancel.rawValue:
                                errorMsg = "Authentifizierung abgebrochen."
                            case LAError.userFallback.rawValue:
                                errorMsg = "Bitte verwenden Sie Face ID, Touch ID oder Ihren Gerätepasscode."
                            case LAError.biometryNotAvailable.rawValue:
                                errorMsg = "Face ID oder Touch ID ist nicht verfügbar."
                            case LAError.biometryNotEnrolled.rawValue:
                                errorMsg = "Bitte richten Sie Face ID oder Touch ID in den Einstellungen ein."
                            case LAError.biometryLockout.rawValue:
                                errorMsg = "Face ID oder Touch ID ist gesperrt. Bitte verwenden Sie Ihren Gerätepasscode."
                            default:
                                errorMsg = "Authentifizierung fehlgeschlagen: \(error.localizedDescription)"
                            }
                            print("Authentifizierung fehlgeschlagen: \(errorMsg)")
                            completion(false, errorMsg)
                        } else {
                            let errorMsg = "Unbekannter Fehler bei der Authentifizierung."
                            print(errorMsg)
                            completion(false, errorMsg)
                        }
                    }
                }
            }
        } else {
            // Authentifizierung nicht möglich
            let errorMsg: String
            if let error = error {
                switch error.code {
                case LAError.biometryNotAvailable.rawValue:
                    errorMsg = "Face ID oder Touch ID ist auf diesem Gerät nicht verfügbar."
                case LAError.biometryNotEnrolled.rawValue:
                    errorMsg = "Bitte richten Sie Face ID oder Touch ID in den Einstellungen ein."
                default:
                    errorMsg = "Biometrische Authentifizierung nicht möglich: \(error.localizedDescription)"
                }
            } else {
                errorMsg = "Biometrische Authentifizierung nicht möglich."
            }
            print("Authentifizierung nicht verfügbar: \(errorMsg)")
            completion(false, errorMsg)
        }
    }
}
