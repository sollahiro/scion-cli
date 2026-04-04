import ArgumentParser
import Foundation

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "取引履歴を表示"
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

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy-MM-dd"

        print("\(pad("日付", 12))  \(pad("種別", 10))  \(pad("Token", 6))  \(pad("アカウント", 20))  \(pad("金額", 12))  JPY")
        print(String(repeating: "-", count: 80))

        for record in records {
            let dateStr = displayFormatter.string(from: record.date)
            let fromLabel = record.fromAccountId.flatMap { try? acctRepo.fetch(id: $0)?.label } ?? "-"
            let toLabel = record.toAccountId.flatMap { try? acctRepo.fetch(id: $0)?.label } ?? "-"
            let accountStr = record.fromAccountId != nil && record.toAccountId != nil
                ? "\(fromLabel) → \(toLabel)"
                : record.fromAccountId != nil ? fromLabel : toLabel
            let jpyStr = record.jpyAmount.map { "¥\($0)" } ?? "-"

            print("\(pad(dateStr, 12))  \(pad(record.type, 10))  \(pad(record.token, 6))  \(pad(String(accountStr.prefix(20)), 20))  \(pad(record.amount, 12))  \(jpyStr)")
        }
        print()
    }
}
