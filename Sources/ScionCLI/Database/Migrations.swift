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

        migrator.registerMigration("v2_new_fields") { db in
            try db.alter(table: "transactions") { t in
                t.add(column: "executionRate", .text)
                t.add(column: "lendingRate", .text)
                t.add(column: "lendingPeriod", .text)
                t.add(column: "lendingStartDate", .datetime)
                t.add(column: "withdrawalId", .text)
            }
        }

        migrator.registerMigration("v3_blockchain_sync") { db in
            try db.alter(table: "transactions") { t in
                t.add(column: "blockchainTxHash", .text)
                t.add(column: "source", .text)  // "manual" | "blockchain"
            }
            // TxHashの検索を高速化するインデックス
            try db.create(
                index: "transactions_on_blockchainTxHash",
                on: "transactions",
                columns: ["blockchainTxHash"],
                ifNotExists: true
            )
        }
    }
}
