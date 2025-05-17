import Foundation
import CoreData

public class CategoryMatcher {
    // Struktur für Kategorie-Regeln
    public struct CategoryRule: Codable {
        public let pattern: String
        public var category: String
        public var matchCount: Int
        public let lastUsed: Date
        public var originalText: String?  // Speichert den ursprünglichen Text
        public var shortForm: String?     // Speichert die gekürzte Form
        
        public init(pattern: String, category: String, matchCount: Int = 0, lastUsed: Date = Date(), originalText: String? = nil, shortForm: String? = nil) {
            self.pattern = pattern
            self.category = category
            self.matchCount = matchCount
            self.lastUsed = lastUsed
            self.originalText = originalText
            self.shortForm = shortForm
        }
    }
    
    // Neue Struktur für Transaktionstyp-Erkennung
    public struct TransactionTypeInfo {
        public let type: String
        public let category: String
        public let isTransfer: Bool
        public let sourceAccount: String?
        public let targetAccount: String?
        
        public init(type: String, category: String, isTransfer: Bool, sourceAccount: String? = nil, targetAccount: String? = nil) {
            self.type = type
            self.category = category
            self.isTransfer = isTransfer
            self.sourceAccount = sourceAccount
            self.targetAccount = targetAccount
        }
    }
    
    // Singleton-Instanz
    public static let shared = CategoryMatcher()
    
    // UserDefaults-Schlüssel
    private let rulesKey = "categoryMatchingRules"
    
    // Aktuelle Regeln
    private var rules: [CategoryRule] = []
    
    private init() {
        loadRules()
        initializeDefaultRules()
    }
    
    // Lädt gespeicherte Regeln
    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let decodedRules = try? JSONDecoder().decode([CategoryRule].self, from: data) {
            rules = decodedRules
        }
    }
    
    // Initialisiert Standard-Regeln
    private func initializeDefaultRules() {
        let defaultRules: [(pattern: String, category: String)] = [
            // Spezifische Zuordnungen
            ("Edelgard Carl-Uzer", "Steuerberater"),
            ("Acai", "Wareneinkauf"),
            ("Helen Schmiedle", "Personal"),
            ("Sevim Mutlu", "Personal"),
            ("Ferhat Keziban", "Personal"),
            ("EK Hanseatische Krankenkasse", "KV-Beiträge"),
            ("EK Techniker Krankenkasse", "KV-Beiträge"),
            ("HV Raimund Petersen", "Raumkosten"),
            ("STRATO GmbH", "Sonstiges"),
            ("AOK Nordost", "KV-Beiträge"),
            ("Uber Payments B.V.", "Einnahmen"),
            ("Wolt License Services Oy", "Einnahmen"),
            ("SIGNAL IDUNA Gruppe", "Priv. KV"),
            ("SGB Energie GmbH", "Strom/Gas"),
            ("ALBA Berlin GmbH", "Sonstiges"),
            ("Finanzamt Charlottenburg", "Steuern"),
            ("finanzamt friedrichshain kreuzberg", "Steuern"),
            ("reCup GmbH", "Verpackung"),
            ("ILLE Papier-Service GmbH", "Reinigung"),
            ("Bundesknappschaft", "Sozialkassen"),
            ("Vodafone GmbH", "Telefon"),
            
            // Allgemeine Regeln
            ("gehalt", "Personal"),
            ("lohn", "Personal"),
            ("bonus", "Personal"),
            ("uber", "Einnahmen"),
            ("wolt", "Einnahmen"),
            ("lieferando", "Einnahmen"),
            
            // Versicherungen und Krankenkassen
            ("krankenkasse", "KV-Beiträge"),
            ("krankenversicherung", "KV-Beiträge"),
            ("aok", "KV-Beiträge"),
            ("signal iduna", "Priv. KV"),
            ("unfallversicherung", "Versicherung"),
            
            // Steuern und Finanzen
            ("finanzamt", "Steuern"),
            ("steuer", "Steuern"),
            ("umsatzsteuer", "Steuern"),
            ("einkommensteuer", "Steuern"),
            
            // Infrastruktur
            ("strom", "Strom/Gas"),
            ("gas", "Strom/Gas"),
            ("energie", "Strom/Gas"),
            ("vodafone", "Telefon"),
            ("strato", "Internetkosten"),
            
            // Büro und Material
            ("miete", "Raumkosten"),
            ("büro", "Raumkosten"),
            ("nebenkosten", "Raumkosten"),
            ("verpackung", "Verpackung"),
            ("karton", "Verpackung"),
            ("versand", "Verpackung"),
            ("recup", "Verpackung"),
            
            // Dienstleistungen
            ("steuerberater", "Steuerberater"),
            ("buchhaltung", "Steuerberater"),
            ("werbung", "Werbekosten"),
            ("marketing", "Werbekosten"),
            ("anzeige", "Werbekosten"),
            
            // Wareneinkauf
            ("einkauf", "Wareneinkauf"),
            ("material", "Wareneinkauf"),
            ("waren", "Wareneinkauf"),
            
            // Instandhaltung
            ("reparatur", "Instandhaltung"),
            ("wartung", "Instandhaltung"),
            ("service", "Instandhaltung"),
            
            // Spezielle Transaktionen
            ("kaution", "Kaution"),
            ("deposit", "Kaution"),
            ("pfand", "Kaution"),
            ("anzahlung", "Kaution"),
            ("sb-einzahlung", "SB-Einzahlung"),
            ("sb einzahlung", "SB-Einzahlung"),
            ("selbstbedienungs-einzahlung", "SB-Einzahlung"),
            ("geldautomat", "SB-Einzahlung"),
            ("atm", "SB-Einzahlung")
        ]
        
        for (pattern, category) in defaultRules {
            if !rules.contains(where: { $0.pattern == pattern }) {
                rules.append(CategoryRule(pattern: pattern, category: category))
            }
        }
        saveRules()
    }
    
    // Speichert Regeln
    private func saveRules() {
        if let encoded = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(encoded, forKey: rulesKey)
        }
    }
    
    // Findet die beste Kategorie für einen Verwendungszweck
    public func findBestCategory(for usage: String, amount: Double) -> (String?, String?) {
        let normalizedUsage = usage.lowercased()
        
        // Prüfe zuerst auf spezielle Transaktionstypen
        if let transactionType = detectTransactionType(usage: normalizedUsage, amount: amount) {
            return (transactionType.category, transactionType.type)
        }
        
        // Suche nach exakten Übereinstimmungen
        if let exactMatch = findExactMatch(for: normalizedUsage) {
            // Bestimme den Typ basierend auf der Kategorie
            let type = determineTransactionType(category: exactMatch, amount: amount)
            return (exactMatch, type)
        }
        
        // Suche nach ähnlichen Übereinstimmungen
        if let similarMatch = findSimilarMatch(for: normalizedUsage) {
            // Bestimme den Typ basierend auf der Kategorie
            let type = determineTransactionType(category: similarMatch, amount: amount)
            return (similarMatch, type)
        }
        
        // Prüfe auf 50€ Kaution
        if abs(abs(amount) - 50.0) < 0.01 {
            // Prüfe ob es sich um eine Person handelt (kein bekanntes Unternehmen)
            let businessIndicators = ["gmbh", "ag", "kg", "ohg", "ug", "ltd", "corp", "inc"]
            let isBusinessTransaction = businessIndicators.contains { normalizedUsage.contains($0) }
            
            if !isBusinessTransaction {
                return ("Kaution", "neutral")
            }
        }
        
        // Betragbasierte Kategorisierung als Fallback
        let (category, type) = suggestCategoryBasedOnAmount(amount)
        return (category, type)
    }
    
    // Bestimme den Transaktionstyp basierend auf der Kategorie
    private func determineTransactionType(category: String, amount: Double) -> String {
        switch category {
        case "SB-Einzahlung", "Kaution":
            return "neutral"
        default:
            return amount >= 0 ? "einnahme" : "ausgabe"
        }
    }
    
    // Schlägt eine Kategorie basierend auf dem Betrag vor
    private func suggestCategoryBasedOnAmount(_ amount: Double) -> (String, String) {
        if amount > 0 {
            return ("Einnahmen", "einnahme")
        } else if amount < -1000 {
            return ("Große Ausgaben", "ausgabe")
        } else if amount < -100 {
            return ("Mittlere Ausgaben", "ausgabe")
        } else {
            return ("Kleine Ausgaben", "ausgabe")
        }
    }
    
    // Sucht nach exakten Übereinstimmungen
    private func findExactMatch(for usage: String) -> String? {
        let normalizedUsage = usage.lowercased()
        
        // Suche zuerst nach Original-Text-Matches
        for (index, rule) in rules.enumerated() {
            if let originalText = rule.originalText?.lowercased(),
               normalizedUsage.contains(originalText) {
                // Aktualisiere die Nutzungsstatistik
                var updatedRule = rule
                updatedRule.matchCount += 1
                rules[index] = updatedRule
                saveRules()
                return rule.category
            }
        }
        
        // Dann nach gekürzten Formen und Pattern-Matches
        for (index, rule) in rules.enumerated() {
            // Prüfe die gekürzte Form, falls vorhanden
            if let shortForm = rule.shortForm?.lowercased(),
               normalizedUsage.contains(shortForm) {
                // Aktualisiere die Nutzungsstatistik
                var updatedRule = rule
                updatedRule.matchCount += 1
                rules[index] = updatedRule
                saveRules()
                return rule.category
            }
            
            // Prüfe das Pattern
            if normalizedUsage.contains(rule.pattern.lowercased()) {
                // Aktualisiere die Nutzungsstatistik
                var updatedRule = rule
                updatedRule.matchCount += 1
                rules[index] = updatedRule
                saveRules()
                return rule.category
            }
        }
        
        return nil
    }
    
    // Sucht nach ähnlichen Übereinstimmungen
    private func findSimilarMatch(for usage: String) -> String? {
        var bestMatch: (similarity: Double, category: String)? = nil
        
        for rule in rules {
            let similarity = calculateSimilarity(between: usage, and: rule.pattern.lowercased())
            if similarity > 0.8 { // Schwellenwert für Ähnlichkeit
                if bestMatch == nil || similarity > bestMatch!.similarity {
                    bestMatch = (similarity, rule.category)
                }
            }
        }
        
        return bestMatch?.category
    }
    
    // Berechnet die Ähnlichkeit zwischen zwei Strings
    private func calculateSimilarity(between first: String, and second: String) -> Double {
        let distance = levenshteinDistance(between: first, and: second)
        let maxLength = Double(max(first.count, second.count))
        return 1 - (Double(distance) / maxLength)
    }
    
    // Levenshtein-Distanz für String-Ähnlichkeit
    private func levenshteinDistance(between first: String, and second: String) -> Int {
        let firstArray = Array(first)
        let secondArray = Array(second)
        
        var matrix = Array(repeating: Array(repeating: 0, count: secondArray.count + 1), count: firstArray.count + 1)
        
        for i in 0...firstArray.count {
            matrix[i][0] = i
        }
        
        for j in 0...secondArray.count {
            matrix[0][j] = j
        }
        
        for i in 1...firstArray.count {
            for j in 1...secondArray.count {
                if firstArray[i-1] == secondArray[j-1] {
                    matrix[i][j] = matrix[i-1][j-1]
                } else {
                    matrix[i][j] = min(
                        matrix[i-1][j] + 1,    // Löschung
                        matrix[i][j-1] + 1,    // Einfügung
                        matrix[i-1][j-1] + 1   // Ersetzung
                    )
                }
            }
        }
        
        return matrix[firstArray.count][secondArray.count]
    }
    
    // Fügt eine neue Regel hinzu oder aktualisiert eine bestehende
    func addOrUpdateRule(pattern: String, category: String) {
        if let index = rules.firstIndex(where: { $0.pattern == pattern }) {
            var updatedRule = rules[index]
            updatedRule.category = category
            updatedRule.matchCount += 1
            rules[index] = updatedRule
        } else {
            let newRule = CategoryRule(pattern: pattern, category: category)
            rules.append(newRule)
        }
        saveRules()
    }
    
    // Entfernt eine Regel
    func removeRule(pattern: String) {
        rules.removeAll { $0.pattern == pattern }
        saveRules()
    }
    
    // Gibt alle aktuellen Regeln zurück
    func getAllRules() -> [CategoryRule] {
        return rules.sorted { $0.matchCount > $1.matchCount }
    }
    
    // Erkennt spezielle Transaktionstypen
    func detectTransactionType(usage: String, amount: Double) -> TransactionTypeInfo? {
        let normalizedUsage = usage.lowercased()
        
        // Erkennung von SB-Einzahlungen
        if normalizedUsage.contains("sb-einzahlung") || 
           normalizedUsage.contains("sb einzahlung") ||
           normalizedUsage.contains("selbstbedienungs-einzahlung") ||
           normalizedUsage.contains("geldautomat einzahlung") ||
           (normalizedUsage.contains("sb ") && normalizedUsage.contains(" / ")) {
            return TransactionTypeInfo(
                type: "neutral",
                category: "SB-Einzahlung",
                isTransfer: true,
                sourceAccount: "Bargeld",
                targetAccount: "Giro"
            )
        }
        
        // Erkennung von Kautionen
        if (normalizedUsage.contains("kaution") ||
            normalizedUsage.contains("deposit") ||
            normalizedUsage.contains("pfand") ||
            normalizedUsage.contains("anzahlung")) &&
            abs(abs(amount) - 50.0) < 0.01 {
            return TransactionTypeInfo(
                type: "neutral",
                category: "Kaution",
                isTransfer: false,
                sourceAccount: nil,
                targetAccount: nil
            )
        }
        
        return nil
    }
    
    // Neue Methode zum Lernen von Kürzungen
    public func learnShortForm(originalText: String, shortForm: String, category: String) {
        // Normalisiere die Texte
        let normalizedOriginal = originalText.lowercased()
        let normalizedShort = shortForm.lowercased()
        
        // Prüfe, ob bereits eine Regel für diesen Text existiert
        if let index = rules.firstIndex(where: { $0.originalText?.lowercased() == normalizedOriginal }) {
            // Aktualisiere existierende Regel
            var updatedRule = rules[index]
            updatedRule.shortForm = shortForm
            updatedRule.category = category
            updatedRule.matchCount += 1
            rules[index] = updatedRule
        } else {
            // Erstelle neue Regel
            let newRule = CategoryRule(
                pattern: normalizedShort,
                category: category,
                matchCount: 1,
                lastUsed: Date(),
                originalText: originalText,
                shortForm: shortForm
            )
            rules.append(newRule)
        }
        
        saveRules()
    }
} 