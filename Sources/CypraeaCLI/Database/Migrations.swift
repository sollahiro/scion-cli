import GRDB

enum Migrations {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "accounts") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("label", .text).notNull()
                t.column("url", .text)
                t.column("contractAddress", .text)
            }

            try db.create(table: "deposit_addresses") { t in
                t.primaryKey("id", .text)
                t.column("accountId", .text).notNull()
                    .references("accounts", onDelete: .cascade)
                t.column("chain", .text).notNull()
                t.column("address", .text).notNull()
            }

            try db.create(table: "transactions") { t in
                t.primaryKey("id", .text)
                t.column("date", .datetime).notNull()
                t.column("type", .text).notNull()
                t.column("token", .text).notNull()
                t.column("fromAccountId", .text)
                    .references("accounts", onDelete: .restrict)
                t.column("toAccountId", .text)
                    .references("accounts", onDelete: .restrict)
                t.column("amount", .text).notNull()
                t.column("receivedAmount", .text)
                t.column("jpyAmount", .text)
                t.column("usdJpyRate", .text)
                t.column("feeJpy", .text)
                t.column("notes", .text)
            }

            try db.create(table: "rate_cache") { t in
                t.primaryKey("token", .text)
                t.column("rateJpy", .double).notNull()
                t.column("fetchedAt", .datetime).notNull()
            }
        }
    }
}
