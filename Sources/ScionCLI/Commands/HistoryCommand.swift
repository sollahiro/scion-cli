import ArgumentParser
import Foundation

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "取引履歴を表示・削除",
        subcommands: [Delete.self]
    )

    @Option(name: .long, help: "トークンで絞り込み: JPYC / USDC") var token: String?
    @Option(name: .long, help: "種別で絞り込み: buy / sell / lend / unlend / interest / transfer / receive / send") var type: String?
    @Option(name: .long, help: "アカウントラベルで絞り込み") var account: String?
    @Option(name: .long, help: "開始日 (YYYY-MM-DD)") var from: String?
    @Option(name: .long, help: "終了日 (YYYY-MM-DD)") var to: String?
    @Option(name: .long, help: "年度で絞り込み") var year: Int?

    mutating func run() async throws {
        try await HistoryCommand.execute(token: token, type: type, account: account, from: from, to: to, year: year)
    }

    static func execute(token: String?, type: String?, account: String?, from: String?, to: String?, year: Int?) async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let txRepo = TransactionRepository(db: db)
        let acctRepo = AccountRepository(db: db)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var fromDate: Date? = from.flatMap { dateFormatter.date(from: $0) }
        var toDate: Date? = to.flatMap { dateFormatter.date(from: $0) }

        if let year {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
            guard
                let start = cal.date(from: DateComponents(year: year, month: 1, day: 1, hour: 0, minute: 0, second: 0)),
                let endDay = cal.date(from: DateComponents(year: year, month: 12, day: 31)),
                let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endDay)
            else {
                throw ValidationError("年度 \(year) の日付範囲が計算できませんでした")
            }
            fromDate = start
            toDate = end
        }

        var accountId: String? = nil
        if let accountLabel = account {
            let accounts = try acctRepo.fetchAll()
            accountId = accounts.first(where: { $0.label == accountLabel })?.id
        }

        let records = try txRepo.fetchAll(
            token: token,
            type: type,
            accountId: accountId,
            from: fromDate,
            to: toDate
        )

        if records.isEmpty {
            print("取引履歴がありません")
            return
        }

        // アカウントとチェーン情報をプリロード
        let allAccounts = try acctRepo.fetchAll()
        let accountById = Dictionary(uniqueKeysWithValues: allAccounts.map { ($0.id, $0) })
        var accountChain: [String: String] = [:]
        for account in allAccounts where account.type == AccountType.wallet.rawValue {
            let addrs = try acctRepo.fetchDepositAddresses(accountId: account.id)
            if let chain = addrs.first?.chain {
                accountChain[account.id] = chain
            }
        }

        func accountLabel(id: String?) -> String {
            guard let id, let account = accountById[id] else { return "-" }
            if let chain = accountChain[id] {
                return "\(account.label)[\(chain)]"
            }
            return account.label
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy-MM-dd"

        let acctCol = 28
        print("\(pad("日付", 12))  \(pad("種別", 10))  \(pad("Token", 6))  \(pad("アカウント", acctCol))  \(pad("数量", 12))  JPY")
        print(String(repeating: "-", count: 90))

        for record in records {
            let dateStr = displayFormatter.string(from: record.date)
            let fromStr = accountLabel(id: record.fromAccountId)
            let toStr   = accountLabel(id: record.toAccountId)
            let accountStr: String
            if record.fromAccountId != nil && record.toAccountId != nil {
                accountStr = "\(fromStr) → \(toStr)"
            } else if record.fromAccountId != nil {
                accountStr = fromStr
            } else {
                accountStr = toStr
            }
            let jpyStr = record.jpyAmount.map { "¥\($0)" } ?? "-"

            print("\(pad(dateStr, 12))  \(pad(record.type, 10))  \(pad(record.token, 6))  \(pad(String(accountStr.prefix(acctCol)), acctCol))  \(pad(record.amount, 12))  \(jpyStr)")
        }
        print()
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete", abstract: "取引を削除")

        @Argument(help: "削除する取引のID")
        var id: String

        mutating func run() async throws {
            let db = try DatabaseManager(path: DatabaseManager.defaultPath())
            let txRepo = TransactionRepository(db: db)
            let acctRepo = AccountRepository(db: db)

            guard let record = try txRepo.fetchAll().first(where: { $0.id == id }) else {
                print("エラー: 取引が見つかりません: \(id)")
                throw ExitCode.failure
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let fromLabel = record.fromAccountId.flatMap { try? acctRepo.fetch(id: $0)?.label } ?? "-"
            let toLabel   = record.toAccountId.flatMap   { try? acctRepo.fetch(id: $0)?.label } ?? "-"
            let accountStr = record.fromAccountId != nil && record.toAccountId != nil
                ? "\(fromLabel) → \(toLabel)"
                : record.fromAccountId != nil ? fromLabel : toLabel

            print("削除する取引: \(dateFormatter.string(from: record.date))  \(record.type)  \(record.token)  \(accountStr)  \(record.amount)")
            print("本当に削除しますか？ [y/N]: ", terminator: "")
            let confirm = readLine() ?? ""
            guard confirm.lowercased() == "y" else {
                print("キャンセルしました")
                return
            }

            try txRepo.delete(id: id)
            print("✓ 取引を削除しました")
        }
    }
}
