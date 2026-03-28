import Foundation
import GRDB

final class DatabaseManager: Sendable {
    let pool: DatabasePool

    init(path: String) throws {
        pool = try DatabasePool(path: path)
        var migrator = DatabaseMigrator()
        Migrations.register(in: &migrator)
        try migrator.migrate(pool)
    }

    static func defaultPath() -> String {
        let dir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".cypraea")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("db.sqlite").path
    }
}
