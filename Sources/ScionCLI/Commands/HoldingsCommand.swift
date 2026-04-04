import ArgumentParser
import Foundation

struct HoldingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "holdings",
        abstract: "保有明細を表示"
    )

    @Option(name: .long, help: "VaporサーバーURL（環境変数 SCION_SERVER_URL でも設定可）")
    var serverURL: String = ProcessInfo.processInfo.environment["SCION_SERVER_URL"] ?? "http://localhost:8080"

    mutating func run() async throws {
        try await HoldingsCommand.execute(serverURL: serverURL)
    }

    static func execute(serverURL: String) async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let txRepo = TransactionRepository(db: db)
        let acctRepo = AccountRepository(db: db)
        let ratesService = RatesService(dbManager: db, serverURL: serverURL)

        let balances = try txRepo.fetchBalances()
        let netLending = try txRepo.fetchNetLending()
        let rates = try await ratesService.fetchRates()

        for token in ["USDC", "JPYC"] {
            guard let tokenBalances = balances[token], !tokenBalances.isEmpty else { continue }

            print("\n【\(token)】")
            var total: Decimal = 0

            for (accountId, amount) in tokenBalances.sorted(by: { $0.key < $1.key }) {
                guard amount != 0, let account = try acctRepo.fetch(id: accountId) else { continue }
                let isLending = account.type == AccountType.lendingPlatform.rawValue
                let label = isLending ? "\(account.label)（レンディング中）" : account.label

                // wallet の場合はチェーンとアドレスを表示
                var addressInfo = ""
                if account.type == AccountType.wallet.rawValue {
                    let addrs = try acctRepo.fetchDepositAddresses(accountId: accountId)
                    if let addr = addrs.first {
                        addressInfo = "  \(addr.chain)  \(addr.address)"
                    }
                }

                print("  \(pad(label, 30)) \(pad(formatDecimal(amount), 12))\(addressInfo)")

                // 貸出中金額を内訳表示
                if let lent = netLending[token]?[accountId], lent > 0 {
                    let available = amount - lent
                    print("    うち貸出中: \(formatDecimal(lent))  利用可能: \(formatDecimal(available))")
                }

                total += amount
            }

            let rate = rates[token] ?? 0
            let totalJpy = total * rate
            let avgCost = try txRepo.fetchMovingAverageCost(token: token)
            let unrealized = token == "USDC" ? (rate - avgCost) * (total) : (rate - avgCost) * total

            print(String(repeating: "-", count: 60))
            let lendingTotal = netLending[token]?.values.reduce(0, +) ?? 0
            let sign = unrealized >= 0 ? "+" : ""
            var summary = "  合計: \(formatDecimal(total))  時価: ¥\(formatJpy(totalJpy))  含み益: \(sign)¥\(formatJpy(unrealized))"
            if lendingTotal > 0 {
                summary += "  （貸出中: \(formatDecimal(lendingTotal))）"
            }
            print(summary)
        }
        print()
    }
}

// MARK: - Formatting helpers

func pad(_ s: String, _ width: Int) -> String {
    let count = s.count
    if count >= width { return s }
    return s + String(repeating: " ", count: width - count)
}

private let _decimalFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 4
    f.minimumFractionDigits = 2
    return f
}()

private let _jpyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return f
}()

func formatDecimal(_ value: Decimal) -> String {
    _decimalFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
}

func formatJpy(_ value: Decimal) -> String {
    _jpyFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
}
