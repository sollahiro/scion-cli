import Foundation
import GRDB
import ScionCore

// MARK: - AccountType

public enum AccountType: String, Codable, CaseIterable {
    case wallet
    case exchange
    case lendingPlatform
}

// MARK: - DepositAddress

public struct DepositAddress: Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var accountId: String
    public var chain: String
    public var address: String

    public static let databaseTableName = "deposit_addresses"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let accountId = Column(CodingKeys.accountId)
        static let chain = Column(CodingKeys.chain)
        static let address = Column(CodingKeys.address)
    }
}

// MARK: - Account

public struct Account: Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var type: String          // AccountType.rawValue
    public var label: String
    public var url: String?          // exchange / lendingPlatform
    public var contractAddress: String? // lendingPlatform

    public static let databaseTableName = "accounts"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let type = Column(CodingKeys.type)
        static let label = Column(CodingKeys.label)
        static let url = Column(CodingKeys.url)
        static let contractAddress = Column(CodingKeys.contractAddress)
    }
}
