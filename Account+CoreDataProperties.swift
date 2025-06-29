//
//  Account+CoreDataProperties.swift
//  EuroBlick
//
//  Created by admin on 12.04.25.
//
//

import Foundation
import CoreData


extension Account {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Account> {
        return NSFetchRequest<Account>(entityName: "Account")
    }

    @NSManaged public var name: String?
    @NSManaged public var transactions: NSSet?
    @NSManaged public var group: AccountGroup?
    @NSManaged public var targetedTransactions: NSSet?
    @NSManaged public var id: UUID?

}

// MARK: Generated accessors for transactions
extension Account {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: Transaction)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: Transaction)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}

// MARK: Generated accessors for targetedTransactions
extension Account {

    @objc(addTargetedTransactionsObject:)
    @NSManaged public func addToTargetedTransactions(_ value: Transaction)

    @objc(removeTargetedTransactionsObject:)
    @NSManaged public func removeFromTargetedTransactions(_ value: Transaction)

    @objc(addTargetedTransactions:)
    @NSManaged public func addToTargetedTransactions(_ values: NSSet)

    @objc(removeTargetedTransactions:)
    @NSManaged public func removeFromTargetedTransactions(_ values: NSSet)

}

extension Account : Identifiable {

}
