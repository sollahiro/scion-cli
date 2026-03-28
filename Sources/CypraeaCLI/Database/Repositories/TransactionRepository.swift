import Foundation
import GRDB

struct TransactionRepository {
    let db: DatabaseManager

    func insert(_ record: TransactionRecord) throws {
        try db.pool.write { db in
            try record.insert(db)
        }
    }

    func fetchTxHashes() throws -> Set<String> {
        try db.pool.read { db in
            let hashes = try String.fetchAll(db, sql: "SELECT txHash FROM transactions WHERE txHash IS NOT NULL")
            return Set(hashes)
        }
    }

    func fetchAll(token: String? = nil, type: String? = nil, accountId: String? = nil, from: Date? = nil, to: Date? = nil) throws -> [TransactionRecord] {
        try db.pool.read { db in
            var request = TransactionRecord.all()
            if let token { request = request.filter(TransactionRecord.Columns.token == token) }
            if let type { request = request.filter(TransactionRecord.Columns.type == type) }
            if let accountId {
                request = request.filter(
                    TransactionRecord.Columns.fromAccountId == accountId ||
                    TransactionRecord.Columns.toAccountId == accountId
                )
            }
            if let from { request = request.filter(TransactionRecord.Columns.date >= from) }
            if let to { request = request.filter(TransactionRecord.Columns.date <= to) }
            return try request.order(TransactionRecord.Columns.date).fetchAll(db)
        }
    }

    // 残高計算: token ごとの account 別保有量
    func fetchBalances() throws -> [String: [String: Decimal]] {
        let records = try fetchAll()
        var balances: [String: [String: Decimal]] = [:]  // [token: [accountId: amount]]

        for record in records {
            let token = record.token
            let amount = Decimal(string: record.amount) ?? 0
            let received = record.receivedAmount.flatMap { Decimal(string: $0) } ?? amount

            if let fromId = record.fromAccountId {
                balances[token, default: [:]][fromId, default: 0] -= amount
            }
            if let toId = record.toAccountId {
                balances[token, default: [:]][toId, default: 0] += received
            }
        }
        // マイナス残高は表示対象外（buy/sell の取引所カウンターパーティ等）
        for token in balances.keys {
            balances[token] = balances[token]?.filter { $0.value > 0 }
        }
        return balances
    }

    // 移動平均取得単価の計算（USDC用）
    func fetchMovingAverageCost(token: String) throws -> Decimal {
        let records = try fetchAll(token: token)
        var totalCost: Decimal = 0
        var totalAmount: Decimal = 0

        for record in records {
            guard record.type == TransactionType.buy.rawValue,
                  let jpyAmount = record.jpyAmount.flatMap({ Decimal(string: $0) }) else { continue }
            let amount = Decimal(string: record.amount) ?? 0
            totalCost += jpyAmount
            totalAmount += amount
        }
        guard totalAmount > 0 else { return 0 }
        return totalCost / totalAmount
    }

    // 実現損益の計算
    func fetchRealizedPnL(token: String, year: Int? = nil) throws -> Decimal {
        var buyRecords = try fetchAll(token: token, type: TransactionType.buy.rawValue)
        var sellRecords = try fetchAll(token: token, type: TransactionType.sell.rawValue)

        if let year {
            let calendar = Calendar.current
            buyRecords = buyRecords.filter { calendar.component(.year, from: $0.date) == year }
            sellRecords = sellRecords.filter { calendar.component(.year, from: $0.date) == year }
        }

        // 総平均法（year指定時）/ 移動平均法（通常）
        let avgCost: Decimal
        if year != nil {
            let totalCost = buyRecords.compactMap { $0.jpyAmount.flatMap { Decimal(string: $0) } }.reduce(0, +)
            let totalAmt = buyRecords.compactMap { Decimal(string: $0.amount) }.reduce(0, +)
            avgCost = totalAmt > 0 ? totalCost / totalAmt : 0
        } else {
            avgCost = try fetchMovingAverageCost(token: token)
        }

        let totalSellJpy = sellRecords.compactMap { $0.jpyAmount.flatMap { Decimal(string: $0) } }.reduce(0, +)
        let totalSellAmt = sellRecords.compactMap { Decimal(string: $0.amount) }.reduce(0, +)
        let costBasis = avgCost * totalSellAmt
        return totalSellJpy - costBasis
    }

    // レンディング収益の累計
    func fetchLendingIncome(token: String, year: Int? = nil) throws -> Decimal {
        var records = try fetchAll(token: token, type: TransactionType.interest.rawValue)
        if let year {
            records = records.filter { Calendar.current.component(.year, from: $0.date) == year }
        }
        return records.compactMap { record -> Decimal? in
            let amount = Decimal(string: record.amount) ?? 0
            if token == "USDC", let rate = record.usdJpyRate.flatMap({ Decimal(string: $0) }) {
                return amount * rate
            }
            return amount  // JPYCは1:1
        }.reduce(0, +)
    }
}
