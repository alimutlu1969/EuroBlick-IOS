//
//  Transaction+CoreDataProperties.swift
//  EuroBlick
//
//  Created by admin on 12.04.25.
//
//

import Foundation
import CoreData

extension Transaction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Transaction> {
        return NSFetchRequest<Transaction>(entityName: "Transaction")
    }

    @NSManaged public var amount: Double
    @NSManaged public var date: Date
    @NSManaged public var excludeFromBalance: Bool
    @NSManaged public var id: UUID
    @NSManaged public var type: String?
    @NSManaged public var usage: String?
    @NSManaged public var account: Account?
    @NSManaged public var categoryRelationship: Category?
    @NSManaged public var targetAccount: Account?

}

extension Transaction : Identifiable {

}
