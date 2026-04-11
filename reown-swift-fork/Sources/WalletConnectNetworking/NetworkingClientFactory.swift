import Foundation

public struct NetworkingClientFactory {

    public static func create(
        relayClient: RelayClient,
        groupIdentifier: String
    ) -> NetworkingInteractor {
        let logger = ConsoleLogger(prefix: "🕸️", loggingLevel: .off)

        guard let keyValueStorage = UserDefaults(suiteName: groupIdentifier) else {
            fatalError("Could not instantiate UserDefaults for a group identifier \(groupIdentifier)")
        }

        // macOS CLI apps don't have App Group entitlements; pass nil to skip access group
        #if os(macOS)
        let keychainStorage = KeychainStorage(serviceIdentifier: "com.walletconnect.sdk", accessGroup: nil)
        #else
        let keychainStorage = KeychainStorage(serviceIdentifier: "com.walletconnect.sdk", accessGroup: groupIdentifier)
        #endif
        return NetworkingClientFactory.create(relayClient: relayClient, logger: logger, keychainStorage: keychainStorage, keyValueStorage: keyValueStorage)
    }

    public static func create(relayClient: RelayClient, logger: ConsoleLogging, keychainStorage: KeychainStorageProtocol, keyValueStorage: KeyValueStorage, kmsLogger: ConsoleLogging = ConsoleLogger(prefix: "🔐", loggingLevel: .off)) -> NetworkingInteractor {
        let kms = KeyManagementService(keychain: keychainStorage)

        let serializer = Serializer(kms: kms, logger: kmsLogger)

        let rpcHistory = RPCHistoryFactory.createForNetwork(keyValueStorage: keyValueStorage)

        return NetworkingInteractor(
            relayClient: relayClient,
            serializer: serializer,
            logger: logger,
            rpcHistory: rpcHistory)
    }
}
