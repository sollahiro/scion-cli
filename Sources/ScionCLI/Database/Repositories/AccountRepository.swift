import Foundation
import GRDB

struct AccountRepository {
    let db: DatabaseManager

    func insert(_ account: Account) throws {
        try db.pool.write { db in
            try account.insert(db)
        }
    }

    func insertDepositAddress(_ addr: DepositAddress) throws {
        try db.pool.write { db in
            try addr.insert(db)
        }
    }

    func fetchAll() throws -> [Account] {
        try db.pool.read { db in
            try Account.fetchAll(db)
        }
    }

    func fetch(id: String) throws -> Account? {
        try db.pool.read { db in
            try Account.fetchOne(db, key: id)
        }
    }

    func fetchDepositAddresses(accountId: String) throws -> [DepositAddress] {
        try db.pool.read { db in
            try DepositAddress
                .filter(DepositAddress.Columns.accountId == accountId)
                .fetchAll(db)
        }
    }
}
