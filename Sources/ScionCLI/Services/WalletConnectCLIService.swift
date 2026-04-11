import Foundation
@preconcurrency import WalletConnectSign
@preconcurrency import WalletConnectNetworking
@preconcurrency import WalletConnectRelay
import WalletConnectPairing
import WalletConnectSigner
import Combine

// MARK: - WebSocketFactory (URLSession-based, no Starscream needed)

private final class URLSessionWebSocket: NSObject, WebSocketConnecting, URLSessionWebSocketDelegate {
    var isConnected: Bool = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    private var task: URLSessionWebSocketTask?
    private lazy var session: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    init(url: URL) {
        self.request = URLRequest(url: url)
    }

    func connect() {
        guard let url = request.url else { return }
        task = session.webSocketTask(with: url)
        task?.resume()
        receive()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
    }

    func write(string: String, completion: (() -> Void)?) {
        task?.send(.string(string)) { _ in completion?() }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        onConnect?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        onDisconnect?(nil)
    }

    private func receive() {
        task?.receive { [weak self] result in
            switch result {
            case .success(.string(let text)):
                self?.onText?(text)
                self?.receive()
            case .success(.data):
                self?.receive()
            case .failure(let error):
                self?.isConnected = false
                self?.onDisconnect?(error)
            @unknown default:
                break
            }
        }
    }
}

private struct URLSessionWebSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        URLSessionWebSocket(url: url)
    }
}

// MARK: - CryptoProvider (stub — only session pairing is used, not SIWE)

private struct StubCryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        throw CryptoError.notSupported
    }
    func keccak256(_ data: Data) -> Data {
        // Pure-Swift Keccak-256 (Ethereum variant of SHA-3 pre-standardization)
        return Keccak256.hash(data)
    }
    private enum CryptoError: Error { case notSupported }
}

// MARK: - Minimal Keccak-256 implementation

private enum Keccak256 {
    static func hash(_ data: Data) -> Data {
        var state = [UInt64](repeating: 0, count: 25)
        var message = [UInt8](data) + [0x01]
        let rate = 136 // 1088 bits / 8

        // Pad to rate boundary
        let padLen = rate - (message.count % rate)
        message += [UInt8](repeating: 0, count: padLen)
        message[message.count - 1] ^= 0x80

        for block in stride(from: 0, to: message.count, by: rate) {
            for i in 0..<(rate / 8) {
                state[i] ^= UInt64(littleEndian: message.withUnsafeBytes {
                    $0.load(fromByteOffset: block + i * 8, as: UInt64.self)
                })
            }
            keccakF(&state)
        }

        return Data(state[0..<4].flatMap { $0.littleEndianBytes })
    }

    private static let RC: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
    ]

    private static func keccakF(_ state: inout [UInt64]) {
        var bc = [UInt64](repeating: 0, count: 5)
        for round in 0..<24 {
            // Theta
            for i in 0..<5 { bc[i] = state[i] ^ state[i+5] ^ state[i+10] ^ state[i+15] ^ state[i+20] }
            for i in 0..<5 {
                let t = bc[(i+4)%5] ^ rotl(bc[(i+1)%5], 1)
                for j in stride(from: 0, to: 25, by: 5) { state[j+i] ^= t }
            }
            // Rho & Pi
            var last = state[1]
            for i in 0..<24 {
                let (pi, rho) = piRho[i]
                let tmp = state[pi]
                state[pi] = rotl(last, rho)
                last = tmp
            }
            // Chi
            for j in stride(from: 0, to: 25, by: 5) {
                let t = (0..<5).map { state[j+$0] }
                for i in 0..<5 { state[j+i] ^= (~t[(i+1)%5]) & t[(i+2)%5] }
            }
            // Iota
            state[0] ^= RC[round]
        }
    }

    private static func rotl(_ x: UInt64, _ n: Int) -> UInt64 { (x << n) | (x >> (64 - n)) }

    private static let piRho: [(Int, Int)] = [
        (10,1),(7,62),(11,28),(17,27),(18,36),(3,44),(5,6),(16,55),(8,20),
        (21,3),(24,10),(4,43),(15,25),(23,39),(19,41),(13,45),(12,15),(2,21),
        (20,8),(14,18),(22,2),(9,61),(6,56),(1,14)
    ]
}

private extension UInt64 {
    var littleEndianBytes: [UInt8] {
        (0..<8).map { UInt8((self >> ($0 * 8)) & 0xff) }
    }
}

// MARK: - WalletConnectCLIService

/// CLI上でWalletConnectセッションを確立し、EVMアドレスを取得するサービス
final class WalletConnectCLIService: @unchecked Sendable {
    private var cancellables = Set<AnyCancellable>()

    /// WalletConnectを初期化する
    /// - Parameter projectId: WalletConnect Cloud のプロジェクトID
    func configure(projectId: String) {
        Networking.configure(
            groupIdentifier: "com.scion.cli",
            projectId: projectId,
            socketFactory: URLSessionWebSocketFactory()
        )

        let metadata = AppMetadata(
            name: "Scion CLI",
            description: "電子決済手段（JPYC/USDC）取引管理ツール",
            url: "https://github.com/sollahiro/scion",
            icons: [],
            redirect: try! AppMetadata.Redirect(native: "", universal: nil)
        )
        Pair.configure(metadata: metadata)
        Sign.configure(crypto: StubCryptoProvider())
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
                .sink { [weak self] output in
                    guard !settled else { return }
                    settled = true
                    timer?.invalidate()
                    self?.cancellables.removeAll()

                    // eip155 の最初のアカウントからアドレスを取得
                    let session = output.session
                    let allAccounts = session.namespaces.values.flatMap { $0.accounts }
                    let eip155Account = allAccounts.first { $0.blockchain.namespace == "eip155" }
                    let address = eip155Account?.address ?? allAccounts.first?.address ?? ""

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
