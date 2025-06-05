import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "EuroBlick")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("Failed to load persistent stores: \(error), \(error.userInfo)")
                fatalError("Unresolved error \(error), \(error.userInfo)")
            } else {
                print("Successfully loaded persistent stores: \(storeDescription)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
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
