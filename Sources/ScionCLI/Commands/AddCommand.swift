import ArgumentParser
import Foundation

struct AddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "取引を記録",
        subcommands: [
            AddBuy.self, AddSell.self,
            AddLend.self, AddUnlend.self, AddInterest.self,
            AddTransfer.self, AddReceive.self, AddSend.self,
            AddPayment.self, AddIssue.self,
        ]
    )
}

// MARK: - 共通オプション

private let validTokens = ["JPYC", "USDC"]

private func validateToken(_ token: String) throws -> String {
    guard validTokens.contains(token) else {
        throw ValidationError("無効なトークンです: \(token)。JPYC または USDC を指定してください")
    }
    return token
}

private func validatePositiveDecimal(_ value: String, fieldName: String) throws -> String {
    guard let d = Decimal(string: value), d > 0 else {
        throw ValidationError("\(fieldName)は正の数値を入力してください: \(value)")
    }
    return value
}

private func parseDate(_ value: String?) throws -> Date {
    guard let value else { return Date() }
    let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd"]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in formats {
        formatter.dateFormat = format
        if let date = formatter.date(from: value) { return date }
    }
    throw ValidationError("日時の形式が不正です: \(value)。例: 2026-03-20 14:10:08")
}

private func resolveAccount(label: String?, prompt message: String, repo: AccountRepository) throws -> String {
    let resolvedLabel = try label ?? prompt(message)
    let accounts = try repo.fetchAll()
    guard let account = accounts.first(where: { $0.label.lowercased() == resolvedLabel.lowercased() }) else {
        throw ValidationError("アカウントが見つかりません: \(resolvedLabel)")
    }
    return account.id
}

// MARK: - buy

struct AddBuy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "buy", abstract: "購入を記録")

    @Option(help: "トークン: JPYC / USDC") var token: String?
    @Option(help: "取引所アカウントラベル") var exchange: String?
    @Option(help: "取得量") var amount: String?
    @Option(help: "支払JPY総額") var jpy: String?
    @Option(help: "USD/JPYレート（USDCのみ）") var rate: String?
    @Option(help: "手数料（JPY）") var fee: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "約定レート") var executionRate: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let resolvedToken = try validateToken(token ?? prompt("トークン (JPYC / USDC): "))
        let toId = try resolveAccount(label: exchange, prompt: "取引所ラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("取得量: "), fieldName: "取得量")
        let resolvedJpy = try validatePositiveDecimal(jpy ?? prompt("支払JPY総額: "), fieldName: "支払JPY総額")

        var resolvedRate: String? = rate
        if resolvedToken == "USDC" && resolvedRate == nil {
            resolvedRate = try prompt("USD/JPYレート: ")
        }
        if let r = resolvedRate {
            resolvedRate = try validatePositiveDecimal(r, fieldName: "USD/JPYレート")
        }

        let resolvedExecutionRate = try executionRate.map { try validatePositiveDecimal($0, fieldName: "約定レート") }

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.buy.rawValue,
            token: resolvedToken,
            fromAccountId: nil,
            toAccountId: toId,
            amount: resolvedAmount,
            receivedAmount: nil,
            jpyAmount: resolvedJpy,
            usdJpyRate: resolvedRate,
            feeJpy: fee,
            notes: notes,
            executionRate: resolvedExecutionRate,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: nil
        )
        try txRepo.insert(record)
        print("✓ buy を記録しました: \(resolvedToken) \(resolvedAmount)")
    }
}

// MARK: - sell

struct AddSell: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sell", abstract: "売却を記録")

    @Option(help: "トークン: JPYC / USDC") var token: String?
    @Option(help: "送出アカウントラベル") var from: String?
    @Option(help: "取引所アカウントラベル") var exchange: String?
    @Option(help: "売却量") var amount: String?
    @Option(help: "受取JPY総額") var jpy: String?
    @Option(help: "USD/JPYレート（USDCのみ）") var rate: String?
    @Option(help: "手数料（JPY）") var fee: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "約定レート") var executionRate: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let resolvedToken = try validateToken(token ?? prompt("トークン (JPYC / USDC): "))
        let fromId = try resolveAccount(label: from, prompt: "送出アカウントラベル: ", repo: repo)
        let toId = try resolveAccount(label: exchange, prompt: "取引所ラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("売却量: "), fieldName: "売却量")
        let resolvedJpy = try validatePositiveDecimal(jpy ?? prompt("受取JPY総額: "), fieldName: "受取JPY総額")

        var resolvedRate: String? = rate
        if resolvedToken == "USDC" && resolvedRate == nil {
            resolvedRate = try prompt("USD/JPYレート: ")
        }
        if let r = resolvedRate {
            resolvedRate = try validatePositiveDecimal(r, fieldName: "USD/JPYレート")
        }

        let resolvedExecutionRate = try executionRate.map { try validatePositiveDecimal($0, fieldName: "約定レート") }

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.sell.rawValue,
            token: resolvedToken,
            fromAccountId: fromId,
            toAccountId: nil,
            amount: resolvedAmount,
            receivedAmount: nil,
            jpyAmount: resolvedJpy,
            usdJpyRate: resolvedRate,
            feeJpy: fee,
            notes: notes,
            executionRate: resolvedExecutionRate,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: nil
        )
        try txRepo.insert(record)
        print("✓ sell を記録しました: \(resolvedToken) \(resolvedAmount)")
    }
}

// MARK: - lend

struct AddLend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "lend", abstract: "レンディング預入を記録")

    @Option(help: "トークン: JPYC / USDC") var token: String?
    @Option(help: "送出アカウントラベル") var from: String?
    @Option(help: "レンディングプラットフォームラベル") var platform: String?
    @Option(help: "預入量") var amount: String?
    @Option(help: "手数料（JPY）") var fee: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "年率 (%)") var lendingRate: String?
    @Option(help: "貸出期間 (例: 30日)") var lendingPeriod: String?
    @Option(help: "貸出開始日 (YYYY-MM-DD)") var lendingStartDate: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let resolvedToken = try validateToken(token ?? prompt("トークン (JPYC / USDC): "))
        let fromId = try resolveAccount(label: from, prompt: "送出アカウントラベル: ", repo: repo)
        let toId = try resolveAccount(label: platform, prompt: "プラットフォームラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("預入量: "), fieldName: "預入量")

        let resolvedLendingRate = try lendingRate.map { try validatePositiveDecimal($0, fieldName: "年率") }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let resolvedLendingStartDate: Date?
        if let ds = lendingStartDate {
            guard let d = dateFormatter.date(from: ds) else {
                throw ValidationError("貸出開始日の形式が不正です: \(ds)。YYYY-MM-DD 形式で入力してください")
            }
            resolvedLendingStartDate = d
        } else {
            resolvedLendingStartDate = nil
        }

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.lend.rawValue,
            token: resolvedToken,
            fromAccountId: fromId,
            toAccountId: toId,
            amount: resolvedAmount,
            receivedAmount: nil,
            jpyAmount: nil,
            usdJpyRate: nil,
            feeJpy: fee,
            notes: notes,
            executionRate: nil,
            lendingRate: resolvedLendingRate,
            lendingPeriod: lendingPeriod,
            lendingStartDate: resolvedLendingStartDate,
            withdrawalId: nil
        )
        try txRepo.insert(record)
        print("✓ lend を記録しました: \(resolvedToken) \(resolvedAmount)")
    }
}

// MARK: - unlend

struct AddUnlend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unlend", abstract: "レンディング解除を記録")

    @Option(help: "トークン: JPYC / USDC") var token: String?
    @Option(help: "レンディングプラットフォームラベル") var platform: String?
    @Option(help: "受取アカウントラベル") var to: String?
    @Option(help: "返還量") var amount: String?
    @Option(help: "手数料（JPY）") var fee: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let resolvedToken = try validateToken(token ?? prompt("トークン (JPYC / USDC): "))
        let fromId = try resolveAccount(label: platform, prompt: "プラットフォームラベル: ", repo: repo)
        let toId = try resolveAccount(label: to, prompt: "受取アカウントラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("返還量: "), fieldName: "返還量")

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.unlend.rawValue,
            token: resolvedToken,
            fromAccountId: fromId,
            toAccountId: toId,
            amount: resolvedAmount,
            receivedAmount: nil,
            jpyAmount: nil,
            usdJpyRate: nil,
            feeJpy: fee,
            notes: notes,
            executionRate: nil,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: nil
        )
        try txRepo.insert(record)
        print("✓ unlend を記録しました: \(resolvedToken) \(resolvedAmount)")
    }
}

// MARK: - interest

struct AddInterest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "interest", abstract: "レンディング利息受取を記録")

    @Option(help: "トークン: JPYC / USDC") var token: String?
    @Option(help: "プラットフォームラベル") var platform: String?
    @Option(help: "受取量") var amount: String?
    @Option(help: "USD/JPYレート（USDCのみ）") var rate: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let resolvedToken = try validateToken(token ?? prompt("トークン (JPYC / USDC): "))
        let toId = try resolveAccount(label: platform, prompt: "プラットフォームラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("受取量: "), fieldName: "受取量")

        var resolvedRate: String? = rate
        if resolvedToken == "USDC" && resolvedRate == nil {
            resolvedRate = try prompt("USD/JPYレート: ")
        }
        if let r = resolvedRate {
            resolvedRate = try validatePositiveDecimal(r, fieldName: "USD/JPYレート")
        }

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.interest.rawValue,
            token: resolvedToken,
            fromAccountId: nil,
            toAccountId: toId,
            amount: resolvedAmount,
            receivedAmount: nil,
            jpyAmount: nil,
            usdJpyRate: resolvedRate,
            feeJpy: nil,
            notes: notes,
            executionRate: nil,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: nil
        )
        try txRepo.insert(record)
        print("✓ interest を記録しました: \(resolvedToken) \(resolvedAmount)")
    }
}

// MARK: - transfer

struct AddTransfer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "transfer", abstract: "ウォレット間移動を記録")

    @Option(help: "トークン: JPYC / USDC") var token: String?
    @Option(help: "送出アカウントラベル") var from: String?
    @Option(help: "受取アカウントラベル") var to: String?
    @Option(help: "送出量") var amount: String?
    @Option(help: "着金量（手数料で減る場合）") var received: String?
    @Option(help: "手数料（JPY）") var fee: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "出庫ID") var withdrawalId: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let resolvedToken = try validateToken(token ?? prompt("トークン (JPYC / USDC): "))
        let fromId = try resolveAccount(label: from, prompt: "送出アカウントラベル: ", repo: repo)
        let toId = try resolveAccount(label: to, prompt: "受取アカウントラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("送出量: "), fieldName: "送出量")

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.transfer.rawValue,
            token: resolvedToken,
            fromAccountId: fromId,
            toAccountId: toId,
            amount: resolvedAmount,
            receivedAmount: received,
            jpyAmount: nil,
            usdJpyRate: nil,
            feeJpy: fee,
            notes: notes,
            executionRate: nil,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: withdrawalId
        )
        try txRepo.insert(record)
        print("✓ transfer を記録しました: \(resolvedToken) \(resolvedAmount)")
    }
}

// MARK: - receive

struct AddReceive: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "receive", abstract: "外部からの受取を記録")

    @Option(help: "トークン: JPYC / USDC") var token: String?
    @Option(help: "受取アカウントラベル") var to: String?
    @Option(help: "受取量") var amount: String?
    @Option(help: "手数料（JPY）") var fee: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let resolvedToken = try validateToken(token ?? prompt("トークン (JPYC / USDC): "))
        let toId = try resolveAccount(label: to, prompt: "受取アカウントラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("受取量: "), fieldName: "受取量")

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.receive.rawValue,
            token: resolvedToken,
            fromAccountId: nil,
            toAccountId: toId,
            amount: resolvedAmount,
            receivedAmount: nil,
            jpyAmount: nil,
            usdJpyRate: nil,
            feeJpy: fee,
            notes: notes,
            executionRate: nil,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: nil
        )
        try txRepo.insert(record)
        print("✓ receive を記録しました: \(resolvedToken) \(resolvedAmount)")
    }
}

// MARK: - payment

struct AddPayment: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "payment", abstract: "支払いを記録")

    @Option(help: "トークン: JPYC / USDC") var token: String?
    @Option(help: "送出アカウントラベル") var from: String?
    @Option(help: "支払量") var amount: String?
    @Option(help: "決済時JPY相当額（USDCは必須）") var jpy: String?
    @Option(help: "USD/JPYレート（USDCのみ）") var rate: String?
    @Option(help: "手数料（JPY）") var fee: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let resolvedToken = try validateToken(token ?? prompt("トークン (JPYC / USDC): "))
        let fromId = try resolveAccount(label: from, prompt: "送出アカウントラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("支払量: "), fieldName: "支払量")

        var resolvedJpy: String?
        var resolvedRate: String?
        if resolvedToken == "USDC" {
            resolvedJpy = try validatePositiveDecimal(jpy ?? prompt("決済時JPY相当額: "), fieldName: "決済時JPY相当額")
            resolvedRate = try validatePositiveDecimal(rate ?? prompt("USD/JPYレート: "), fieldName: "USD/JPYレート")
        } else {
            // JPYCは1:1なのでamountをそのまま使うが、明示指定も許容
            resolvedJpy = jpy ?? resolvedAmount
        }

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.payment.rawValue,
            token: resolvedToken,
            fromAccountId: fromId,
            toAccountId: nil,
            amount: resolvedAmount,
            receivedAmount: nil,
            jpyAmount: resolvedJpy,
            usdJpyRate: resolvedRate,
            feeJpy: fee,
            notes: notes,
            executionRate: nil,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: nil
        )
        try txRepo.insert(record)
        print("✓ payment を記録しました: \(resolvedToken) \(resolvedAmount)")
    }
}

// MARK: - issue

struct AddIssue: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "issue", abstract: "JPYC EX発行を記録（JPY支払い → ウォレットへJPYC直接ミント）")

    @Option(help: "受取ウォレットアカウントラベル") var to: String?
    @Option(help: "発行量（JPYC）") var amount: String?
    @Option(help: "支払JPY総額（省略時は発行量と同額）") var jpy: String?
    @Option(help: "手数料（JPY）") var fee: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let toId = try resolveAccount(label: to, prompt: "受取ウォレットラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("発行量（JPYC）: "), fieldName: "発行量")
        let resolvedJpy = try validatePositiveDecimal(jpy ?? resolvedAmount, fieldName: "支払JPY総額")

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.issue.rawValue,
            token: "JPYC",
            fromAccountId: nil,
            toAccountId: toId,
            amount: resolvedAmount,
            receivedAmount: nil,
            jpyAmount: resolvedJpy,
            usdJpyRate: nil,
            feeJpy: fee,
            notes: notes,
            executionRate: nil,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: nil
        )
        try txRepo.insert(record)
        print("✓ issue を記録しました: JPYC \(resolvedAmount)（支払JPY: \(resolvedJpy)）")
    }
}

// MARK: - send

struct AddSend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "send", abstract: "外部への送出を記録")

    @Option(help: "トークン: JPYC / USDC") var token: String?
    @Option(help: "送出アカウントラベル") var from: String?
    @Option(help: "送出量") var amount: String?
    @Option(help: "手数料（JPY）") var fee: String?
    @Option(help: "メモ") var notes: String?
    @Option(help: "取引日時 (YYYY-MM-DD HH:mm:ss)") var date: String?

    mutating func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)

        let resolvedToken = try validateToken(token ?? prompt("トークン (JPYC / USDC): "))
        let fromId = try resolveAccount(label: from, prompt: "送出アカウントラベル: ", repo: repo)
        let resolvedAmount = try validatePositiveDecimal(amount ?? prompt("送出量: "), fieldName: "送出量")

        let record = TransactionRecord(
            id: UUID().uuidString,
            date: try parseDate(date),
            type: TransactionType.send.rawValue,
            token: resolvedToken,
            fromAccountId: fromId,
            toAccountId: nil,
            amount: resolvedAmount,
            receivedAmount: nil,
            jpyAmount: nil,
            usdJpyRate: nil,
            feeJpy: fee,
            notes: notes,
            executionRate: nil,
            lendingRate: nil,
            lendingPeriod: nil,
            lendingStartDate: nil,
            withdrawalId: nil
        )
        try txRepo.insert(record)
        print("✓ send を記録しました: \(resolvedToken) \(resolvedAmount)")
    }
}
