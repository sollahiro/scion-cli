import ArgumentParser
import Foundation

struct HoldingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "holdings",
        abstract: "保有明細を表示"
    )

    @Option(name: .long, help: "VaporサーバーURL")
    var serverURL: String = "http://localhost:8080"

    @Option(name: .long, help: "Alchemy APIキー（指定するとオンチェーン残高を照合）")
    var alchemyKey: String?

    @Option(name: .long, help: "Alchemyネットワーク (eth-mainnet / polygon-mainnet)")
    var alchemyNetwork: String = "polygon-mainnet"

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let txRepo = TransactionRepository(db: db)
        let acctRepo = AccountRepository(db: db)
        let ratesService = RatesService(dbManager: db, serverURL: serverURL)

        let balances = try txRepo.fetchBalances()
        let rates = try await ratesService.fetchRates()

        for token in ["USDC", "JPYC"] {
            guard let tokenBalances = balances[token], !tokenBalances.isEmpty else { continue }

            print("\n【\(token)】")
            var total: Decimal = 0
            var lendingTotal: Decimal = 0

            for (accountId, amount) in tokenBalances.sorted(by: { $0.key < $1.key }) {
                guard amount != 0, let account = try acctRepo.fetch(id: accountId) else { continue }
                let isLending = account.type == AccountType.lendingPlatform.rawValue
                let label = isLending ? "\(account.label)（レンディング中）" : account.label

                // wallet の場合はチェーンとアドレスを表示（Alchemy 指定時はオンチェーン残高も照合）
                var addressInfo = ""
                if account.type == AccountType.wallet.rawValue {
                    let addrs = try acctRepo.fetchDepositAddresses(accountId: accountId)
                    if let addr = addrs.first {
                        addressInfo = "  \(addr.chain)  \(addr.address)"

                        if let key = alchemyKey,
                           AlchemyService.alchemyNetwork(from: addr.chain) == alchemyNetwork {
                            let alchemy = AlchemyService(apiKey: key, network: alchemyNetwork)
                            if let onChain = try? await alchemy.fetchTokenBalances(address: addr.address)[token] {
                                let diff = onChain - amount
                                let diffStr = diff == 0
                                    ? "✓"
                                    : "差分: \(diff > 0 ? "+" : "")\(formatDecimal(diff))"
                                addressInfo += "  [オンチェーン: \(formatDecimal(onChain))  \(diffStr)]"
                            }
                        }
                    }
                }

                print("  \(pad(label, 30)) \(pad(formatDecimal(amount), 12))\(addressInfo)")
                total += amount
                if isLending { lendingTotal += amount }
            }

            let rate = rates[token] ?? 0
            let totalJpy = total * rate
            let avgCost = try txRepo.fetchMovingAverageCost(token: token)
            let unrealized = token == "USDC" ? (rate - avgCost) * (total) : (rate - avgCost) * total

            print(String(repeating: "-", count: 60))
            let sign = unrealized >= 0 ? "+" : ""
            print("  合計: \(formatDecimal(total))  時価: ¥\(formatJpy(totalJpy))  含み益: \(sign)¥\(formatJpy(unrealized))")
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

func formatDecimal(_ value: Decimal) -> String {
    let nsDecimal = value as NSDecimalNumber
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 4
    formatter.minimumFractionDigits = 2
    return formatter.string(from: nsDecimal) ?? "\(value)"
}

func formatJpy(_ value: Decimal) -> String {
    let nsDecimal = value as NSDecimalNumber
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter.string(from: nsDecimal) ?? "\(value)"
}
