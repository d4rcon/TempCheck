import Foundation

public enum HistoryStoreError: LocalizedError {
    case invalidArchive
    case unsupportedVersion(Int)
    case archiveTooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidArchive: return "Nie udało się odczytać zapisanej historii."
        case .unsupportedVersion: return "Historia została zapisana w nieobsługiwanej wersji formatu."
        case .archiveTooLarge: return "Plik historii przekracza obsługiwany rozmiar."
        }
    }
}

/// Call load/save on the same background queue. The explicit URL also keeps tests isolated.
public final class HistoryStore: Sendable {
    public let url: URL
    private let maximumBytes = 64 * 1024 * 1024
    private struct Archive: Codable {
        let version: Int
        let history: History
    }
    public init(url: URL) { self.url = url }
    public func load(now: Date = Date()) throws -> History {
        guard FileManager.default.fileExists(atPath: url.path) else { return History() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > maximumBytes { throw HistoryStoreError.archiveTooLarge }
        let data = try Data(contentsOf: url)
        let archive: Archive
        do { archive = try PropertyListDecoder().decode(Archive.self, from: data) }
        catch { throw HistoryStoreError.invalidArchive }
        guard archive.version == 1 else { throw HistoryStoreError.unsupportedVersion(archive.version) }
        var history = archive.history; history.trim(now: now); return history
    }
    public func save(_ history: History, now: Date = Date()) throws {
        var retained = history; retained.trim(now: now)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(Archive(version: 1, history: retained))
        guard data.count <= maximumBytes else { throw HistoryStoreError.archiveTooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
