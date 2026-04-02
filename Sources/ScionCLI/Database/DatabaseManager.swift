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
            .appendingPathComponent(".scion")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fputs("警告: データベースディレクトリの作成に失敗しました: \(error.localizedDescription)\n", stderr)
        }
        return dir.appendingPathComponent("db.sqlite").path
    }
}
