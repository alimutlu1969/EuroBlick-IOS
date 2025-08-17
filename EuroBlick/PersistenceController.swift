import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "EuroBlick")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Konfiguriere Core Data Migration
        if let storeDescription = container.persistentStoreDescriptions.first {
            storeDescription.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            storeDescription.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("Failed to load persistent stores: \(error), \(error.userInfo)")
                
                // Versuche Core Data Reset bei Migration-Fehlern
                if error.code == NSPersistentStoreIncompatibleVersionHashError {
                    print("⚠️ Core Data Schema inkompatibel - versuche Reset...")
                    self.handleIncompatibleStore()
                } else {
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            } else {
                print("Successfully loaded persistent stores: \(storeDescription)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    // Behandle inkompatible Core Data Stores
    private func handleIncompatibleStore() {
        print("🔄 Starte Core Data Reset wegen Schema-Inkompatibilität...")
        
        // Lösche alle Store-Dateien
        if let storeURL = container.persistentStoreDescriptions.first?.url {
            do {
                // Lösche die Haupt-Store-Datei
                try FileManager.default.removeItem(at: storeURL)
                print("✅ Haupt-Store-Datei gelöscht: \(storeURL)")
                
                // Lösche auch die .sqlite-shm und .sqlite-wal Dateien
                let shmURL = storeURL.appendingPathExtension("sqlite-shm")
                let walURL = storeURL.appendingPathExtension("sqlite-wal")
                
                if FileManager.default.fileExists(atPath: shmURL.path) {
                    try FileManager.default.removeItem(at: shmURL)
                    print("✅ SHM-Datei gelöscht: \(shmURL)")
                }
                
                if FileManager.default.fileExists(atPath: walURL.path) {
                    try FileManager.default.removeItem(at: walURL)
                    print("✅ WAL-Datei gelöscht: \(walURL)")
                }
                
                // Versuche erneut zu laden
                container.loadPersistentStores(completionHandler: { (storeDescription, error) in
                    if let error = error as NSError? {
                        print("❌ Fehler beim Neuladen nach Reset: \(error)")
                        fatalError("Unresolved error after reset \(error), \(error.userInfo)")
                    } else {
                        print("✅ Store erfolgreich nach Reset geladen: \(storeDescription)")
                    }
                })
            } catch {
                print("❌ Fehler beim Löschen der Store-Datei: \(error)")
                fatalError("Could not delete incompatible store: \(error)")
            }
        }
    }

    // Debug-Methode zum Zurücksetzen der Datenbank
    func resetCoreData() {
        let context = container.viewContext
        let entities = ["AccountGroup", "Account", "Category", "Transaction"]
        for entityName in entities {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: entityName)
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDeleteRequest.resultType = .resultTypeCount
            do {
                let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
                print("Gelöscht: \(entityName), \(result?.result as? Int ?? 0) Objekte")
            } catch {
                print("Failed to reset \(entityName): \(error)")
            }
        }
        do {
            try context.save()
            context.reset() // Setze den Kontext zurück
            print("Core Data reset: Alle Entitäten gelöscht und Kontext zurückgesetzt")
        } catch {
            print("Failed to save context after reset: \(error)")
        }
    }

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        return result
    }()
}
