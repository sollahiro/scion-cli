import ArgumentParser
import Foundation

struct PnLCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pnl",
        abstract: "損益サマリーを表示"
    )

    @Option(name: .long, help: "税務申告用年度（総平均法）")
    var tax: Int?

    @Option(name: .long, help: "VaporサーバーURL（環境変数 SCION_SERVER_URL でも設定可）")
    var serverURL: String = ProcessInfo.processInfo.environment["SCION_SERVER_URL"] ?? "http://localhost:8080"

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let txRepo = TransactionRepository(db: db)
        let ratesService = RatesService(dbManager: db, serverURL: serverURL)

        let rates = try await ratesService.fetchRates()
        let balances = try txRepo.fetchBalances()

        // 保有状況
        print("\n【保有状況】")
        for token in ["USDC", "JPYC"] {
            let total = balances[token]?.values.reduce(0, +) ?? 0
            let lendingTotal = try lendingBalance(token: token, txRepo: txRepo)
            let rate = rates[token] ?? 0
            let avgCost = try txRepo.fetchMovingAverageCost(token: token)
            let unrealized = (rate - avgCost) * total
            let pct = avgCost > 0 ? (rate - avgCost) / avgCost * 100 : 0

            let sign = unrealized >= 0 ? "+" : ""
            print("  \(token)  \(formatDecimal(total))（うちレンディング中: \(formatDecimal(lendingTotal))）")
            print("    平均取得単価 ¥\(formatRate(avgCost)) / 現在 ¥\(formatRate(rate)) / 含み益 \(sign)¥\(formatJpy(unrealized))(\(formatRate(pct))%)")
        }

        // 課税対象合計
        print("\n【課税対象合計（雑所得）】\(tax.map { "  \($0)年度 総平均法" } ?? "  移動平均法")")
        var totalRealized: Decimal = 0
        var totalLending: Decimal = 0

        for token in ["USDC", "JPYC"] {
            let realized = try txRepo.fetchRealizedPnL(token: token, year: tax)
            let lending = try txRepo.fetchLendingIncome(token: token, year: tax)
            totalRealized += realized
            totalLending += lending
        }

        let realizedSign = totalRealized >= 0 ? "+" : ""
        let totalSign = (totalRealized + totalLending) >= 0 ? "+" : ""
        print("  実現損益:          \(realizedSign)¥\(formatJpy(totalRealized))")
        print("  レンディング収益:   ¥\(formatJpy(totalLending))")
        print(String(repeating: "-", count: 40))
        let total = totalRealized + totalLending
        print("  合計:              \(totalSign)¥\(formatJpy(total))")
        print()
    }

    private func lendingBalance(token: String, txRepo: TransactionRepository) throws -> Decimal {
        let lends = try txRepo.fetchAll(token: token, type: TransactionType.lend.rawValue)
        let unlends = try txRepo.fetchAll(token: token, type: TransactionType.unlend.rawValue)
        let lendTotal = lends.compactMap { Decimal(string: $0.amount) }.reduce(0, +)
        let unlendTotal = unlends.compactMap { Decimal(string: $0.amount) }.reduce(0, +)
        return lendTotal - unlendTotal
    }
}

private let _rateFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 3
    f.minimumFractionDigits = 3
    return f
}()

func formatRate(_ value: Decimal) -> String {
    _rateFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
}
