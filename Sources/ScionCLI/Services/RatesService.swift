import Foundation
import GRDB

struct RateCache: Codable, FetchableRecord, PersistableRecord {
    var token: String
    var rateJpy: Double
    var fetchedAt: Date

    static let databaseTableName = "rate_cache"
}

struct RatesService {
    let dbManager: DatabaseManager
    let serverURL: String
    private let cacheTTL: TimeInterval = 3600  // 1時間

    func fetchRates() async throws -> [String: Decimal] {
        // キャッシュ確認
        if let cached = try cachedRates() {
            return cached
        }
        // Vaporサーバーから取得
        guard let url = URL(string: "\(serverURL)/rates") else {
            throw RatesError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RatesError.serverError
        }
        let decoded = try JSONDecoder().decode(RatesResponse.self, from: data)
        try updateCache(usdc: decoded.USDC, jpyc: decoded.JPYC)
        return [
            "USDC": Decimal(decoded.USDC),
            "JPYC": Decimal(decoded.JPYC),
        ]
    }

    private func cachedRates() throws -> [String: Decimal]? {
        try dbManager.pool.read { db in
            let caches = try RateCache.fetchAll(db)
            guard caches.count == 2 else { return nil }
            let now = Date()
            guard caches.allSatisfy({ now.timeIntervalSince($0.fetchedAt) < cacheTTL }) else { return nil }
            return Dictionary(uniqueKeysWithValues: caches.map { ($0.token, Decimal($0.rateJpy)) })
        }
    }

    private func updateCache(usdc: Double, jpyc: Double) throws {
        try dbManager.pool.write { db in
            try RateCache(token: "USDC", rateJpy: usdc, fetchedAt: Date()).save(db)
            try RateCache(token: "JPYC", rateJpy: jpyc, fetchedAt: Date()).save(db)
        }
    }
}

private struct RatesResponse: Decodable {
    let USDC: Double
    let JPYC: Double
}

enum RatesError: Error {
    case invalidURL
    case serverError
}
