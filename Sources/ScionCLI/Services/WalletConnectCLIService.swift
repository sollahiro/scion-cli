import Foundation
import WalletConnectSign
import Combine

/// CLI上でWalletConnectセッションを確立し、EVMアドレスを取得するサービス
final class WalletConnectCLIService: @unchecked Sendable {
    private var cancellables = Set<AnyCancellable>()

    /// WalletConnectを初期化する
    /// - Parameter projectId: WalletConnect Cloud のプロジェクトID
    func configure(projectId: String) {
        let metadata = AppMetadata(
            name: "Scion CLI",
            description: "電子決済手段（JPYC/USDC）取引管理ツール",
            url: "https://github.com/sollahiro/scion",
            icons: []
        )
        Sign.configure(projectId: projectId, metadata: metadata)
    }

    /// 接続URIを生成して返す
    func generateURI() async throws -> WalletConnectURI {
        let namespaces: [String: ProposalNamespace] = [
            "eip155": ProposalNamespace(
                chains: [
                    Blockchain("eip155:1")!,      // Ethereum
                    Blockchain("eip155:137")!,     // Polygon
                    Blockchain("eip155:43114")!,   // Avalanche
                ],
                methods: ["eth_sendTransaction", "personal_sign", "eth_signTypedData"],
                events: ["accountsChanged", "chainChanged"]
            )
        ]
        return try await Sign.instance.connect(requiredNamespaces: namespaces)
    }

    /// ウォレットが接続するまで待機し、EVMアドレスを返す
    /// - Parameter timeout: タイムアウト秒数（デフォルト120秒）
    func waitForConnection(timeout: TimeInterval = 120) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var settled = false
            var timer: Timer?

            timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                guard !settled else { return }
                settled = true
                continuation.resume(throwing: WCError.timeout)
            }

            Sign.instance.sessionSettlePublisher
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] session in
                    guard !settled else { return }
                    settled = true
                    timer?.invalidate()
                    self?.cancellables.removeAll()

                    // eip155 の最初のアカウントからアドレスを取得
                    let address = session.namespaces
                        .values
                        .flatMap { $0.accounts }
                        .first { $0.blockchain.namespace == "eip155" }?
                        .address
                        ?? session.namespaces.values.flatMap { $0.accounts }.first?.address
                        ?? ""

                    if address.isEmpty {
                        continuation.resume(throwing: WCError.noAddress)
                    } else {
                        continuation.resume(returning: address)
                    }
                }
                .store(in: &cancellables)
        }
    }

    /// アクティブなセッションのアドレス一覧を返す
    func activeSessions() -> [(address: String, topic: String)] {
        Sign.instance.getSessions().compactMap { session in
            guard let address = session.namespaces
                .values.flatMap({ $0.accounts })
                .first(where: { $0.blockchain.namespace == "eip155" })?
                .address
            else { return nil }
            return (address: address, topic: session.topic)
        }
    }

    /// セッションを切断する
    func disconnect(topic: String) async throws {
        try await Sign.instance.disconnect(topic: topic)
    }
}

enum WCError: LocalizedError {
    case timeout
    case noAddress
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .timeout:      return "WalletConnect: 接続タイムアウトしました（120秒）"
        case .noAddress:    return "WalletConnect: アドレスを取得できませんでした"
        case .notConfigured: return "WalletConnect: PROJECT_IDが設定されていません"
        }
    }
}
