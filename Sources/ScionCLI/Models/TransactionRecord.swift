import Foundation
import GRDB

// MARK: - TransactionType

public enum TransactionType: String, Codable, CaseIterable {
    case buy
    case sell
    case lend
    case unlend
    case interest
    case transfer
    case receive
    case send
    case payment
}

// MARK: - TransactionRecord

public struct TransactionRecord: Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var date: Date
    public var type: String              // TransactionType.rawValue
    public var token: String             // "JPYC" / "USDC"
    public var fromAccountId: String?
    public var toAccountId: String?
    public var amount: String            // Decimal as String for precision
    public var receivedAmount: String?   // transfer時の着金量
    public var jpyAmount: String?        // buy: 支払JPY / sell: 受取JPY
    public var usdJpyRate: String?       // USDC取引時のレート
    public var feeJpy: String?           // 手数料・ガス代
    public var notes: String?
    public var executionRate: String?    // buy/sell 約定レート
    public var lendingRate: String?      // lend 年率（%）
    public var lendingPeriod: String?    // lend 貸出期間
    public var lendingStartDate: Date?   // lend 貸出開始日
    public var withdrawalId: String?     // transfer 出庫ID

    public static let databaseTableName = "transactions"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let date = Column(CodingKeys.date)
        static let type = Column(CodingKeys.type)
        static let token = Column(CodingKeys.token)
        static let fromAccountId = Column(CodingKeys.fromAccountId)
        static let toAccountId = Column(CodingKeys.toAccountId)
        static let amount = Column(CodingKeys.amount)
        static let receivedAmount = Column(CodingKeys.receivedAmount)
        static let jpyAmount = Column(CodingKeys.jpyAmount)
        static let usdJpyRate = Column(CodingKeys.usdJpyRate)
        static let feeJpy = Column(CodingKeys.feeJpy)
        static let notes = Column(CodingKeys.notes)
        static let executionRate = Column(CodingKeys.executionRate)
        static let lendingRate = Column(CodingKeys.lendingRate)
        static let lendingPeriod = Column(CodingKeys.lendingPeriod)
        static let lendingStartDate = Column(CodingKeys.lendingStartDate)
        static let withdrawalId = Column(CodingKeys.withdrawalId)
    }
}
