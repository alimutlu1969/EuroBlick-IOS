//
//  AccountGroup+CoreDataProperties.swift
//  EuroBlick
//
//  Created by admin on 12.04.25.
//
//

import Foundation
import CoreData


extension AccountGroup {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AccountGroup> {
        return NSFetchRequest<AccountGroup>(entityName: "AccountGroup")
    }

    @NSManaged public var name: String?
    @NSManaged public var accounts: NSSet?
    @NSManaged public var categories: NSSet?
    @NSManaged public var id: UUID?

}

// MARK: Generated accessors for accounts
extension AccountGroup {

    @objc(addAccountsObject:)
    @NSManaged public func addToAccounts(_ value: Account)

    @objc(removeAccountsObject:)
    @NSManaged public func removeFromAccounts(_ value: Account)

    @objc(addAccounts:)
    @NSManaged public func addToAccounts(_ values: NSSet)

    @objc(removeAccounts:)
    @NSManaged public func removeFromAccounts(_ values: NSSet)

}

// MARK: Generated accessors for categories
extension AccountGroup {

    @objc(addCategoriesObject:)
    @NSManaged public func addToCategories(_ value: Category)

    @objc(removeCategoriesObject:)
    @NSManaged public func removeFromCategories(_ value: Category)

    @objc(addCategories:)
    @NSManaged public func addToCategories(_ values: NSSet)

    @objc(removeCategories:)
    @NSManaged public func removeFromCategories(_ values: NSSet)

}

extension AccountGroup : Identifiable {

}
