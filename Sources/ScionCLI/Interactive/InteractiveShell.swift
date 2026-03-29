import Foundation

struct InteractiveShell {

    private let ui: any SelectUI = TermiosSelectUI()
    private let serverURL = ProcessInfo.processInfo.environment["SCION_SERVER_URL"] ?? "http://localhost:8080"

    // MARK: - Entry Point

    func run() async throws {
        printLogo()

        while true {
            let mainItems = [
                "保有明細を見る",
                "損益を確認する",
                "取引履歴を見る",
                "取引を記録する",
                "アカウントを管理する",
                "終了する",
            ]

            guard let idx = try ui.select(
                prompt: "操作を選択  ↑↓ で移動  Enter で決定  q でキャンセル",
                items: mainItems
            ) else {
                break
            }

            do {
                switch idx {
                case 0: try await runHoldings()
                case 1: try await runPnL()
                case 2: try await runHistory()
                case 3: try await runAddMenu()
                case 4: try await runAccountMenu()
                case 5: print("終了します。"); return
                default: break
                }
            } catch {
                print("\nエラー: \(error.localizedDescription)")
                pauseForRead()
            }
        }
    }

    // MARK: - View Commands

    private func runHoldings() async throws {
        print()
        var cmd = HoldingsCommand()
        cmd.serverURL = serverURL
        try await cmd.run()
        pauseForRead()
    }

    private func runPnL() async throws {
        print()
        var cmd = PnLCommand()
        cmd.serverURL = serverURL
        try await cmd.run()
        pauseForRead()
    }

    private func runHistory() async throws {
        print()
        var cmd = HistoryCommand()
        try await cmd.run()
        pauseForRead()
    }

    // MARK: - Add Transaction Menu

    private func runAddMenu() async throws {
        let items = [
            "購入",
            "売却",
            "レンディング預入",
            "レンディング解除",
            "利息受取",
            "ウォレット間移動",
            "外部からの受取",
            "外部への送出",
            "支払い",
            "← 戻る",
        ]

        guard let idx = try ui.select(prompt: "取引の種類を選択", items: items) else { return }

        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)
        let txRepo = TransactionRepository(db: db)
        let accounts = try repo.fetchAll()

        switch idx {
        case 0: try runBuyFlow(accounts: accounts, repo: repo, txRepo: txRepo)
        case 1: try runSellFlow(accounts: accounts, repo: repo, txRepo: txRepo)
        case 2: try runLendFlow(accounts: accounts, repo: repo, txRepo: txRepo)
        case 3: try runUnlendFlow(accounts: accounts, repo: repo, txRepo: txRepo)
        case 4: try runInterestFlow(accounts: accounts, repo: repo, txRepo: txRepo)
        case 5: try runTransferFlow(accounts: accounts, repo: repo, txRepo: txRepo)
        case 6: try runReceiveFlow(accounts: accounts, repo: repo, txRepo: txRepo)
        case 7: try runSendFlow(accounts: accounts, repo: repo, txRepo: txRepo)
        case 8: try runPaymentFlow(accounts: accounts, repo: repo, txRepo: txRepo)
        case 9: return
        default: break
        }
    }

    // MARK: - Add Flows

    private func runBuyFlow(
        accounts: [Account], repo: AccountRepository, txRepo: TransactionRepository
    ) throws {
        guard let token = try selectToken() else { return }

        let exchanges = accounts.filter { $0.type == AccountType.exchange.rawValue }
        guard let fromId = try selectAccount("取引所を選択", from: exchanges) else { return }

        guard let toId = try selectAccount("受取アカウントを選択", from: accounts) else { return }

        guard let amount = readField("取得量") else { return }

        let jpy: String
        let rate: String?
        if token == "USDC" {
            guard let resolvedRate = readField("USD/JPYレート") else { return }
            rate = resolvedRate
            // JPY総額 = 取得量 × レート（自動計算）
            if let a = Decimal(string: amount), let r = Decimal(string: resolvedRate) {
                jpy = formatJpy(a * r)
            } else {
                guard let resolvedJpy = readField("支払JPY総額") else { return }
                jpy = resolvedJpy
            }
        } else {
            // JPYC は 1:1 なので amount がそのまま JPY 総額
            jpy = amount
            rate = nil
        }
        let fee   = readOptionalField("手数料 (JPY)  スキップはEnter")
        let notes = readOptionalField("メモ         スキップはEnter")

        let record = TransactionRecord(
            id: UUID().uuidString, date: Date(),
            type: TransactionType.buy.rawValue, token: token,
            fromAccountId: fromId, toAccountId: toId,
            amount: amount, receivedAmount: nil,
            jpyAmount: jpy, usdJpyRate: rate,
            feeJpy: fee, notes: notes
        )
        try txRepo.insert(record)
        print("✓ buy を記録しました: \(token) \(amount)")
        pauseForRead()
    }

    private func runSellFlow(
        accounts: [Account], repo: AccountRepository, txRepo: TransactionRepository
    ) throws {
        guard let token = try selectToken() else { return }

        let wallets = accounts.filter { $0.type == AccountType.wallet.rawValue }
        guard let fromId = try selectAccount("送出アカウントを選択", from: wallets) else { return }

        let exchanges = accounts.filter { $0.type == AccountType.exchange.rawValue }
        guard let toId = try selectAccount("取引所を選択", from: exchanges) else { return }

        guard let amount = readField("売却量") else { return }

        let jpy: String
        let rate: String?
        if token == "USDC" {
            guard let resolvedRate = readField("USD/JPYレート") else { return }
            rate = resolvedRate
            if let a = Decimal(string: amount), let r = Decimal(string: resolvedRate) {
                jpy = formatJpy(a * r)
            } else {
                guard let resolvedJpy = readField("受取JPY総額") else { return }
                jpy = resolvedJpy
            }
        } else {
            // JPYC は 1:1 なので amount がそのまま JPY 総額
            jpy = amount
            rate = nil
        }
        let fee   = readOptionalField("手数料 (JPY)  スキップはEnter")
        let notes = readOptionalField("メモ         スキップはEnter")

        let record = TransactionRecord(
            id: UUID().uuidString, date: Date(),
            type: TransactionType.sell.rawValue, token: token,
            fromAccountId: fromId, toAccountId: toId,
            amount: amount, receivedAmount: nil,
            jpyAmount: jpy, usdJpyRate: rate,
            feeJpy: fee, notes: notes
        )
        try txRepo.insert(record)
        print("✓ sell を記録しました: \(token) \(amount)")
        pauseForRead()
    }

    private func runLendFlow(
        accounts: [Account], repo: AccountRepository, txRepo: TransactionRepository
    ) throws {
        guard let token = try selectToken() else { return }

        let wallets = accounts.filter { $0.type == AccountType.wallet.rawValue }
        guard let fromId = try selectAccount("送出アカウントを選択", from: wallets) else { return }

        let platforms = accounts.filter { $0.type == AccountType.lendingPlatform.rawValue }
        guard let toId = try selectAccount("プラットフォームを選択", from: platforms) else { return }

        guard let amount = readField("預入量") else { return }
        let fee   = readOptionalField("手数料 (JPY)  スキップはEnter")
        let notes = readOptionalField("メモ         スキップはEnter")

        let record = TransactionRecord(
            id: UUID().uuidString, date: Date(),
            type: TransactionType.lend.rawValue, token: token,
            fromAccountId: fromId, toAccountId: toId,
            amount: amount, receivedAmount: nil,
            jpyAmount: nil, usdJpyRate: nil,
            feeJpy: fee, notes: notes
        )
        try txRepo.insert(record)
        print("✓ lend を記録しました: \(token) \(amount)")
        pauseForRead()
    }

    private func runUnlendFlow(
        accounts: [Account], repo: AccountRepository, txRepo: TransactionRepository
    ) throws {
        guard let token = try selectToken() else { return }

        let platforms = accounts.filter { $0.type == AccountType.lendingPlatform.rawValue }
        guard let fromId = try selectAccount("プラットフォームを選択", from: platforms) else { return }

        let wallets = accounts.filter { $0.type == AccountType.wallet.rawValue }
        guard let toId = try selectAccount("受取アカウントを選択", from: wallets) else { return }

        guard let amount = readField("返還量") else { return }
        let fee   = readOptionalField("手数料 (JPY)  スキップはEnter")
        let notes = readOptionalField("メモ         スキップはEnter")

        let record = TransactionRecord(
            id: UUID().uuidString, date: Date(),
            type: TransactionType.unlend.rawValue, token: token,
            fromAccountId: fromId, toAccountId: toId,
            amount: amount, receivedAmount: nil,
            jpyAmount: nil, usdJpyRate: nil,
            feeJpy: fee, notes: notes
        )
        try txRepo.insert(record)
        print("✓ unlend を記録しました: \(token) \(amount)")
        pauseForRead()
    }

    private func runInterestFlow(
        accounts: [Account], repo: AccountRepository, txRepo: TransactionRepository
    ) throws {
        guard let token = try selectToken() else { return }

        let platforms = accounts.filter { $0.type == AccountType.lendingPlatform.rawValue }
        guard let toId = try selectAccount("プラットフォームを選択", from: platforms) else { return }

        guard let amount = readField("受取量") else { return }
        let rate  = token == "USDC" ? readField("USD/JPYレート") : nil
        let notes = readOptionalField("メモ  スキップはEnter")

        let record = TransactionRecord(
            id: UUID().uuidString, date: Date(),
            type: TransactionType.interest.rawValue, token: token,
            fromAccountId: nil, toAccountId: toId,
            amount: amount, receivedAmount: nil,
            jpyAmount: nil, usdJpyRate: rate,
            feeJpy: nil, notes: notes
        )
        try txRepo.insert(record)
        print("✓ interest を記録しました: \(token) \(amount)")
        pauseForRead()
    }

    private func runTransferFlow(
        accounts: [Account], repo: AccountRepository, txRepo: TransactionRepository
    ) throws {
        guard let token = try selectToken() else { return }

        guard let fromId = try selectAccount("送出アカウントを選択", from: accounts) else { return }
        guard let toId   = try selectAccount("受取アカウントを選択", from: accounts) else { return }

        guard let amount = readField("送出量") else { return }
        let received = readOptionalField("着金量（手数料で減る場合）  スキップはEnter")
        let fee      = readOptionalField("手数料 (JPY)  スキップはEnter")
        let notes    = readOptionalField("メモ         スキップはEnter")

        let record = TransactionRecord(
            id: UUID().uuidString, date: Date(),
            type: TransactionType.transfer.rawValue, token: token,
            fromAccountId: fromId, toAccountId: toId,
            amount: amount, receivedAmount: received,
            jpyAmount: nil, usdJpyRate: nil,
            feeJpy: fee, notes: notes
        )
        try txRepo.insert(record)
        print("✓ transfer を記録しました: \(token) \(amount)")
        pauseForRead()
    }

    private func runReceiveFlow(
        accounts: [Account], repo: AccountRepository, txRepo: TransactionRepository
    ) throws {
        guard let token = try selectToken() else { return }
        guard let toId  = try selectAccount("受取アカウントを選択", from: accounts) else { return }

        guard let amount = readField("受取量") else { return }
        let fee   = readOptionalField("手数料 (JPY)  スキップはEnter")
        let notes = readOptionalField("メモ         スキップはEnter")

        let record = TransactionRecord(
            id: UUID().uuidString, date: Date(),
            type: TransactionType.receive.rawValue, token: token,
            fromAccountId: nil, toAccountId: toId,
            amount: amount, receivedAmount: nil,
            jpyAmount: nil, usdJpyRate: nil,
            feeJpy: fee, notes: notes
        )
        try txRepo.insert(record)
        print("✓ receive を記録しました: \(token) \(amount)")
        pauseForRead()
    }

    private func runSendFlow(
        accounts: [Account], repo: AccountRepository, txRepo: TransactionRepository
    ) throws {
        guard let token  = try selectToken() else { return }
        guard let fromId = try selectAccount("送出アカウントを選択", from: accounts) else { return }

        guard let amount = readField("送出量") else { return }
        let fee   = readOptionalField("手数料 (JPY)  スキップはEnter")
        let notes = readOptionalField("メモ         スキップはEnter")

        let record = TransactionRecord(
            id: UUID().uuidString, date: Date(),
            type: TransactionType.send.rawValue, token: token,
            fromAccountId: fromId, toAccountId: nil,
            amount: amount, receivedAmount: nil,
            jpyAmount: nil, usdJpyRate: nil,
            feeJpy: fee, notes: notes
        )
        try txRepo.insert(record)
        print("✓ send を記録しました: \(token) \(amount)")
        pauseForRead()
    }

    private func runPaymentFlow(
        accounts: [Account], repo: AccountRepository, txRepo: TransactionRepository
    ) throws {
        guard let token  = try selectToken() else { return }
        guard let fromId = try selectAccount("送出アカウントを選択", from: accounts) else { return }

        guard let amount = readField("支払量") else { return }

        let jpy: String?
        let rate: String?
        if token == "USDC" {
            guard let resolvedJpy = readField("決済時JPY相当額") else { return }
            guard let resolvedRate = readField("USD/JPYレート") else { return }
            jpy = resolvedJpy
            rate = resolvedRate
        } else {
            // JPYCは1:1なのでamountをそのまま使う
            jpy = amount
            rate = nil
        }

        let fee   = readOptionalField("手数料 (JPY)  スキップはEnter")
        let notes = readOptionalField("メモ         スキップはEnter")

        let record = TransactionRecord(
            id: UUID().uuidString, date: Date(),
            type: TransactionType.payment.rawValue, token: token,
            fromAccountId: fromId, toAccountId: nil,
            amount: amount, receivedAmount: nil,
            jpyAmount: jpy, usdJpyRate: rate,
            feeJpy: fee, notes: notes
        )
        try txRepo.insert(record)
        print("✓ payment を記録しました: \(token) \(amount)")
        pauseForRead()
    }

    // MARK: - Account Menu

    private func runAccountMenu() async throws {
        let items = ["アカウント一覧", "アカウント追加", "← 戻る"]
        guard let idx = try ui.select(prompt: "アカウント管理", items: items) else { return }

        switch idx {
        case 0:
            print()
            var cmd = AccountCommand.List()
            try await cmd.run()
            pauseForRead()
        case 1:
            try runAccountAddFlow()
        default:
            return
        }
    }

    private func runAccountAddFlow() throws {
        let typeItems = ["wallet", "exchange", "lendingPlatform"]
        guard let typeIdx = try ui.select(prompt: "アカウント種別を選択", items: typeItems) else { return }
        let resolvedType = typeItems[typeIdx]

        guard let resolvedLabel = readField("ラベル") else { return }

        let db   = try DatabaseManager(path: DatabaseManager.defaultPath())
        let repo = AccountRepository(db: db)

        let account = Account(
            id: UUID().uuidString,
            type: resolvedType,
            label: resolvedLabel,
            url: nil,
            contractAddress: nil
        )
        try repo.insert(account)

        if resolvedType == AccountType.wallet.rawValue {
            let chainItems = ["ethereum", "polygon", "avalanche"]
            guard let chainIdx = try ui.select(prompt: "チェーンを選択", items: chainItems) else { return }
            guard let resolvedAddress = readField("アドレス") else { return }

            let depositAddr = DepositAddress(
                id: UUID().uuidString,
                accountId: account.id,
                chain: chainItems[chainIdx],
                address: resolvedAddress
            )
            try repo.insertDepositAddress(depositAddr)
        }

        print("✓ アカウントを追加しました: \(resolvedLabel) (\(resolvedType))")
        pauseForRead()
    }

    // MARK: - Input Helpers

    /// Token picker (JPYC / USDC). Returns nil if cancelled.
    private func selectToken() throws -> String? {
        let tokens = ["JPYC", "USDC"]
        guard let idx = try ui.select(prompt: "トークンを選択", items: tokens) else { return nil }
        return tokens[idx]
    }

    /// Account picker from a filtered list. Returns the account ID, or nil if cancelled.
    private func selectAccount(_ promptText: String, from accounts: [Account]) throws -> String? {
        if accounts.isEmpty {
            print("該当するアカウントがありません。先にアカウントを追加してください。")
            pauseForRead()
            return nil
        }
        let labels = accounts.map { $0.label }
        guard let idx = try ui.select(prompt: promptText, items: labels) else { return nil }
        return accounts[idx].id
    }

    /// Prompt for a required text field. Returns nil if user enters an empty string.
    private func readField(_ label: String) -> String? {
        print("\(label): ", terminator: "")
        fflush(stdout)
        let value = readLine() ?? ""
        return value.isEmpty ? nil : value
    }

    /// Prompt for an optional text field. Returns nil if user presses Enter without input.
    private func readOptionalField(_ label: String) -> String? {
        print("\(label): ", terminator: "")
        fflush(stdout)
        let value = readLine() ?? ""
        return value.isEmpty ? nil : value
    }

    /// Print confirmation and wait for Enter before returning to the menu.
    private func pauseForRead() {
        print("（Enterで戻る）", terminator: "")
        fflush(stdout)
        _ = readLine()
    }

    // MARK: - Logo

    private func printLogo() {
        let T = true, F = false

        let glyphs: [[[Bool]]] = [
            // S
            [[F,T,T,T,F],
             [T,F,F,F,T],
             [T,F,F,F,F],
             [F,T,T,T,F],
             [F,F,F,F,T],
             [T,F,F,F,T],
             [F,T,T,T,F]],
            // C
            [[F,T,T,T,F],
             [T,F,F,F,T],
             [T,F,F,F,F],
             [T,F,F,F,F],
             [T,F,F,F,F],
             [T,F,F,F,T],
             [F,T,T,T,F]],
            // I
            [[T,T,T],
             [F,T,F],
             [F,T,F],
             [F,T,F],
             [F,T,F],
             [F,T,F],
             [T,T,T]],
            // O
            [[F,T,T,T,F],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [F,T,T,T,F]],
            // N
            [[T,F,F,F,T],
             [T,T,F,F,T],
             [T,F,T,F,T],
             [T,F,F,T,T],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [T,F,F,F,T]],
        ]

        let spacing  = 1
        let shadowDX = 1
        let shadowDY = 1
        let rows     = 7

        let faceWidth = glyphs.reduce(0) { $0 + $1[0].count } + spacing * (glyphs.count - 1)
        let canvasW   = faceWidth + shadowDX
        let canvasH   = rows      + shadowDY

        var canvas = Array(repeating: Array(repeating: 0, count: canvasW), count: canvasH)

        var x0 = 0
        for glyph in glyphs {
            let gw = glyph[0].count
            for r in 0..<rows {
                for c in 0..<gw {
                    guard glyph[r][c] else { continue }
                    let sy = r + shadowDY, sx = x0 + c + shadowDX
                    if canvas[sy][sx] < 2 { canvas[sy][sx] = 1 }
                    canvas[r][x0 + c] = 2
                }
            }
            x0 += gw + spacing
        }

        for row in canvas {
            var line = ""
            for (col, pixel) in row.enumerated() {
                switch pixel {
                case 2:
                    let t = Double(col) / Double(faceWidth - 1)
                    let (r, g, b) = gradientColor(t: t)
                    line += "\u{1B}[38;2;\(r);\(g);\(b)m█"
                case 1:
                    line += "\u{1B}[38;2;10;28;85m█"
                default:
                    line += " "
                }
            }
            line += "\u{1B}[0m"
            print(line)
        }
        print()
    }

    // MARK: - Gradient

    private func gradientColor(t: Double) -> (Int, Int, Int) {
        let t = max(0.0, min(1.0, t))
        if t <= 0.5 {
            let s = t / 0.5
            return (lerp(1, 9, s), lerp(103, 154, s), lerp(236, 226, s))
        } else {
            let s = (t - 0.5) / 0.5
            return (lerp(9, 27, s), lerp(154, 190, s), lerp(226, 208, s))
        }
    }

    private func lerp(_ a: Int, _ b: Int, _ t: Double) -> Int {
        Int((Double(a) + Double(b - a) * t).rounded())
    }
}
