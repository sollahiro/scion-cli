import ArgumentParser
import Foundation

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Alchemyを使ってオンチェーン取引を取得・インポート"
    )

    @Option(name: .long, help: "Alchemy APIキー")
    var alchemyKey: String

    @Option(name: .long, help: "ネットワーク (eth-mainnet / polygon-mainnet)")
    var network: String = "polygon-mainnet"

    @Flag(name: .long, help: "確認なしで全件インポート")
    var auto: Bool = false

    @Option(name: .long, help: "取得開始ブロック（デフォルト: 0x0）")
    var fromBlock: String = "0x0"

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let acctRepo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let wallets = try acctRepo.fetchAll().filter { $0.type == AccountType.wallet.rawValue }
        guard !wallets.isEmpty else {
            print("ウォレットアカウントが登録されていません。")
            return
        }

        let existingHashes = try txRepo.fetchTxHashes()
        var totalImported = 0

        for wallet in wallets {
            let addresses = try acctRepo.fetchDepositAddresses(accountId: wallet.id)
            let matching = addresses.filter { AlchemyService.alchemyNetwork(from: $0.chain) == network }

            for addr in matching {
                print("\n📡 [\(wallet.label)] \(addr.chain)  \(addr.address)")
                let alchemy = AlchemyService(apiKey: alchemyKey, network: network)

                let transfers: [AlchemyTransfer]
                do {
                    transfers = try await alchemy.fetchAssetTransfers(
                        address: addr.address, fromBlock: fromBlock)
                } catch {
                    print("  エラー: \(error.localizedDescription)")
                    continue
                }

                let relevant = transfers
                    .filter { ["USDC", "JPYC"].contains($0.asset) }
                    .filter { !existingHashes.contains($0.hash) }
                    .sorted { $0.blockTime < $1.blockTime }

                if relevant.isEmpty {
                    print("  新しい取引なし")
                    continue
                }

                print("  \(relevant.count) 件の未記録取引:")
                for t in relevant {
                    let dir = t.to.lowercased() == addr.address.lowercased() ? "受取" : "送出"
                    print("  [\(formatSyncDate(t.blockTime))] \(dir)  \(formatDecimal(t.value)) \(t.asset)  \(t.hash.prefix(14))...")
                }

                let shouldImport: Bool
                if auto {
                    shouldImport = true
                } else {
                    let answer = try prompt("  インポートしますか？ (y/N): ")
                    shouldImport = answer.lowercased() == "y"
                }

                guard shouldImport else { continue }

                for t in relevant {
                    let isIncoming = t.to.lowercased() == addr.address.lowercased()
                    let record = TransactionRecord(
                        id: UUID().uuidString,
                        date: t.blockTime,
                        type: (isIncoming ? TransactionType.receive : TransactionType.send).rawValue,
                        token: t.asset,
                        fromAccountId: isIncoming ? nil : wallet.id,
                        toAccountId: isIncoming ? wallet.id : nil,
                        amount: "\(t.value)",
                        receivedAmount: nil,
                        jpyAmount: nil,
                        usdJpyRate: nil,
                        feeJpy: nil,
                        notes: "Alchemy sync",
                        txHash: t.hash
                    )
                    try txRepo.insert(record)
                    totalImported += 1
                }
                print("  ✓ \(relevant.count) 件をインポートしました")
            }
        }

        if totalImported > 0 {
            print("\n✓ 合計 \(totalImported) 件の取引をインポートしました")
        } else {
            print("\n新しいオンチェーン取引はありませんでした")
        }
    }
}

private func formatSyncDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    f.timeZone = TimeZone.current
    return f.string(from: date)
}
