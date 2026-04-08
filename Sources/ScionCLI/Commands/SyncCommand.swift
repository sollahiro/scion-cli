import ArgumentParser
import Foundation
import ScionCore

/// オンチェーンのトランザクション履歴をAlchemy経由で取得し、ローカルDBに同期する
struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "ウォレットのオンチェーン取引履歴を同期"
    )

    @Option(name: .long, help: "VaporサーバーURL（環境変数 SCION_SERVER_URL でも設定可）")
    var serverURL: String = ProcessInfo.processInfo.environment["SCION_SERVER_URL"] ?? "http://localhost:8080"

    @Option(name: .long, help: "同期するウォレットのラベル（省略時: 全ウォレット）")
    var account: String?

    @Flag(name: .long, help: "実際には挿入せず、取得件数のみ表示する")
    var dryRun: Bool = false

    mutating func run() async throws {
        try await SyncCommand.execute(serverURL: serverURL, accountLabel: account, dryRun: dryRun)
    }

    static func execute(serverURL: String, accountLabel: String?, dryRun: Bool) async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let acctRepo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        // 同期対象ウォレットを絞り込む
        let allAccounts = try acctRepo.fetchAll()
        let wallets = allAccounts.filter {
            $0.type == AccountType.wallet.rawValue
            && (accountLabel == nil || $0.label == accountLabel)
        }

        if wallets.isEmpty {
            print("同期対象のウォレットが見つかりません。")
            print("先に scion account add または scion account connect でウォレットを登録してください。")
            return
        }

        guard let baseURL = URL(string: serverURL) else {
            fputs("無効なサーバーURL: \(serverURL)\n", stderr)
            throw ExitCode.failure
        }

        let alchemyClient = AlchemyClient(baseURL: baseURL)
        let tokens: [Token] = [.jpyc, .usdc]

        if dryRun { print("（ドライラン: DBへの書き込みは行いません）\n") }

        var totalInserted = 0
        var totalSkipped = 0

        for wallet in wallets {
            let addresses = try acctRepo.fetchDepositAddresses(accountId: wallet.id)
            guard !addresses.isEmpty else { continue }

            print("[\(wallet.label)]")

            for addr in addresses {
                guard let chain = Chain(rawValue: addr.chain) else { continue }

                for token in tokens {
                    print("  \(pad(addr.chain, 10)) \(token.rawValue) ... ", terminator: "")
                    fflush(stdout)

                    let transactions: [ScionCore.Transaction]
                    do {
                        transactions = try await alchemyClient.fetchTransactions(
                            walletAddress: addr.address,
                            chain: chain,
                            token: token
                        )
                    } catch {
                        print("エラー: \(error.localizedDescription)")
                        continue
                    }

                    var inserted = 0
                    var skipped = 0

                    for tx in transactions {
                        let record = makeRecord(
                            tx: tx,
                            walletAccountId: wallet.id,
                            token: token
                        )
                        if dryRun {
                            let alreadyExists = (try? txRepo.existsByTxHash(tx.id)) ?? false
                            if alreadyExists { skipped += 1 } else { inserted += 1 }
                        } else {
                            let wasInserted = (try? txRepo.insertIfNotExists(record)) ?? false
                            if wasInserted { inserted += 1 } else { skipped += 1 }
                        }
                    }

                    totalInserted += inserted
                    totalSkipped += skipped
                    print("新規 \(inserted)件 / 重複スキップ \(skipped)件")
                }
            }
        }

        print()
        print(String(repeating: "─", count: 40))
        if dryRun {
            print("新規取込予定: \(totalInserted)件 / 既存（スキップ）: \(totalSkipped)件")
        } else {
            print("同期完了: 新規 \(totalInserted)件 / スキップ \(totalSkipped)件")
            if totalInserted > 0 {
                print("  scion holdings または scion pnl で確認できます")
            }
        }
        print()
    }

    // MARK: - Private

    private static func makeRecord(
        tx: ScionCore.Transaction,
        walletAccountId: String,
        token: Token
    ) -> TransactionRecord {
        let amount = formatDecimalPrecise(tx.amount)
        let priceInJPY = tx.priceInJPY
        let jpyAmount = formatDecimalPrecise(tx.amount * priceInJPY)
        let usdJpyRate = token == .usdc ? formatDecimalPrecise(priceInJPY) : nil

        return TransactionRecord(
            id: UUID().uuidString,
            date: tx.timestamp,
            type: tx.type == .receive
                ? TransactionType.receive.rawValue
                : TransactionType.send.rawValue,
            token: token.rawValue,
            fromAccountId: tx.type == .send ? walletAccountId : nil,
            toAccountId: tx.type == .receive ? walletAccountId : nil,
            amount: amount,
            receivedAmount: nil,
            jpyAmount: jpyAmount,
            usdJpyRate: usdJpyRate,
            feeJpy: nil,
            notes: "chain:\(tx.chain.rawValue) block:\(tx.blockNumber)",
            executionRate: nil,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: nil,
            blockchainTxHash: "\(tx.id):\(tx.chain.rawValue):\(token.rawValue)",
            source: "blockchain"
        )
    }
}

// MARK: - Helpers

private func formatDecimalPrecise(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 18
    formatter.minimumFractionDigits = 0
    formatter.usesGroupingSeparator = false
    return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
}
