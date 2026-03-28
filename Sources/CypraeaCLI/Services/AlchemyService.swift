import Foundation

// MARK: - AlchemyTransfer

struct AlchemyTransfer {
    let hash: String
    let blockTime: Date
    let from: String
    let to: String
    let value: Decimal
    let asset: String           // "USDC" / "JPYC"
    let contractAddress: String
}

// MARK: - AlchemyService

struct AlchemyService {
    let apiKey: String
    let network: String  // e.g. "eth-mainnet", "polygon-mainnet"

    // [network: [tokenName: (contractAddress, decimals)]]
    static let tokenContracts: [String: [String: (address: String, decimals: Int)]] = [
        "eth-mainnet": [
            "USDC": ("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", 6),
            "JPYC": ("0x2370f9d504c7a6E775bf6E14B3F12846b594cD53", 18),
        ],
        "polygon-mainnet": [
            "USDC":   ("0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359", 6),
            "USDC.e": ("0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", 6),
            "JPYC":   ("0x431D5dfF03120AFA4bDf332c61A6e1766eF37BF6", 18),
        ],
    ]

    /// `DepositAddress.chain` 文字列を Alchemy ネットワーク名に変換
    static func alchemyNetwork(from chain: String) -> String {
        switch chain.lowercased() {
        case "ethereum", "eth", "eth-mainnet": return "eth-mainnet"
        case "polygon", "matic", "polygon-mainnet": return "polygon-mainnet"
        default: return chain
        }
    }

    /// ウォレットアドレスのオンチェーントークン残高を取得（USDC / JPYC）
    func fetchTokenBalances(address: String) async throws -> [String: Decimal] {
        guard let contracts = Self.tokenContracts[network] else { return [:] }
        let contractAddrs = contracts.values.map(\.address)

        let body: [String: Any] = [
            "id": 1,
            "jsonrpc": "2.0",
            "method": "alchemy_getTokenBalances",
            "params": [address, contractAddrs],
        ]
        let data = try await jsonRPC(body: body)
        let response = try JSONDecoder().decode(TokenBalancesRPCResponse.self, from: data)

        var result: [String: Decimal] = [:]
        for tb in response.result.tokenBalances {
            guard let (tokenName, info) = contracts.first(where: {
                $0.value.address.lowercased() == tb.contractAddress.lowercased()
            }) else { continue }
            let balance = hexToDecimal(tb.tokenBalance, decimals: info.decimals)
            // USDC.e は USDC に合算
            let key = tokenName == "USDC.e" ? "USDC" : tokenName
            result[key, default: 0] += balance
        }
        return result
    }

    /// ウォレットアドレスの ERC-20 転送履歴を取得（送受信両方）
    func fetchAssetTransfers(address: String, fromBlock: String = "0x0") async throws -> [AlchemyTransfer] {
        guard let contracts = Self.tokenContracts[network] else { return [] }
        let contractAddrs = contracts.values.map(\.address)

        async let inbound = fetchTransfers(
            toAddress: address, contractAddresses: contractAddrs, fromBlock: fromBlock)
        async let outbound = fetchTransfers(
            fromAddress: address, contractAddresses: contractAddrs, fromBlock: fromBlock)

        let (inTx, outTx) = try await (inbound, outbound)

        // 送受信が同一 tx になる場合を排除しつつマージ
        var seen = Set<String>()
        return (inTx + outTx).filter { seen.insert($0.hash + $0.from + ($0.to)).inserted }
    }

    // MARK: - Private

    private var baseURL: URL {
        URL(string: "https://\(network).g.alchemy.com/v2/\(apiKey)")!
    }

    private func fetchTransfers(
        fromAddress: String? = nil,
        toAddress: String? = nil,
        contractAddresses: [String],
        fromBlock: String
    ) async throws -> [AlchemyTransfer] {
        var params: [String: Any] = [
            "contractAddresses": contractAddresses,
            "category": ["erc20"],
            "withMetadata": true,
            "excludeZeroValue": true,
            "fromBlock": fromBlock,
            "maxCount": "0x64",  // 最大100件
        ]
        if let from = fromAddress { params["fromAddress"] = from }
        if let to = toAddress { params["toAddress"] = to }

        let body: [String: Any] = [
            "id": 1,
            "jsonrpc": "2.0",
            "method": "alchemy_getAssetTransfers",
            "params": [params],
        ]
        let data = try await jsonRPC(body: body)
        let response = try JSONDecoder().decode(AssetTransfersRPCResponse.self, from: data)

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()

        return response.result.transfers.compactMap { t in
            guard let timestamp = t.metadata?.blockTimestamp,
                  let date = isoFull.date(from: timestamp) ?? isoBasic.date(from: timestamp),
                  let value = t.value
            else { return nil }

            let contractAddr = t.rawContract?.address ?? ""
            let rawName = Self.tokenContracts[network]?
                .first(where: { $0.value.address.lowercased() == contractAddr.lowercased() })?
                .key ?? (t.asset ?? contractAddr)
            let tokenName = rawName == "USDC.e" ? "USDC" : rawName

            return AlchemyTransfer(
                hash: t.hash,
                blockTime: date,
                from: t.from,
                to: t.to ?? "",
                value: Decimal(string: "\(value)") ?? 0,
                asset: tokenName,
                contractAddress: contractAddr
            )
        }
    }

    private func jsonRPC(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AlchemyError.serverError
        }
        if let errResp = try? JSONDecoder().decode(RPCErrorResponse.self, from: data),
           let msg = errResp.error?.message {
            throw AlchemyError.rpcError(msg)
        }
        return data
    }

    /// 16進数文字列 → Decimal（decimals 分だけスケール）
    private func hexToDecimal(_ hex: String, decimals: Int) -> Decimal {
        let stripped = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        if stripped.isEmpty || stripped.allSatisfy({ $0 == "0" }) { return 0 }
        var result: Decimal = 0
        for char in stripped.lowercased() {
            let digit: Int
            switch char {
            case "0"..."9": digit = Int(char.asciiValue! - 48)
            case "a"..."f": digit = Int(char.asciiValue! - 87)
            default: return 0
            }
            result = result * 16 + Decimal(digit)
        }
        var divisor: Decimal = 1
        for _ in 0..<decimals { divisor *= 10 }
        return result / divisor
    }
}

// MARK: - Errors

enum AlchemyError: Error, LocalizedError {
    case serverError
    case rpcError(String)
    case unsupportedNetwork(String)

    var errorDescription: String? {
        switch self {
        case .serverError: return "Alchemy サーバーエラー"
        case .rpcError(let msg): return "Alchemy RPC エラー: \(msg)"
        case .unsupportedNetwork(let n): return "未対応ネットワーク: \(n)"
        }
    }
}

// MARK: - Private Codable Response Types

private struct TokenBalancesRPCResponse: Decodable {
    let result: Result
    struct Result: Decodable {
        let address: String
        let tokenBalances: [TokenBalance]
    }
    struct TokenBalance: Decodable {
        let contractAddress: String
        let tokenBalance: String
    }
}

private struct AssetTransfersRPCResponse: Decodable {
    let result: Result
    struct Result: Decodable {
        let transfers: [Transfer]
    }
    struct Transfer: Decodable {
        let hash: String
        let from: String
        let to: String?
        let value: Double?
        let asset: String?
        let metadata: Metadata?
        let rawContract: RawContract?
        struct Metadata: Decodable {
            let blockTimestamp: String
        }
        struct RawContract: Decodable {
            let address: String?
        }
    }
}

private struct RPCErrorResponse: Decodable {
    let error: RPCErrorDetail?
    struct RPCErrorDetail: Decodable {
        let message: String
    }
}
